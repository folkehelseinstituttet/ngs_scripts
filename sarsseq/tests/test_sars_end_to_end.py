"""Run the real wrapper completion paths through submission and accession import."""
import csv
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import pytest
from test_sars_wrapper_master_update import run_env, run_tail

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).with_name('fixtures')


@pytest.mark.parametrize('kind', ['routine-fastq', 'routine-fasta', 'fasta'])
def test_wrapper_master_qc_export_and_accession_round_trip(run_env, tmp_path, kind):
    env, master, run_out, _ = run_env
    master.write_bytes((FIXTURES / 'master.csv').read_bytes())
    metadata = master.with_name('NGS_PREP_SC2_report.csv')
    metadata.write_bytes((FIXTURES / 'metadata.csv').read_bytes())
    workflow = 'fastq' if kind == 'routine-fastq' else 'fasta'
    report = run_out / 'report/SART001_with_software_versions.csv'
    report.write_bytes((FIXTURES / (workflow + '_report.csv')).read_bytes())
    result = run_tail(kind, env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (master.parent / 'master.fasta').is_file()
    qc = json.loads((run_out / 'report/SART001_qc.json').read_text())
    assert qc['samples'][0]['qpcr']['status'] == 'Positive qPCR'
    assert qc['samples'][0]['coverage']['Genome'] == 95
    for suffix in ('html', 'json'):
        remote = Path(env['QC_TEST_ROOT']) / f'results/SART001/report/SART001_qc.{suffix}'
        assert remote.read_bytes() == (run_out / f'report/SART001_qc.{suffix}').read_bytes()

    config = {'schema_version': 1, 'pathogen': 'SC2', 'key_column': 'Prove_LW_ID', 'csv_delimiter': ';',
              'edit_columns': ['GISAID_Kommentar'], 'default_columns': [],
              'review_options': ['Approved', 'Rejected', 'Needs follow-up']}
    master.with_name('config.json').write_text(json.dumps(config))
    reviews = master.parent / 'reviews'
    reviews.mkdir()
    with master.open(encoding='utf-8-sig') as handle:
        row = next(csv.DictReader(handle, delimiter=';'))
    pairs = sorted([key, value] for key, value in row.items() if key != 'Prove_LW_ID' and value != '')
    event = {'format_version': 1, 'id': 'synthetic-review', 'pathogen': 'SC2', 'key': '001',
             'key_columns': ['Prove_LW_ID'], 'supersedes': [], 'created_at': '2026-02-05T12:00:00Z',
             'result_hash': 'sha256:' + hashlib.sha256(json.dumps(pairs, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest(),
             'review': {'reviewer': 'TEST', 'assessment': 'Approved', 'comment': '', 'overrides': {}}}
    (reviews / 'review.json').write_text(json.dumps(event))
    labs = tmp_path / 'labs.csv'
    labs.write_text('Innsender_nr;Innsender_navn;Innsender_adresse\n0001;Synthetic lab;Synthetic address\n')
    validator = ROOT / 'sarsseq/master_csv/validate_deployment.py'
    checked = subprocess.run([sys.executable, str(validator), '--workflow', workflow, '--report', str(report),
                              '--master', str(master), '--metadata', str(metadata), '--fasta', str(run_out / 'report/SART001.fasta'),
                              '--lab', str(labs), '--reviews'], capture_output=True, text=True)
    assert checked.returncode == 0, checked.stderr
    assert json.loads(checked.stdout)['approval_counts']['approved'] == 1
    output = tmp_path / 'submission'
    export = subprocess.run([sys.executable, str(ROOT / 'gisaid/sars-cov-2/sc2_gisaid_csv.py'), 'SART001', 'TEST',
                             '--master', str(master), '--lab-lookup', str(labs), '--output-dir', str(output),
                             '--prefix', 'synthetic', '--assembly-method', 'Synthetic method'], capture_output=True, text=True)
    assert export.returncode == 0, export.stderr
    with (output / 'synthetic.csv').open() as handle:
        name = next(csv.DictReader(handle))['covv_virus_name']
    assert (output / 'synthetic.fasta').read_text().splitlines()[0] == '>' + name
    returned = tmp_path / 'returned.tsv'
    returned.write_text(f'Virus name\tAccession ID\n{name}\tEPI_ISL_123456\nunmatched\tEPI_ISL_789\n')
    before = master.read_bytes()
    command = [sys.executable, str(ROOT / 'gisaid/sars-cov-2/import_gisaid_accessions.py'), '--master', str(master),
               '--manifest', str(output / 'synthetic.manifest.json'), str(returned)]
    preview = subprocess.run(command + ['--dry-run'], capture_output=True, text=True)
    assert preview.returncode == 0 and master.read_bytes() == before
    imported = subprocess.run(command, capture_output=True, text=True)
    assert imported.returncode == 0, imported.stderr
    stats = json.loads(imported.stdout)
    assert stats['written'] and stats['skipped_unmatched'] == 1
    assert Path(stats['backup']).read_bytes() == before
    after = master.read_bytes()
    retry = subprocess.run(command, capture_output=True, text=True)
    assert retry.returncode == 0 and not json.loads(retry.stdout)['written']
    assert master.read_bytes() == after
    # Review fingerprints cover accession columns too; historical approvals remain immutable.
    reader = subprocess.run(['node', str(ROOT / 'gisaid/shared/approved_master.cjs'), '--master', str(master),
                             '--pathogen', 'SC2'], capture_output=True, text=True)
    assert reader.returncode == 0, reader.stderr
    assert json.loads(reader.stdout)['counts']['stale'] == 1
    assert json.loads((reviews / 'review.json').read_text()) == event
    assert not Path(str(master) + '.lock').exists()
    # A routine re-merge must preserve returned accession IDs and remain idempotent.
    repeated_run = run_tail(kind, env)
    assert repeated_run.returncode == 0, repeated_run.stdout + repeated_run.stderr
    assert master.read_bytes() == after


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_deployment_checks_only_read_source_derived_fixtures(tmp_path, workflow):
    before = {path: path.read_bytes() for path in FIXTURES.iterdir() if path.is_file()}
    result = subprocess.run([sys.executable, str(ROOT / 'sarsseq/master_csv/validate_deployment.py'),
        '--workflow', workflow, '--report', str(FIXTURES / (workflow + '_report.csv')),
        '--master', str(FIXTURES / 'master.csv'), '--metadata', str(FIXTURES / 'metadata.csv'),
        '--fasta', str(FIXTURES / 'run.fasta')], cwd=tmp_path, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data['writes'] is False and data['report']['samples'] == data['fasta_records'] == 1
    assert data['qc_context'] == 'previewed master'
    assert data['qc_counts']['qpcr']['Positive qPCR'] == 1
    assert all(path.read_bytes() == content for path, content in before.items())
    assert not list(tmp_path.iterdir())
