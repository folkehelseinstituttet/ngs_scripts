"""Approval-filtered Nextstrain inputs using R only and synthetic local data."""
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
from zipfile import ZipFile

import pytest
from test_approved_exports import GISAID, make_dataset, review, write_csv

NEXTSTRAIN = Path(os.environ.get('TEST_NEXTSTRAIN_DIR', GISAID.parent / 'nextstrain'))
SCRIPTS = {'INF': 'influenza/INF_master_csv.R', 'SC2': 'sars-cov-2/SC2_META.R'}


def command(master, tmp_path, pathogen):
    args = ['--master', str(master), '--lab', str(tmp_path / 'labs.csv'), '--output', str(tmp_path / 'output')]
    if pathogen == 'INF': args += ['--staging', str(tmp_path / 'staging')]
    return ['Rscript', str(NEXTSTRAIN / SCRIPTS[pathogen]), *args]


def run(master, tmp_path, pathogen):
    return subprocess.run(command(master, tmp_path, pathogen), capture_output=True, text=True, timeout=60,
                          env={**os.environ, 'GISAID_NODE': '/missing/node',
                               'GISAID_SHARED_DIR': str(GISAID / 'shared'), 'TZ': 'UTC'})


def xlsx_rows(path):
    ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    with ZipFile(path) as archive:
        shared = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            shared = [''.join(element.itertext()) for element in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        rows = []
        for row in ET.fromstring(archive.read('xl/worksheets/sheet1.xml')).findall('.//m:row', ns):
            cells = {}
            for cell in row:
                text = cell.find('m:v', ns)
                value = text.text or '' if text is not None else ''
                if cell.get('t') == 's': value = shared[int(value)]
                elif cell.get('t') == 'inlineStr': value = ''.join(cell.find('m:is', ns).itertext())
                cells[''.join(c for c in cell.get('r') if c.isalpha())] = value
            rows.append(cells)
    return [dict((name, row.get(column, '')) for column, name in rows[0].items()) for row in rows[1:]]


def metadata(tmp_path, pathogen):
    if pathogen == 'SC2':
        with next((tmp_path / 'output').glob('*.tsv')).open() as handle:
            return list(csv.DictReader(handle, delimiter='\t'))
    return [row for path in (tmp_path / 'output').rglob('metadata.xlsx') for row in xlsx_rows(path)]


def fasta_headers(tmp_path):
    return [line[1:] for path in (tmp_path / 'output').rglob('*.fasta')
            for line in path.read_text().splitlines() if line.startswith('>')]


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_nextstrain_only_current_approved_with_overrides_and_existing_filters(tmp_path, pathogen):
    master, rows = make_dataset(tmp_path, pathogen, 9)
    rows[6]['NC_Coverage'] = '0.74'; rows[6]['NGS_Sekvens_Resultat'] = 'N1'
    rows[8]['NC_Coverage'] = '0.60'; rows[8]['NGS_Sekvens_Resultat'] = 'N2'
    rows[0]['Pasient_Fylke_Name'] = 'Oslo'; rows[0]['Pasient_Fylke_Nr'] = '03'
    rows[0]['GISAID_Isolate_ID'] = 'EPI_ISL_12345'
    rows[0]['GISAID_Kommentar'] = 'Previously submitted; still eligible for Nextstrain'
    rows[7]['NC_Coverage'] = '0,75'
    write_csv(master, rows)
    cfg_path = master.with_name('config.json'); cfg = json.loads(cfg_path.read_text())
    cfg['edit_columns'] += ['Pasient_Fylke_Name', 'Pasient_Fylke_Nr', 'NGS_LW_ID']
    cfg_path.write_text(json.dumps(cfg))
    review(master, rows[0], 'current', overrides={'Pasient_Fylke_Name': 'Møre og Romsdal', 'Pasient_Fylke_Nr': '15', 'NGS_LW_ID': 'edited-id'})
    review(master, rows[1], 'stale', stale=True)
    review(master, rows[2], 'rejected', assessment='Rejected')
    review(master, rows[3], 'conflict1'); review(master, rows[3], 'conflict2')
    review(master, rows[4], 'approved-old'); review(master, rows[4], 'followup', assessment='Needs follow-up', supersedes=['approved-old'])
    review(master, rows[6], 'filtered')
    review(master, rows[7], 'second-current', overrides={'NGS_Sekvens_Resultat': 'B/Victoria'})
    review(master, rows[8], 'filtered-too')
    before = {path: path.read_bytes() for path in master.parent.rglob('*') if path.is_file()}
    result = run(master, tmp_path, pathogen)
    assert result.returncode == 0, result.stdout + result.stderr
    data = metadata(tmp_path, pathogen)
    assert len(data) == 2
    names = [row['Isolate_Name' if pathogen == 'INF' else 'strain'] for row in data]
    assert set(fasta_headers(tmp_path)) == set(names)
    assert any('Møre og Romsdal' in row.get('Location', row.get('division', '')) for row in data)
    if pathogen == 'INF':
        assert next((tmp_path / 'output').rglob('VIC/raw_sequences_ha.fasta')).read_text().startswith('>B/Norway/')
        assert all((tmp_path / 'staging' / path.relative_to(path.parents[1])).exists()
                   for path in (tmp_path / 'output').rglob('metadata.xlsx'))
    else:
        assert [row['gisaid_epi_isl'] for row in data] == ['EPI_ISL_12345', '']
        assert all(row['originating_lab'] == 'Synthetic lab' for row in data)
        assert all(row['length'] == '6' for row in data)
    assert all(path.read_bytes() == value for path, value in before.items())


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
@pytest.mark.parametrize('failure', ['no-approved', 'missing-config', 'missing-reviews', 'malformed',
                                    'wrong-pathogen', 'missing-parent', 'unknown-policy', 'ambiguous-id'])
def test_nextstrain_approval_failure_writes_no_outputs(tmp_path, pathogen, failure):
    master, rows = make_dataset(tmp_path, pathogen, 2)
    if failure == 'ambiguous-id':
        rows[1]['NGS_LW_ID'] = rows[0]['NGS_LW_ID']; write_csv(master, rows)
    if failure != 'no-approved':
        path = review(master, rows[0], 'current')
        if failure == 'missing-config': master.with_name('config.json').unlink()
        if failure == 'missing-reviews': shutil.rmtree(path.parent)
        if failure == 'malformed': path.write_text('{')
        if failure in {'wrong-pathogen', 'missing-parent', 'unknown-policy'}:
            event = json.loads(path.read_text())
            event.update({'wrong-pathogen': {'pathogen': 'WRONG'}, 'missing-parent': {'supersedes': ['missing']},
                          'unknown-policy': {'policy_version': 'unsupported'}}[failure])
            path.write_text(json.dumps(event))
    result = run(master, tmp_path, pathogen)
    assert result.returncode != 0, result.stdout
    assert not (tmp_path / 'output').exists()
    assert not (tmp_path / 'staging').exists()


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_nextstrain_rechecks_review_snapshot_before_writing(tmp_path, pathogen):
    master, rows = make_dataset(tmp_path, pathogen)
    review(master, rows[0], 'current')
    cli = command(master, tmp_path, pathogen)
    code = ('a <- commandArgs(TRUE); source(a[1]); original <- assert_approved_master; '
            'assert_approved_master <- function(master, pathogen, token) {'
            'cat("\\n", file=master, append=TRUE); original(master, pathogen, token)}; main(a[-1])')
    result = subprocess.run(['Rscript', '-e', code, *cli[1:]], capture_output=True, text=True, timeout=60,
                            env={**os.environ, 'GISAID_NODE': '/missing/node', 'GISAID_SHARED_DIR': str(GISAID / 'shared'), 'TZ': 'UTC'})
    assert result.returncode != 0 and 'changed during export' in result.stderr
    assert not (tmp_path / 'output').exists() and not (tmp_path / 'staging').exists()


def test_sc2_nextstrain_minimum_date_keeps_exclusive_boundary(tmp_path):
    master, rows = make_dataset(tmp_path, 'SC2', 3)
    rows[0]['Prove_Tatt'] = '2025-01-01'; rows[1]['Prove_Tatt'] = '2024-12-31'; rows[2]['Prove_Tatt'] = '2025-01-02'
    write_csv(master, rows)
    for i, row in enumerate(rows): review(master, row, f'current{i}')
    result = run(master, tmp_path, 'SC2')
    assert result.returncode == 0, result.stderr
    assert [row['date'] for row in metadata(tmp_path, 'SC2')] == ['2025-01-02']


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_nextstrain_source_finds_shared_reader_without_working_directory_or_node(tmp_path, pathogen):
    master, rows = make_dataset(tmp_path, pathogen)
    review(master, rows[0], 'current')
    checkout = tmp_path / 'checkout with spaces'
    script = checkout / 'nextstrain' / SCRIPTS[pathogen]
    script.parent.mkdir(parents=True)
    shutil.copyfile(NEXTSTRAIN / SCRIPTS[pathogen], script)
    shutil.copytree(GISAID / 'shared', checkout / 'gisaid/shared')
    (checkout / 'gisaid/sars-cov-2').mkdir()
    shutil.copyfile(GISAID / 'sars-cov-2/sc2_export.R', checkout / 'gisaid/sars-cov-2/sc2_export.R')
    args = command(master, tmp_path, pathogen)[2:]
    env = {**os.environ, 'GISAID_NODE': '/missing/node', 'TEST_SCRIPT': str(script), 'TZ': 'UTC'}
    env.pop('GISAID_SHARED_DIR', None)
    code = ('nextstrain_args <- unlist(jsonlite::fromJSON(' + json.dumps(json.dumps(args)) + ')); '
            'source(Sys.getenv("TEST_SCRIPT"), encoding="UTF-8")')
    result = subprocess.run(['Rscript', '-e', code], cwd=tmp_path, env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr
    assert metadata(tmp_path, pathogen)


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_nextstrain_rejects_old_node_helper_before_attempting_execution(tmp_path, pathogen):
    old_shared = tmp_path / 'old shared'; old_shared.mkdir()
    (old_shared / 'approval.R').write_text('read_approved_master <- function(helper, master, pathogen) stop("must not run Node")\n')
    result = subprocess.run(['Rscript', str(NEXTSTRAIN / SCRIPTS[pathogen]), '--help'],
                            capture_output=True, text=True, timeout=15,
                            env={**os.environ, 'GISAID_SHARED_DIR': str(old_shared), 'GISAID_NODE': '/missing/node'})
    assert result.returncode != 0 and 'Outdated Sequence Review reader:' in result.stderr
    assert 'must not run Node' not in result.stderr


def test_influenza_matches_original_sequence_id_alias(tmp_path):
    master, rows = make_dataset(tmp_path, 'INF')
    rows[0]['Sequence_ID'] = 'original-alias'; rows[0]['NGS_LW_ID'] = ''
    write_csv(master, rows)
    master.with_name('master.fasta').write_text('>original-alias|01-HA-H1N1\nACGT\n')
    review(master, rows[0], 'current')
    result = run(master, tmp_path, 'INF')
    assert result.returncode == 0, result.stderr
    assert fasta_headers(tmp_path) == ['A/Norway/00000/2026']
