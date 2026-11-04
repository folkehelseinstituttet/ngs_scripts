"""Accession matching and file transactions using synthetic SC2 records."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import stat
import sys

import pytest
from test_approved_exports import make_dataset, write_csv

SCRIPT = Path(__file__).resolve().parents[1] / 'sars-cov-2/import_gisaid_accessions.py'
spec = importlib.util.spec_from_file_location('sc2_accessions', SCRIPT)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


@pytest.fixture
def files(tmp_path):
    master, rows = make_dataset(tmp_path, count=2)
    returned = tmp_path / 'returned.tsv'
    returned.write_text('Virus name\tAccession ID\n'
                        'hCoV-19/Norway/00000/2026\tEPI_ISL_12345\n'
                        'hCoV-19/Norway/unknown/2026\tEPI_ISL_99999\n'
                        '\tEPI_ISL_77777\n')
    return master, returned, rows


def test_import_preview_backup_unicode_preservation_and_retry(files):
    master, returned, rows = files
    master.chmod(0o640)
    before = master.read_bytes()
    preview = importer.import_accessions(master, [returned], dry_run=True)
    assert preview['updated_samples'] == 1 and preview['values_added'] == 2
    assert preview['skipped_unmatched'] == preview['skipped_missing_identifier'] == 1
    assert master.read_bytes() == before and not list(master.parent.glob('*.bak.*'))
    stats = importer.import_accessions(master, [returned])
    assert stats['written'] and Path(stats['backup']).read_bytes() == before
    assert stat.S_IMODE(master.stat().st_mode) == stat.S_IMODE(Path(stats['backup']).stat().st_mode) == 0o640
    headers, actual = importer.read_table(master)
    assert actual[0]['GISAID_Isolate_ID'] == 'EPI_ISL_12345'
    assert actual[0]['GISAID_Isolate_Name'] == 'hCoV-19/Norway/00000/2026'
    assert {k: actual[0][k] for k in rows[0]} == rows[0]
    assert {k: actual[1][k] for k in rows[1]} == rows[1]
    after, mtime = master.read_bytes(), master.stat().st_mtime_ns
    assert not importer.import_accessions(master, [returned])['written']
    assert master.read_bytes() == after and master.stat().st_mtime_ns == mtime
    assert len(list(master.parent.glob('*.bak.*'))) == 1
    assert not Path(str(master) + '.lock').exists()


@pytest.mark.parametrize('problem', ['existing-id', 'returned-id', 'duplicate-key', 'ambiguous-name',
                                   'accession-reused', 'invalid-id', 'disagreeing-key', 'unknown-key'])
def test_conflicts_do_not_write_and_release_owned_lock(files, problem):
    master, returned, rows = files
    record = {'Virus name': 'hCoV-19/Norway/00000/2026', 'Accession ID': 'EPI_ISL_12345'}
    records = [record]
    if problem == 'existing-id':
        rows[0]['GISAID_Isolate_ID'] = 'EPI_ISL_54321'
    elif problem == 'returned-id':
        records.append({**record, 'Accession ID': 'EPI_ISL_54321'})
    elif problem == 'duplicate-key':
        rows[1]['Key'] = rows[0]['Key']
    elif problem == 'ambiguous-name':
        rows[1]['Key'] = '242600000'
    elif problem == 'accession-reused':
        rows[1]['GISAID_Isolate_ID'] = 'EPI_ISL_12345'
    elif problem == 'invalid-id':
        record['Accession ID'] = 'EPI_12345'
    elif problem in {'disagreeing-key', 'unknown-key'}:
        record['Submitting_Sample_Id'] = rows[1]['Key'] if problem == 'disagreeing-key' else 'unknown'
    write_csv(master, rows)
    write_csv(returned, records)
    before = master.read_bytes()
    with pytest.raises(ValueError):
        importer.import_accessions(master, [returned])
    assert master.read_bytes() == before
    assert not list(master.parent.glob('*.bak.*'))
    assert not Path(str(master) + '.lock').exists()


def test_identical_multiple_exports_and_blank_values(files, tmp_path):
    master, returned, rows = files
    extra = write_csv(tmp_path / 'extra.csv', [{'Submitting_Sample_Id': rows[0]['Key'], 'Isolate_Id': '', 'Isolate_Name': ''}])
    result = importer.import_accessions(master, [returned, returned, extra])
    assert result['values_added'] == 2 and result['updated_samples'] == 1


def test_unknown_samples_are_skipped_even_with_invalid_accessions(files):
    master, returned, _ = files
    returned.write_text('Virus name\tAccession ID\nunknown\tinvalid\n')
    before = master.read_bytes()
    stats = importer.import_accessions(master, [returned])
    assert not stats['written'] and stats['skipped_unmatched'] == 1
    assert master.read_bytes() == before


def test_stored_name_and_manifest_match_without_reconstructing_keys(files, tmp_path):
    master, returned, rows = files
    name = 'hCoV-19/Norway/reviewed-name/2026'
    manifest = tmp_path / 'submission.manifest.json'
    manifest.write_text(json.dumps({'format_version': 1, 'pathogen': 'SC2',
                                   'approvals': [{'virus_name': name, 'fasta_id': 'SEQ0'}]}))
    returned.write_text('Virus name\tAccession ID\n' + name + '\tEPI_ISL_12345\n')
    assert importer.import_accessions(master, [returned], manifest)['written']
    # A subsequent import matches the stored exact name even without the manifest.
    assert not importer.import_accessions(master, [returned])['written']


@pytest.mark.parametrize('problem', ['ambiguous-alias', 'conflicting-name', 'duplicate-name', 'wrong-pathogen'])
def test_manifest_conflicts_fail_before_writing(files, tmp_path, problem):
    master, returned, rows = files
    entry = {'virus_name': 'hCoV-19/Norway/00000/2026', 'fasta_id': 'SEQ0'}
    manifest = {'format_version': 1, 'pathogen': 'SC2', 'approvals': [entry]}
    if problem == 'ambiguous-alias':
        rows[1]['OriginalName'] = 'SEQ0'
    elif problem == 'conflicting-name':
        entry['fasta_id'] = 'SEQ1'
    elif problem == 'duplicate-name':
        manifest['approvals'].append(dict(entry))
    else:
        manifest['pathogen'] = 'INF'
    write_csv(master, rows)
    path = tmp_path / 'manifest.json'
    path.write_text(json.dumps(manifest))
    before = master.read_bytes()
    with pytest.raises(ValueError):
        importer.import_accessions(master, [returned], path)
    assert master.read_bytes() == before
    assert not Path(str(master) + '.lock').exists()


def test_existing_lock_is_never_removed(files):
    master, returned, _ = files
    lock = Path(str(master) + '.lock')
    lock.mkdir()
    before = master.read_bytes()
    with pytest.raises(ValueError, match='locked'):
        importer.import_accessions(master, [returned])
    assert lock.is_dir() and master.read_bytes() == before
    assert importer.import_accessions(master, [returned], dry_run=True)['dry_run']
    assert lock.is_dir()


@pytest.mark.parametrize('problem', ['replace', 'concurrent', 'backup', 'final-readback'])
def test_transaction_failures_preserve_evidence_and_clean_lock(files, monkeypatch, problem):
    master, returned, _ = files
    before = master.read_bytes()
    original_write, original_digest, original_replace = importer.write_table, importer.digest, importer.os.replace
    replaced = False

    def write(path, headers, rows):
        original_write(path, headers, rows)
        if problem == 'concurrent':
            master.write_text('Key\nexternal-edit\n')

    def replace(source, target):
        nonlocal replaced
        if problem == 'replace':
            raise OSError('simulated replacement failure')
        original_replace(source, target)
        replaced = True

    def digest(path):
        if (problem == 'backup' and '.bak.' in str(path)) or (problem == 'final-readback' and replaced and Path(path) == master):
            return 'corrupt'
        return original_digest(path)

    monkeypatch.setattr(importer, 'write_table', write)
    monkeypatch.setattr(importer, 'digest', digest)
    monkeypatch.setattr(importer.os, 'replace', replace)
    with pytest.raises((OSError, ValueError)):
        importer.import_accessions(master, [returned])
    assert not Path(str(master) + '.lock').exists()
    assert not list(master.parent.glob('.*.tmp'))
    backups = list(master.parent.glob('*.bak.*'))
    if problem == 'concurrent':
        assert master.read_text() == 'Key\nexternal-edit\n' and not backups
    else:
        assert len(backups) == 1 and backups[0].read_bytes() == before
        assert (master.read_bytes() == before) == (problem != 'final-readback')


def test_cli_and_separate_input_guard(files, tmp_path):
    master, returned, _ = files
    result = subprocess.run([sys.executable, str(SCRIPT), '--master', str(master), str(returned)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout)['written']
    alias = tmp_path / 'alias.csv'
    os.link(master, alias)
    with pytest.raises(ValueError, match='separate'):
        importer.import_accessions(master, [alias])
