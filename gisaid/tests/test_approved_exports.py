"""Synthetic submission tests: local files only, no GISAID/network calls."""

import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

GISAID = Path(__file__).resolve().parents[1]
HELPER = GISAID / 'shared/approved_master.cjs'
# The archived Python exporter remains an independent reference for R parity.
SC2 = GISAID / 'sars-cov-2/archive/sc2_gisaid_csv.py'
INF = GISAID / 'influenza/influenza_gisaid_csv.R'
spec = importlib.util.spec_from_file_location('sc2_export', SC2)
sc2_export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc2_export)


def write_csv(path, rows, headers=None):
    headers = headers or list(dict.fromkeys(key for row in rows for key in row))
    with path.open('w', encoding='utf-8-sig', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, delimiter=';', lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    return path


def make_dataset(tmp_path, pathogen='SC2', count=1):
    root = tmp_path / pathogen
    root.mkdir()
    (root / 'reviews').mkdir()
    config = {'schema_version': 1, 'pathogen': pathogen, 'key_column': 'Prove_LW_ID',
              'csv_delimiter': ';', 'review_options': ['Approved', 'Needs follow-up', 'Rejected'],
              'edit_columns': ['GISAID_Kommentar', 'NGS_Sekvens_Resultat'], 'default_columns': []}
    (root / 'config.json').write_text(json.dumps(config))
    rows = []
    for i in range(count):
        rows.append({'Key': f'2526{i:05}', 'Prove_LW_ID': f'{i:03}', 'NGS_LW_ID': f'SEQ{i}',
                     'NGS_Run_ID': 'RUN', 'GISAID_Kommentar': '', 'NC_Coverage': '0.95',
                     'Prove_Tatt': '2026-02-03', 'Pasient_Fylke_Name': 'Tr ndelag',
                     'Pasient_Kjnn': 'F', 'Pasient_Fylke_Nr': '50', 'Pasient_Alder': '30',
                     'Prove_Innsender_ID': '001', 'Prove_Kategori': 'P1_', 'Prove_Material': 'NAPHSEKR',
                     'Pasient_Status': 'Poliklinisk', 'NGS_Depth': '100', 'NGS_Primer_vers': 'TEST',
                     'NGS_Sekvens_Resultat': 'A/H1N1', 'NGS_QC_Sum': '',
                     **{f'NGS_Reads_{gene}': '100' for gene in ('HA', 'NA', 'M', 'NS', 'NP', 'PA', 'PB1', 'PB2')}})
    master = write_csv(root / 'master.csv', rows)
    if pathogen == 'SC2':
        fasta = ''.join(f">{row['NGS_LW_ID']} synthetic description\nACGTNN\n" for row in rows)
    else:
        fasta = ''.join(f">{row['NGS_LW_ID']}|01-HA-H1N1\nACGTNN\n>{row['NGS_LW_ID']}|02-NA-H1N1\nACGTNN\n" for row in rows)
    (root / 'master.fasta').write_text(fasta)
    write_csv(tmp_path / 'labs.csv', [{'Innsender_nr': '001', 'Innsender_navn': 'Synthetic lab',
                                    'Innsender_adresse': 'Test address', 'GISAID_Id': '123'}])
    return master, rows


def review(master, row, event_id, assessment='Approved', supersedes=(), overrides=None, stale=False, **changes):
    # Independent implementation of the documented v1 hash for these ASCII headers.
    config = json.loads(master.with_name('config.json').read_text())
    keys = config.get('key_columns', [config['key_column']])
    pairs = sorted([key, value] for key, value in row.items() if key not in keys and value != '')
    fingerprint = 'sha256:' + hashlib.sha256(json.dumps(pairs, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    key = row[keys[0]] if len(keys) == 1 else json.dumps([row[name] for name in keys], separators=(',', ':'))
    event = {'format_version': 1, 'id': event_id, 'pathogen': config['pathogen'], 'key': key,
             'key_columns': keys, 'result_hash': 'sha256:' + '0' * 64 if stale else fingerprint,
             'created_at': '2026-02-04T12:00:00Z', 'supersedes': list(supersedes),
             'review': {'reviewer': 'TEST', 'assessment': assessment, 'comment': '', 'overrides': overrides or {}}}
    event.update(changes)
    path = master.parent / 'reviews' / (event_id + '.json')
    path.write_text(json.dumps(event))
    return path


def approved(master, pathogen='SC2', extra=()):
    return subprocess.run(['node', str(HELPER), '--master', str(master), '--pathogen', pathogen, *extra],
                          capture_output=True, text=True, timeout=15)


def sc2_command(master, tmp_path, extra=()):
    return [sys.executable, str(SC2), 'RUN', 'synthetic-submitter', '--master', str(master),
            '--lab-lookup', str(tmp_path / 'labs.csv'), '--output-dir', str(tmp_path / 'output'),
            '--prefix', 'synthetic', '--assembly-method', 'Synthetic test method', *extra]


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_only_current_conflict_free_approval_and_overrides(tmp_path, pathogen):
    master, rows = make_dataset(tmp_path, pathogen, 7)
    review(master, rows[0], 'current', overrides={'GISAID_Kommentar': 'manual hold'})
    review(master, rows[1], 'stale', stale=True)
    review(master, rows[2], 'rejected', assessment='Rejected')
    review(master, rows[3], 'conflict1')
    review(master, rows[3], 'conflict2')
    review(master, rows[4], 'old-approved')
    review(master, rows[4], 'followup', assessment='Needs follow-up', supersedes=['old-approved'])
    review(master, rows[5], 'old1')
    review(master, rows[5], 'old2')
    review(master, rows[5], 'resolved', supersedes=['old1', 'old2'])
    result = approved(master, pathogen)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert [row['Key'] for row in data['rows']] == [rows[0]['Key'], rows[5]['Key']]
    assert data['rows'][0]['GISAID_Kommentar'] == 'manual hold'
    assert data['counts'] == dict(total=7, approved=2, pending=1, stale=1, conflict=1, not_approved=2)
    assert len(data['identities']) == 7


@pytest.mark.parametrize('failure', ['config', 'reviews', 'malformed', 'wrong-pathogen', 'missing-parent', 'unknown-policy', 'unsupported-override'])
def test_missing_or_invalid_review_state_never_falls_back_to_all_rows(tmp_path, failure):
    master, rows = make_dataset(tmp_path)
    path = review(master, rows[0], 'current')
    if failure == 'config':
        master.with_name('config.json').unlink()
    elif failure == 'reviews':
        shutil.rmtree(path.parent)
    elif failure == 'malformed':
        path.write_text('{')
    else:
        changes = {'wrong-pathogen': {'pathogen': 'INF'}, 'missing-parent': {'supersedes': ['missing']},
                   'unknown-policy': {'policy_version': 'unknown'},
                   'unsupported-override': {'review': {'reviewer': 'TEST', 'assessment': 'Approved',
                                                      'overrides': {'NGS_LW_ID': 'other'}}}}
        event = json.loads(path.read_text())
        event.update(changes[failure])
        path.write_text(json.dumps(event))
    result = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert result.returncode != 0
    assert not (tmp_path / 'output').exists()


def test_reanalysis_invalidates_approval_and_snapshot_token(tmp_path):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    before = json.loads(approved(master).stdout)
    rows[0]['NC_Coverage'] = '0.96'
    write_csv(master, rows)
    changed = json.loads(approved(master).stdout)
    assert changed['rows'] == [] and changed['counts']['stale'] == 1
    result = approved(master, extra=['--expect-token', before['token']])
    assert result.returncode != 0 and 'changed during export' in result.stderr


def test_legacy_review_identifiers_follow_solution_migration(tmp_path):
    master, rows = make_dataset(tmp_path)
    config = json.loads(master.with_name('config.json').read_text())
    config['key_column'] = 'Key'
    master.with_name('config.json').write_text(json.dumps(config))
    review(master, rows[0], 'legacy')
    config.update(key_column='Prove_LW_ID', legacy_key_columns=['Key'])
    master.with_name('config.json').write_text(json.dumps(config))
    result = approved(master)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['approvals'][0]['key'] == '000'


def test_sc2_exports_only_approved_and_metadata_eligible_matching_records(tmp_path):
    master, rows = make_dataset(tmp_path, count=8)
    rows[1]['GISAID_Kommentar'] = 'hold'
    rows[2]['NC_Coverage'] = '0.74'
    rows[3]['NGS_Run_ID'] = 'OTHER'
    rows[4]['Key'] = ''
    rows[7]['NC_Coverage'] = '0,75'
    write_csv(master, rows)
    for i in [0, 1, 2, 3, 4, 6, 7]:
        review(master, rows[i], f'event{i}', stale=(i == 6))
    before = {path: path.read_bytes() for path in master.parent.rglob('*') if path.is_file()}
    result = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    output = tmp_path / 'output'
    with (output / 'synthetic.csv').open() as handle:
        submission = list(csv.DictReader(handle))
    assert [row['covv_virus_name'] for row in submission] == ['hCoV-19/Norway/00000/2026', 'hCoV-19/Norway/00007/2026']
    assert submission[0]['covv_location'] == 'Europe/Norway/Trøndelag'
    assert submission[0]['covv_orig_lab'] == 'Synthetic lab'
    assert submission[0]['covv_orig_lab_addr'] == 'Test address'
    assert submission[0]['fn'] == 'synthetic.fasta'
    assert (output / 'synthetic.fasta').read_text().splitlines() == [
        '>hCoV-19/Norway/00000/2026', 'ACGTNN', '>hCoV-19/Norway/00007/2026', 'ACGTNN']
    manifest = json.loads((output / 'synthetic.manifest.json').read_text())
    assert manifest['samples'] == 2
    assert manifest['master_sha256'] == hashlib.sha256(master.read_bytes()).hexdigest()
    assert manifest['fasta_sha256'] == hashlib.sha256(master.with_name('master.fasta').read_bytes()).hexdigest()
    assert manifest['lab_lookup_sha256'] == hashlib.sha256((tmp_path / 'labs.csv').read_bytes()).hexdigest()
    assert manifest['filter_counts'] == dict(gisaid_comment=1, coverage=1, other_run=1, missing_key=1)
    for name, digest in manifest['outputs'].items():
        assert hashlib.sha256((output / name).read_bytes()).hexdigest() == digest
    assert all(path.read_bytes() == data for path, data in before.items())
    previous = {path: path.read_bytes() for path in output.iterdir()}
    retry = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert retry.returncode != 0 and 'already exists' in retry.stderr
    assert all(path.read_bytes() == data for path, data in previous.items())


@pytest.mark.parametrize('failure', ['unapproved', 'manual-hold', 'missing-sequence', 'duplicate-sequence',
                                    'multiple-aliases', 'ambiguous-master-id', 'bad-date', 'missing-lab',
                                    'duplicate-lab', 'duplicate-name'])
def test_sc2_validation_failure_writes_no_submission(tmp_path, failure):
    master, rows = make_dataset(tmp_path, count=2 if failure in {'ambiguous-master-id', 'duplicate-name'} else 1)
    if failure == 'ambiguous-master-id':
        rows[1]['NGS_LW_ID'] = 'SEQ0'
    if failure == 'duplicate-name':
        rows[1]['Key'] = '242500000'
    if failure == 'bad-date':
        rows[0]['Prove_Tatt'] = 'invalid'
    if failure == 'unapproved':
        rows[0]['NGS_QC_Assessment'] = 'Approved'  # CSV text alone cannot approve a sample.
    write_csv(master, rows)
    if failure != 'unapproved':
        for i, row in enumerate(rows):
            review(master, row, f'event{i}', overrides={'GISAID_Kommentar': 'hold'} if failure == 'manual-hold' else {})
    fasta = master.with_name('master.fasta')
    if failure == 'missing-sequence':
        fasta.write_text('>unrelated\nACGT\n')
    if failure == 'duplicate-sequence':
        fasta.write_text(fasta.read_text() * 2)
    if failure == 'multiple-aliases':
        fasta.write_text(fasta.read_text() + f">{rows[0]['Key']}\nACGT\n")
    if failure in {'missing-lab', 'duplicate-lab'}:
        write_csv(tmp_path / 'labs.csv', [{'Innsender_nr': 'other' if failure == 'missing-lab' else '001',
                                        'Innsender_navn': 'Test'}] * (2 if failure == 'duplicate-lab' else 1))
    result = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert result.returncode != 0, result.stdout
    assert not (tmp_path / 'output').exists()


def test_approval_R_adapter_preserves_text_and_current_approved_rows(tmp_path):
    master, rows = make_dataset(tmp_path, 'INF', 2)
    review(master, rows[0], 'current')
    script = tmp_path / 'test.R'
    script.write_text('args <- commandArgs(TRUE)\nsource(args[1])\n'
                      'data <- read_approved_master(args[3], "INF")\n'
                      'stopifnot(nrow(data$rows) == 1, data$rows$Prove_LW_ID == "000",\n'
                      'data$rows$Prove_Innsender_ID == "001", nrow(data$identities) == 2)\n'
                      'assert_approved_master(args[3], "INF", data$token)\n')
    result = subprocess.run(['Rscript', str(script), str(GISAID / 'shared/approval.R'), str(HELPER), str(master)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert 'Sequence Review approval filter:' in result.stderr


@pytest.mark.parametrize('failure', ['config', 'reviews'])
def test_approval_R_adapter_reports_failure_reason(tmp_path, failure):
    master, _ = make_dataset(tmp_path, 'INF')
    missing = master.with_name('config.json' if failure == 'config' else 'reviews')
    if missing.is_dir():
        missing.rmdir()
    else:
        missing.unlink()
    script = tmp_path / 'test.R'
    script.write_text('args <- commandArgs(TRUE)\nsource(args[1])\n'
                      'read_approved_master(args[2], "INF")\n')
    result = subprocess.run(['Rscript', str(script), str(GISAID / 'shared/approval.R'), str(master)],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode != 0
    assert 'no submission was written' in result.stderr
    assert missing.name in result.stderr
    assert not list(tmp_path.rglob('approved.csv'))


def test_composite_review_keys_match_solution_fingerprints(tmp_path):
    master, rows = make_dataset(tmp_path)
    config = json.loads(master.with_name('config.json').read_text())
    config['key_columns'] = ['Prove_LW_ID', 'NGS_LW_ID']
    master.with_name('config.json').write_text(json.dumps(config))
    review(master, rows[0], 'composite')
    result = approved(master)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['approvals'][0]['key'] == '["000","SEQ0"]'


@pytest.fixture
def r_exporter():
    if not shutil.which('Rscript'):
        pytest.skip('Rscript is required for the existing Flu exporter')
    check = subprocess.run(['Rscript', '-e',
        'p <- c("readr", "dplyr", "tidyr", "tibble", "purrr", "stringr", "magrittr", "lubridate", "jsonlite", "digest"); '
        'quit(status=if(all(vapply(p, requireNamespace, logical(1), quietly=TRUE))) 0 else 1)'],
        capture_output=True, text=True, env={**os.environ, 'TZ': 'UTC'})
    if check.returncode:
        pytest.skip('Install the documented Flu exporter R packages to run its integration tests')
    return {**os.environ, 'TZ': 'UTC'}


def test_inf_export_retains_existing_filters_and_segment_qc(tmp_path, r_exporter):
    master, rows = make_dataset(tmp_path, 'INF', 8)
    rows[0]['NGS_QC_Sum'] = 'HA:FS'
    rows[2]['NGS_Sekvens_Resultat'] = 'NA'
    rows[3]['NGS_Run_ID'] = 'OTHER'
    rows[4]['Key'] = ''
    write_csv(master, rows)
    for i in [0, 1, 2, 3, 4, 6, 7]:
        overrides = {'GISAID_Kommentar': 'manual hold'} if i == 1 else {'NGS_Sekvens_Resultat': 'B/Victoria'} if i == 7 else {}
        review(master, rows[i], f'event{i}', stale=(i == 6), overrides=overrides)
    before = {path: path.read_bytes() for path in master.parent.rglob('*') if path.is_file()}
    output = tmp_path / 'output'
    output.mkdir()
    result = subprocess.run(['Rscript', str(INF), 'RUN', str(master), str(tmp_path / 'labs.csv'), str(output)],
                            env=r_exporter, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    with next(output.glob('*.csv')).open() as handle:
        submission = list(csv.DictReader(handle))
    by_key = {row['Submitting_Sample_Id']: row for row in submission}
    assert set(by_key) == {rows[0]['Key'], rows[7]['Key']}
    assert by_key[rows[0]['Key']]['Seq_Id (HA)'] == ''
    assert by_key[rows[7]['Key']]['Subtype'] == 'B'
    assert by_key[rows[7]['Key']]['Lineage'] == 'Victoria'
    assert by_key[rows[0]['Key']]['province'] == 'Trøndelag'
    lines = next(output.glob('*.fasta')).read_text().splitlines()
    assert set(line for line in lines if line.startswith('>')) == {
        '>NA|' + rows[0]['Key'], '>HA|' + rows[7]['Key'], '>NA|' + rows[7]['Key']}
    assert all(path.read_bytes() == data for path, data in before.items())


@pytest.mark.parametrize('reason', ['no-approved', 'missing-config', 'stale', 'ambiguous-id'])
def test_inf_does_not_export_without_valid_approvals_or_unique_ids(tmp_path, r_exporter, reason):
    master, rows = make_dataset(tmp_path, 'INF', 2)
    if reason == 'ambiguous-id':
        rows[1]['NGS_LW_ID'] = rows[0]['NGS_LW_ID']
        write_csv(master, rows)
    if reason != 'no-approved':
        review(master, rows[0], 'current', stale=reason == 'stale')
    if reason == 'missing-config':
        master.with_name('config.json').unlink()
    output = tmp_path / 'output'
    output.mkdir()
    result = subprocess.run(['Rscript', str(INF), 'RUN', str(master), str(tmp_path / 'labs.csv'), str(output)],
                            env=r_exporter, capture_output=True, text=True, timeout=60)
    assert result.returncode != 0
    assert not list(output.iterdir())


def test_sc2_rechecks_approval_before_writing(tmp_path, monkeypatch):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'approved')
    original = sc2_export.metadata_row

    def changed_review(*args):
        result = original(*args)
        review(master, rows[0], 'rejected', assessment='Rejected', supersedes=['approved'])
        return result

    monkeypatch.setattr(sc2_export, 'metadata_row', changed_review)
    args = type('Args', (), dict(master=master, fasta=None, lab_lookup=tmp_path / 'labs.csv',
                                output_dir=tmp_path / 'output', prefix='synthetic', run='RUN', submitter='TEST',
                                assembly_method='TEST', sequencing_technology='TEST', authors='TEST'))()
    with pytest.raises(ValueError, match='changed during export'):
        sc2_export.export(args)
    assert not args.output_dir.exists()


@pytest.mark.parametrize('field', ['Key', 'Prove_LW_ID', 'OriginalName', 'SampleID'])
def test_sc2_fasta_matching_supports_exact_legacy_aliases(tmp_path, field):
    master, rows = make_dataset(tmp_path)
    if field in {'OriginalName', 'SampleID'}:
        rows[0][field] = 'legacy-name'
        write_csv(master, rows)
    review(master, rows[0], 'current')
    master.with_name('master.fasta').write_text(f">{rows[0][field]} description\nACGTNN\n")
    result = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    manifest = json.loads((tmp_path / 'output/synthetic.manifest.json').read_text())
    assert manifest['approvals'][0]['fasta_id'] == rows[0][field]


def test_sc2_missing_lab_address_is_reported_without_inventing_one(tmp_path):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    write_csv(tmp_path / 'labs.csv', [{'Innsender_nr': '001', 'Innsender_navn': 'Test lab'}])
    result = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout.splitlines()[0])['filter_counts']['missing_lab_address'] == 1
    with (tmp_path / 'output/synthetic.csv').open() as handle:
        assert next(csv.DictReader(handle))['covv_orig_lab_addr'] == ''


@pytest.mark.parametrize('launch', ['source', 'source-from-wrapper', 'console-repo', 'console-gisaid',
                                  'console-influenza', 'console-override',
                                  pytest.param('console-default-share', marks=pytest.mark.skipif(
                                      os.name == 'nt', reason='Simulated N: directory is Linux-only; never write a real mapped drive'))])
def test_inf_source_and_console_launches_without_script_file_argument(tmp_path, r_exporter, launch):
    master, rows = make_dataset(tmp_path, 'INF')
    review(master, rows[0], 'current')
    # Test the portable deployment and shell quoting with paths containing spaces.
    checkout = tmp_path / 'checkout with spaces'
    script = checkout / 'gisaid/influenza/influenza_gisaid_csv.R'
    script.parent.mkdir(parents=True)
    shutil.copyfile(INF, script)
    shared = checkout / 'gisaid/shared'
    shutil.copytree(GISAID / 'shared', shared)
    output = tmp_path / 'submission output'
    output.mkdir()
    env = {**r_exporter, 'TEST_SCRIPT': str(script), 'TEST_MASTER': str(master),
           'TEST_LABS': str(tmp_path / 'labs.csv'), 'TEST_OUTPUT': str(output)}
    env.pop('GISAID_SHARED_DIR', None)
    code = ('gisaid_args <- Sys.getenv(c("TEST_MASTER", "TEST_LABS", "TEST_OUTPUT")); '
            'gisaid_args <- c("RUN", unname(gisaid_args)); ')
    cwd = tmp_path
    if launch.startswith('source'):
        code += 'source(Sys.getenv("TEST_SCRIPT"))'
    else:
        # eval(parse()) simulates console selections: no source frame or --file.
        code += 'eval(parse(text=readLines(Sys.getenv("TEST_SCRIPT"))), envir=.GlobalEnv)'
        cwd = {'console-repo': checkout, 'console-gisaid': checkout / 'gisaid',
               'console-influenza': script.parent, 'console-override': tmp_path,
               'console-default-share': tmp_path}[launch]
        if launch == 'console-override':
            env['GISAID_SHARED_DIR'] = str(shared)
        if launch == 'console-default-share':
            # On Linux N:/ is an ordinary relative path within this isolated test.
            # Execute console code from elsewhere with no helper-path override.
            shutil.copytree(shared, tmp_path / 'N:/Virologi/NGS/tmp/ngs_scripts/gisaid/shared')
    command = ['Rscript', '-e', code]
    if launch == 'source-from-wrapper':
        wrapper = tmp_path / 'outer script.R'
        wrapper.write_text(code)
        command = ['Rscript', str(wrapper)]
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    with next(output.glob('*.csv')).open() as handle:
        assert next(csv.DictReader(handle))['Submitting_Sample_Id'] == rows[0]['Key']


@pytest.mark.parametrize('override', [False, True])
def test_inf_console_missing_helpers_gives_actionable_error(tmp_path, override):
    master, _ = make_dataset(tmp_path, 'INF')
    env = {**os.environ, 'TEST_SCRIPT': str(INF), 'TEST_MASTER': str(master)}
    env.pop('GISAID_SHARED_DIR', None)
    if override:
        env['GISAID_SHARED_DIR'] = str(tmp_path / 'missing shared')
    code = ('gisaid_args <- c("RUN", Sys.getenv("TEST_MASTER")); '
            'eval(parse(text=readLines(Sys.getenv("TEST_SCRIPT"))), envir=.GlobalEnv)')
    result = subprocess.run(['Rscript', '-e', code], cwd=tmp_path, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0
    assert 'GISAID_SHARED_DIR' in result.stderr
    assert 'path[1]=NA' not in result.stderr
    assert not list(tmp_path.glob('*.fasta'))
