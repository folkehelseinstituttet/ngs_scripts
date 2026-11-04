"""SC2 CSV/FASTA integration with the same archive transaction as Influenza."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'master_csv/update_master.py'
spec = importlib.util.spec_from_file_location('sars_fasta_updater', SCRIPT)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
import merge_master_fasta as archive


@pytest.fixture
def inputs(tmp_path):
    root = tmp_path / 'SC2 archive'
    root.mkdir()
    master = root / 'master.csv'
    master.write_text('Prove_LW_ID;NGS_LW_ID\n001;SEQ1\n')
    metadata = tmp_path / 'separate metadata.csv'
    metadata.write_text('Prove_LW_ID;NGS_LW_ID;RekvNr\n001;SEQ1;legacy\n')
    report = tmp_path / 'run.csv'
    report.write_text('Sample;RunID\nSEQ1;RUN1\n')
    fasta = tmp_path / 'run.fasta'
    fasta.write_text('>SEQ1 current\nACGTNN\n>SEQ3\nCCCC\n')
    config, _ = updater.configuration({'SARSSEQ_MASTER_CSV': str(master), 'SARSSEQ_METADATA_CSV': str(metadata)})
    return config, master, report, fasta


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
@pytest.mark.parametrize('exists', [False, True])
def test_archive_uses_master_location_and_preserves_exact_ids(inputs, workflow, exists):
    config, master, report, fasta = inputs
    target = master.with_name('master.fasta')
    before = None
    if exists:
        target.write_text('>SEQ1 previous\nAAAA\n>SEQ2\nCCCC\n>seq1\nNNNN\n')
        target.chmod(0o640)
        before = target.read_bytes()
    result = updater.update(config, report, workflow, fasta)
    assert result['written'] and result['fasta']['written']
    assert result['fasta']['created'] is not exists
    records, _ = archive.read_fasta(target)
    assert records['SEQ1'] == ('SEQ1 current', 'ACGTNN')
    assert records['SEQ3'] == ('SEQ3', 'CCCC')
    if exists:
        assert list(records) == ['SEQ1', 'SEQ2', 'seq1', 'SEQ3']
        assert records['SEQ2'][1] == records['SEQ3'][1]
        assert records['seq1'][1] == 'NNNN'
        assert Path(result['fasta']['backup']).read_bytes() == before
        assert target.stat().st_mode & 0o777 == 0o640
    else:
        assert list(records) == ['SEQ1', 'SEQ3']
        assert not list(target.parent.glob('master.fasta.bak.*'))
    assert not Path(config['metadata']).with_name('master.fasta').exists()
    assert not Path(str(target) + '.lock').exists()
    before_retry = master.read_bytes(), target.read_bytes()
    retried = updater.update(config, report, workflow, fasta)
    assert not retried['written'] and not retried['fasta']['written']
    assert (master.read_bytes(), target.read_bytes()) == before_retry


def test_multiline_bom_whitespace_and_identical_duplicates(inputs):
    config, master, report, fasta = inputs
    target = master.with_name('master.fasta')
    target.write_text('>SEQ1\nACGTNN\n>SEQ1\nACGTNN\n')
    before = target.read_bytes()
    fasta.write_bytes(b'\xef\xbb\xbf>SEQ1\r\nAC GT\r\nN N\r\n\r\n>SEQ1\r\nACGTNN\r\n')
    stats = updater.update(config, report, 'fastq', fasta)['fasta']
    assert stats['input_duplicates_collapsed'] == stats['master_duplicates_collapsed'] == 1
    assert target.read_text() == '>SEQ1\nACGTNN\n'
    assert Path(stats['backup']).read_bytes() == before


@pytest.mark.parametrize('content', [None, 'ACGT\n', '>\nACGT\n', '>EMPTY\n', '>SEQ1\nAC1T\n',
                                    '>SEQ1\nACGT\n>SEQ1\nAAAA\n',
                                    '>SEQ1 description one\nACGT\n>SEQ1 description two\nACGT\n'])
def test_invalid_incoming_archive_fails_before_any_csv_write(inputs, content):
    config, master, report, fasta = inputs
    if content is None:
        fasta.unlink()
    else:
        fasta.write_text(content)
    before = master.read_bytes()
    with pytest.raises((OSError, ValueError)):
        updater.update(config, report, 'fastq', fasta)
    assert master.read_bytes() == before
    assert not master.with_name('master.fasta').exists()
    assert not list(master.parent.glob('*.bak.*'))
    assert not list(master.parent.glob('*.lock'))


@pytest.mark.parametrize('exists', [False, True])
def test_empty_run_does_not_create_or_erase_archive(inputs, exists):
    config, master, report, fasta = inputs
    target = master.with_name('master.fasta')
    if exists:
        target.write_text('>existing\nACGT\n')
    before = target.read_bytes() if exists else None
    fasta.write_text(' \n')
    result = updater.update(config, report, 'fastq', fasta)
    assert result['written'] and not result['fasta']['written']
    assert result['fasta']['skipped'] == 'run FASTA contains no records'
    assert target.exists() == exists
    if exists:
        assert target.read_bytes() == before
    assert not list(master.parent.glob('master.fasta.bak.*'))


def test_run_archive_cannot_be_master(inputs):
    config, master, report, fasta = inputs
    target = master.with_name('master.fasta')
    target.write_bytes(fasta.read_bytes())
    before = master.read_bytes()
    with pytest.raises(ValueError, match='must be separate'):
        updater.update(config, report, 'fastq', target)
    assert master.read_bytes() == before


def test_archive_failure_after_csv_update_is_retryable(inputs):
    config, master, report, fasta = inputs
    target = master.with_name('master.fasta')
    lock = Path(str(target) + '.lock')
    lock.mkdir()
    with pytest.raises(ValueError, match='locked'):
        updater.update(config, report, 'fastq', fasta)
    assert lock.exists()  # Never remove another writer's lock.
    assert not Path(str(master) + '.lock').exists()
    assert updater.read_table(master)[1][0]['NGS_Run_ID'] == 'RUN1'
    backups = list(master.parent.glob('master.csv.bak.*'))
    lock.rmdir()
    result = updater.update(config, report, 'fastq', fasta)
    assert not result['written'] and result['fasta']['created']
    assert list(master.parent.glob('master.csv.bak.*')) == backups


class Remote(updater.storage.SMB):
    def __init__(self, root, fault=None):
        super().__init__('//test/share', 'data/SC2', 'test-auth')
        self.root, self.fault = root, fault
        self.calls = []
        self.fasta_gets = 0

    def command(self, verb, *args):
        self.calls.append((verb, args))
        target = self.root / args[0]
        if verb == 'mkdir':
            target.mkdir()
        elif verb == 'rmdir':
            target.rmdir()
        elif verb == 'get':
            if args[0] == 'master.fasta':
                self.fasta_gets += 1
                if self.fault and self.fault.startswith('NT_STATUS_'):
                    raise updater.storage.SMBError(verb, [self.fault], 1)
                if self.fault == 'concurrent-edit' and self.fasta_gets == 2:
                    target.write_text('>EXTERNAL\nAAAA\n')
            if not target.exists():
                raise updater.storage.SMBError(verb, ['NT_STATUS_OBJECT_NAME_NOT_FOUND'], 1)
            shutil.copyfile(target, args[1])
            if self.fault == 'final' and args[0] == 'master.fasta' and self.fasta_gets == 3:
                Path(args[1]).write_text('bad readback')
        elif verb == 'put':
            destination = self.root / args[1]
            shutil.copyfile(args[0], destination)
            if ((self.fault == 'candidate' and destination.name.startswith('master.fasta.tmp.'))
                    or (self.fault == 'backup' and destination.name.startswith('master.fasta.bak.'))):
                destination.write_text('bad upload')
        elif verb == 'rename':
            destination = self.root / args[1]
            if args[1] == 'master.fasta':
                if self.fault == 'rename':
                    raise updater.storage.SMBError(verb, ['NT_STATUS_ACCESS_DENIED'], 1)
                if self.fault == 'concurrent-create':
                    destination.write_text('>EXTERNAL\nAAAA\n')
            if len(args) == 2 and destination.exists():
                raise updater.storage.SMBError(verb, ['NT_STATUS_OBJECT_NAME_COLLISION'], 1)
            target.replace(destination)
        else:
            raise AssertionError(verb)


def remote_config(config, master, fault=None):
    return {**config, 'master': None, 'master_smb': Remote(master.parent, fault)}


@pytest.mark.parametrize('exists', [False, True])
def test_remote_archive_creation_backup_verification_and_retry(inputs, exists):
    config, master, report, fasta = inputs
    config = remote_config(config, master)
    target = master.with_name('master.fasta')
    if exists:
        target.write_text('>SEQ1 previous\nAAAA\n')
    before = target.read_bytes() if exists else None
    stats = updater.update(config, report, 'fastq', fasta)
    assert archive.read_fasta(target)[0] == archive.read_fasta(fasta)[0]
    assert stats['fasta']['created'] is not exists
    if exists:
        assert (master.parent / stats['fasta']['backup']).read_bytes() == before
    commands = config['master_smb'].calls
    rename = next(args for verb, args in commands if verb == 'rename' and args[1] == 'master.fasta')
    assert len(rename) == (3 if exists else 2)
    if exists:
        assert rename[2] == '-f'
    assert not list(master.parent.glob('*.lock'))
    commands.clear()
    result = updater.update(config, report, 'fastq', fasta)
    assert not result['written'] and not result['fasta']['written']
    assert not any(verb in ('put', 'rename') for verb, _ in commands)


@pytest.mark.parametrize('fault', ['backup', 'candidate', 'rename', 'final', 'concurrent-edit',
                                  'NT_STATUS_ACCESS_DENIED', 'NT_STATUS_OBJECT_PATH_NOT_FOUND',
                                  'NT_STATUS_CONNECTION_DISCONNECTED'])
def test_remote_archive_errors_release_both_locks_and_never_hide_failure(inputs, fault):
    config, master, report, fasta = inputs
    config = remote_config(config, master, fault)
    target = master.with_name('master.fasta')
    target.write_text('>OLD\nCCCC\n')
    before = target.read_bytes()
    with pytest.raises(ValueError):
        updater.update(config, report, 'fastq', fasta)
    assert not list(master.parent.glob('*.lock'))
    if fault not in {'final', 'concurrent-edit'}:
        assert target.read_bytes() == before
    if fault in {'backup', 'candidate', 'concurrent-edit'} or fault.startswith('NT_STATUS_'):
        assert not any(verb == 'rename' and args[1] == 'master.fasta' for verb, args in config['master_smb'].calls)
    if fault in {'candidate', 'rename', 'final', 'concurrent-edit'}:
        backups = list(master.parent.glob('master.fasta.bak.*'))
        assert len(backups) == 1 and backups[0].read_bytes() == before


def test_remote_new_archive_never_overwrites_competing_initializer(inputs):
    config, master, report, fasta = inputs
    config = remote_config(config, master, 'concurrent-create')
    with pytest.raises(ValueError, match='OBJECT_NAME_COLLISION'):
        updater.update(config, report, 'fastq', fasta)
    assert master.with_name('master.fasta').read_text() == '>EXTERNAL\nAAAA\n'
    assert not list(master.parent.glob('*.lock'))


@pytest.mark.parametrize(('mode', 'validation'), [('true', ''), ('false', ''), ('true', 'VER'), ('auto', '')])
def test_cli_archive_update_and_skip_controls(inputs, mode, validation):
    config, master, report, fasta = inputs
    env = {k: v for k, v in os.environ.items() if not k.startswith('SARSSEQ_')}
    env['SARSSEQ_MASTER_UPDATE'] = mode
    if mode != 'auto':
        env.update(SARSSEQ_MASTER_CSV=str(master), SARSSEQ_METADATA_CSV=config['metadata'])
    enabled = mode == 'true' and not validation
    command = [sys.executable, str(SCRIPT), '--workflow', 'fastq', '--report', str(report),
               '--fasta', str(fasta if enabled else fasta.with_name('missing.fasta')), '--validation', validation]
    before = master.read_bytes()
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert master.with_name('master.fasta').exists() == enabled
    if enabled:
        assert '"fasta":' in result.stdout
    else:
        assert master.read_bytes() == before and 'skipped' in result.stdout
