"""SC2 production transactions, using synthetic CSVs and simulated SMB storage."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'master_csv/update_master.py'
spec = importlib.util.spec_from_file_location('sars_update_master', SCRIPT)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


@pytest.fixture
def inputs(tmp_path):
    root = tmp_path / 'SC2 with spaces'
    root.mkdir()
    master = root / 'master.csv'
    metadata = root / 'NGS_PREP_SC2_report.csv'
    report = tmp_path / 'run.csv'
    master.write_text('Prove_LW_ID;NGS_LW_ID;GISAID_Isolate_ID\n001;SEQ1;existing-accession\n')
    master.chmod(0o640)
    metadata.write_text('Prove_LW_ID;NGS_LW_ID;RekvNr;Key\n001;SEQ1;legacy;metadata-key\n')
    report.write_text('Sample;RunID;coverage\nSEQ1;RUN1;0.95\n')
    return master, metadata, report


def local_config(master):
    config, reason = updater.configuration({'SARSSEQ_MASTER_CSV': str(master)})
    assert reason is None
    return config


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_mounted_update_backup_permissions_and_idempotence(inputs, workflow):
    master, metadata, report = inputs
    before, meta_before, report_before = master.read_bytes(), metadata.read_bytes(), report.read_bytes()
    stats = updater.update(local_config(master), report, workflow)
    assert stats['written'] and stats['updated'] == 1
    backup = Path(stats['backup'])
    assert backup.read_bytes() == before
    assert stat.S_IMODE(backup.stat().st_mode) == stat.S_IMODE(master.stat().st_mode) == 0o640
    _, rows = updater.read_table(master)
    assert rows[0]['Prove_LW_ID'] == '001'
    assert rows[0]['NGS_Run_ID'] == 'RUN1' and rows[0]['NC_Coverage'] == '0.95'
    assert rows[0]['Key'] == 'legacy' and rows[0]['Metadata_Key'] == 'metadata-key'
    assert rows[0]['GISAID_Isolate_ID'] == 'existing-accession'
    assert metadata.read_bytes() == meta_before and report.read_bytes() == report_before
    assert not Path(str(master) + '.lock').exists()
    after, mtime = master.read_bytes(), master.stat().st_mtime_ns
    retry = updater.update(local_config(master), report, workflow)
    assert not retry['written'] and retry['unchanged'] == 1
    assert master.read_bytes() == after and master.stat().st_mtime_ns == mtime
    assert list(master.parent.glob('master.csv.bak.*')) == [backup]


def test_mounted_existing_lock_is_not_removed(inputs):
    master, _, report = inputs
    lock = Path(str(master) + '.lock')
    lock.mkdir()
    before = master.read_bytes()
    with pytest.raises(ValueError, match='locked'):
        updater.update(local_config(master), report, 'fastq')
    assert lock.is_dir() and master.read_bytes() == before
    assert not list(master.parent.glob('*.bak.*'))


def test_invalid_report_cleans_owned_lock_without_backup(inputs):
    master, _, report = inputs
    before = master.read_bytes()
    report.write_text('Sample\nSEQ1\nSEQ1\n')
    with pytest.raises(ValueError, match='duplicate'):
        updater.update(local_config(master), report, 'fastq')
    assert master.read_bytes() == before
    assert not Path(str(master) + '.lock').exists()
    assert not list(master.parent.glob('*.bak.*'))


def test_concurrent_mounted_edit_is_not_overwritten(inputs, monkeypatch):
    master, _, report = inputs
    merge = updater.merge_tables

    def concurrent_edit(*args, **kwargs):
        result = merge(*args, **kwargs)
        master.write_text('Prove_LW_ID\nexternal-edit\n')
        return result

    monkeypatch.setattr(updater, 'merge_tables', concurrent_edit)
    with pytest.raises(ValueError, match='changed during merge'):
        updater.update(local_config(master), report, 'fastq')
    assert master.read_text() == 'Prove_LW_ID\nexternal-edit\n'
    assert not Path(str(master) + '.lock').exists()
    assert not list(master.parent.glob('.*.tmp'))
    assert not list(master.parent.glob('*.bak.*'))


def test_failed_mounted_replacement_keeps_master_backup_and_cleans_lock(inputs, monkeypatch):
    import merge_master_csv
    master, _, report = inputs
    before = master.read_bytes()

    def fail(*args):
        raise OSError('simulated replacement failure')

    monkeypatch.setattr(merge_master_csv.os, 'replace', fail)
    with pytest.raises(OSError, match='replacement failure'):
        updater.update(local_config(master), report, 'fastq')
    assert master.read_bytes() == before
    backups = list(master.parent.glob('*.bak.*'))
    assert len(backups) == 1 and backups[0].read_bytes() == before
    assert not Path(str(master) + '.lock').exists()
    assert not list(master.parent.glob('.*.tmp'))


def test_mounted_metadata_overrides_and_no_smb_dependency(inputs, tmp_path, monkeypatch):
    master, metadata, _ = inputs
    monkeypatch.setattr(updater.storage.shutil, 'which', lambda name: None)
    assert local_config(master)['metadata'] == str(metadata)
    other = tmp_path / 'metadata elsewhere.csv'
    other.write_bytes(metadata.read_bytes())
    config, _ = updater.configuration({'SARSSEQ_MASTER_CSV': str(master),
                                       'SARSSEQ_METADATA_CSV': str(other),
                                       'SARSSEQ_METADATA_SMB_SHARE': '//unused/share'})
    assert config['metadata'] == str(other)
    assert config['master_smb'] is None and config['metadata_smb'] is None


@pytest.mark.parametrize('missing', ['master', 'metadata'])
def test_missing_mounted_inputs_fail_without_initializing_database(inputs, missing):
    master, metadata, _ = inputs
    (master if missing == 'master' else metadata).unlink()
    with pytest.raises(ValueError, match=f'Configured {missing} CSV does not exist'):
        local_config(master)
    assert not list(master.parent.glob('*.bak.*'))
    assert not Path(str(master) + '.lock').exists()


@pytest.fixture
def smb_environ(tmp_path, monkeypatch):
    auth = tmp_path / 'smb-auth'
    auth.touch()
    monkeypatch.setattr(updater.storage.shutil, 'which', lambda name: '/fake/smbclient')
    return {'SARSSEQ_MASTER_UPDATE': 'true', 'SARSSEQ_MASTER_SMB_AUTH': str(auth)}


def test_sc2_defaults_are_isolated_from_influenza(smb_environ):
    config, _ = updater.configuration({**smb_environ, 'FLUSEQ_MASTER_CSV': '/wrong/INF/master.csv',
                                       'FLUSEQ_METADATA_SMB_NAME': 'wrong.csv'})
    assert config['master_smb'].share == '//pos1-fhi-svm01.fhi.no/styrt'
    assert config['master_smb'].directory == (
        'Virologi/NGS/1-NGS-Analyser/2-Utvikling/'
        'Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2')
    assert config['metadata_smb'].directory == config['master_smb'].directory
    assert config['master_name'] == 'master.csv'
    assert config['metadata_name'] == 'NGS_PREP_SC2_report.csv'
    assert updater.storage.MASTER_DIR.endswith('/INF')


@pytest.mark.parametrize('separate_metadata', [False, True])
def test_smb_overrides_inherit_or_separate_metadata(smb_environ, separate_metadata):
    env = {**smb_environ, 'SARSSEQ_MASTER_SMB_SHARE': '//custom/share',
           'SARSSEQ_MASTER_SMB_DIR': 'custom SC2', 'SARSSEQ_MASTER_SMB_NAME': 'database.csv'}
    if separate_metadata:
        env.update(SARSSEQ_METADATA_SMB_SHARE='//metadata/share', SARSSEQ_METADATA_SMB_DIR='exports',
                   SARSSEQ_METADATA_SMB_NAME='metadata.csv')
    config, _ = updater.configuration(env)
    assert config['master_smb'].directory == 'custom SC2'
    assert config['metadata_smb'].share == ('//metadata/share' if separate_metadata else '//custom/share')
    assert config['metadata_smb'].directory == ('exports' if separate_metadata else 'custom SC2')
    assert config['metadata_name'] == ('metadata.csv' if separate_metadata else 'NGS_PREP_SC2_report.csv')


@pytest.mark.parametrize('local_kind', ['master', 'metadata'])
def test_mixed_mounted_and_smb_sources(inputs, smb_environ, local_kind):
    master, metadata, _ = inputs
    env = dict(smb_environ)
    if local_kind == 'master':
        env.update(SARSSEQ_MASTER_CSV=str(master), SARSSEQ_METADATA_SMB_SHARE='//metadata/share')
    else:
        env['SARSSEQ_METADATA_CSV'] = str(metadata)
    config, _ = updater.configuration(env)
    assert config[local_kind] == str(master if local_kind == 'master' else metadata)
    remote_kind = 'metadata' if local_kind == 'master' else 'master'
    assert config[remote_kind] is None and config[remote_kind + '_smb'] is not None


@pytest.mark.parametrize('link', [False, True])
def test_same_mounted_master_and_metadata_rejected(inputs, tmp_path, link):
    master, _, _ = inputs
    metadata = master
    if link:
        metadata = tmp_path / 'alias.csv'
        os.link(master, metadata)
    with pytest.raises(ValueError, match='separate files'):
        updater.configuration({'SARSSEQ_MASTER_CSV': str(master), 'SARSSEQ_METADATA_CSV': str(metadata)})


def test_same_remote_master_and_metadata_rejected(smb_environ):
    with pytest.raises(ValueError, match='separate SMB files'):
        updater.configuration({**smb_environ, 'SARSSEQ_METADATA_SMB_NAME': 'master.csv'})


@pytest.mark.parametrize('name', ['../master.csv', 'bad;name.csv', 'bad"name.csv', '*.csv'])
def test_invalid_remote_names_rejected_before_access(smb_environ, name):
    with pytest.raises(ValueError):
        updater.configuration({**smb_environ, 'SARSSEQ_MASTER_SMB_NAME': name})


def test_missing_smb_client_and_credentials_fail(smb_environ, monkeypatch):
    monkeypatch.setattr(updater.storage.shutil, 'which', lambda name: None)
    with pytest.raises(ValueError, match='smbclient is required'):
        updater.configuration(smb_environ)
    monkeypatch.setattr(updater.storage.shutil, 'which', lambda name: '/fake/smbclient')
    Path(smb_environ['SARSSEQ_MASTER_SMB_AUTH']).unlink()
    with pytest.raises(ValueError, match='authentication file does not exist'):
        updater.configuration(smb_environ)


@pytest.mark.parametrize(('env', 'validation'), [({}, ''), ({'SARSSEQ_MASTER_UPDATE': 'false'}, ''),
                                               ({'SARSSEQ_MASTER_UPDATE': 'true'}, 'VER')])
def test_disabled_unconfigured_validation_skip_without_access(env, validation):
    config, reason = updater.configuration(env, validation)
    assert config is None and reason


@pytest.mark.parametrize(('mode', 'validation', 'configured'), [
    ('auto', '', False), ('auto', '', True), ('false', '', True),
    ('true', '', True), ('TRUE', '', True), ('False', '', True),
    ('true', 'VER', True), ('invalid', '', True), ('invalid', 'VER', True),
])
def test_control_decisions_match_influenza(inputs, mode, validation, configured):
    master, metadata, _ = inputs
    settings = {'MASTER_UPDATE': mode}
    if configured:
        settings.update(MASTER_CSV=str(master), METADATA_CSV=str(metadata))
    outcomes = []
    for prefix, configure in [('FLUSEQ', updater.storage.configuration), ('SARSSEQ', updater.configuration)]:
        env = {prefix + '_' + key: value for key, value in settings.items()}
        try:
            config, reason = configure(env, validation)
            outcomes.append(('enabled' if config else 'skipped', (reason or '').replace(prefix, 'WORKFLOW')))
        except ValueError as error:
            outcomes.append(('error', str(error).replace(prefix, 'WORKFLOW')))
    assert outcomes[0] == outcomes[1]


class SimulatedSMB(updater.storage.SMB):
    """Keep the real lock, get and put_verified methods; substitute server commands."""

    def __init__(self, root, fault=None):
        super().__init__('//simulated/share', 'SC2', 'unused-auth')
        self.root = root
        self.fault = fault
        self.calls = []
        self.master_gets = 0

    def command(self, verb, *arguments):
        self.calls.append((verb, tuple(str(arg) for arg in arguments)))
        if verb == 'get':
            remote, local = arguments
            source = self.root / remote
            if not source.exists():
                raise updater.storage.SMBError(verb, ['NT_STATUS_OBJECT_NAME_NOT_FOUND'], 1)
            if remote == 'master.csv':
                self.master_gets += 1
                if self.fault == 'concurrent' and self.master_gets == 2:
                    source.write_text('Prove_LW_ID\nexternal-edit\n')
            shutil.copyfile(source, local)
            if self.fault == 'final' and remote == 'master.csv' and self.master_gets == 3:
                Path(local).write_text('simulated corrupt readback')
        elif verb == 'put':
            local, remote = arguments
            shutil.copyfile(local, self.root / remote)
            if ((self.fault == 'backup' and '.bak.' in remote)
                    or (self.fault == 'candidate' and '.tmp.' in remote)):
                (self.root / remote).write_text('simulated corrupt upload')
        elif verb == 'mkdir':
            (self.root / arguments[0]).mkdir()
        elif verb == 'rmdir':
            (self.root / arguments[0]).rmdir()
        elif verb == 'rename':
            if self.fault == 'rename':
                raise updater.storage.SMBError(verb, ['NT_STATUS_ACCESS_DENIED'], 1)
            source, destination, flag = arguments
            assert flag == '-f'
            os.replace(self.root / source, self.root / destination)
        else:
            raise AssertionError(f'Unexpected SMB command: {verb}')


def remote_config(root, fault=None):
    remote = SimulatedSMB(root, fault)
    return {'master': None, 'metadata': None, 'master_smb': remote, 'metadata_smb': remote,
            'master_name': 'master.csv', 'metadata_name': updater.METADATA_NAME, 'nonempty_report': False}


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_smb_backup_candidate_and_final_verified_then_retry_noop(inputs, workflow):
    master, metadata, report = inputs
    before, metadata_before = master.read_bytes(), metadata.read_bytes()
    config = remote_config(master.parent)
    remote = config['master_smb']
    result = updater.update(config, report, workflow)
    assert result['written'] and result['updated'] == 1
    assert (master.parent / result['backup']).read_bytes() == before
    assert metadata.read_bytes() == metadata_before
    assert [verb for verb, _ in remote.calls] == [
        'get', 'mkdir', 'get', 'put', 'get', 'put', 'get', 'get', 'rename', 'get', 'rmdir']
    assert not Path(str(master) + '.lock').exists()
    _, rows = updater.read_table(master)
    assert rows[0]['NC_Coverage'] == '0.95'
    remote.calls.clear()
    after = master.read_bytes()
    assert not updater.update(config, report, workflow)['written']
    assert master.read_bytes() == after
    assert [verb for verb, _ in remote.calls] == ['get', 'mkdir', 'get', 'rmdir']


@pytest.mark.parametrize(('fault', 'message'), [('backup', 'upload verification failed'),
                                              ('candidate', 'upload verification failed'),
                                              ('concurrent', 'changed during merge'),
                                              ('rename', 'SMB rename failed'),
                                              ('final', 'Remote master verification failed')])
def test_smb_failures_preserve_backup_and_release_lock(inputs, fault, message):
    master, _, report = inputs
    before = master.read_bytes()
    config = remote_config(master.parent, fault)
    with pytest.raises(ValueError, match=message):
        updater.update(config, report, 'fastq')
    assert not Path(str(master) + '.lock').exists()
    backups = list(master.parent.glob('*.bak.*'))
    assert len(backups) == 1
    if fault != 'backup':
        assert backups[0].read_bytes() == before
    if fault in {'backup', 'candidate', 'rename'}:
        assert master.read_bytes() == before
    elif fault == 'concurrent':
        assert master.read_text() == 'Prove_LW_ID\nexternal-edit\n'
    elif fault == 'final':
        # The rename already succeeded; a failed final readback is not rolled back blindly.
        assert master.read_bytes() != before
    if fault in {'backup', 'candidate', 'concurrent'}:
        assert 'rename' not in [verb for verb, _ in config['master_smb'].calls]


@pytest.mark.parametrize('missing', ['master', 'metadata'])
def test_missing_remote_inputs_never_create_database(inputs, missing):
    master, metadata, report = inputs
    (master if missing == 'master' else metadata).unlink()
    config = remote_config(master.parent)
    with pytest.raises(ValueError, match='OBJECT_NAME_NOT_FOUND'):
        updater.update(config, report, 'fastq')
    assert not Path(str(master) + '.lock').exists()
    assert 'put' not in [verb for verb, _ in config['master_smb'].calls]


def test_smb_existing_lock_is_not_removed(inputs):
    master, _, report = inputs
    lock = Path(str(master) + '.lock')
    lock.mkdir()
    config = remote_config(master.parent)
    with pytest.raises(FileExistsError):
        updater.update(config, report, 'fastq')
    assert lock.is_dir()
    assert [verb for verb, _ in config['master_smb'].calls] == ['get', 'mkdir']


@pytest.mark.parametrize('remote', [False, True])
def test_access_check_only_reads_csvs(inputs, remote):
    master, metadata, _ = inputs
    before = master.read_bytes(), metadata.read_bytes()
    config = remote_config(master.parent) if remote else local_config(master)
    result = updater.check_access(config)
    assert result == {'master': {'columns': 3, 'rows': 1}, 'metadata': {'columns': 4, 'rows': 1}}
    assert (master.read_bytes(), metadata.read_bytes()) == before
    if remote:
        assert [verb for verb, _ in config['master_smb'].calls] == ['get', 'get']
    assert not list(master.parent.glob('*.bak.*'))
    assert not Path(str(master) + '.lock').exists()


def test_smb_command_quotes_spaces_and_rejects_success_status_errors(monkeypatch, tmp_path):
    remote = updater.storage.SMB('//server/share', 'directory with spaces', 'auth path')
    calls = []

    def run(command, **kwargs):
        calls.append((command, kwargs))
        return subprocess.CompletedProcess(command, 0, 'NT_STATUS_ACCESS_DENIED private-detail', '')

    monkeypatch.setattr(updater.storage.subprocess, 'run', run)
    with pytest.raises(ValueError, match='ACCESS_DENIED') as error:
        remote.get('master with spaces.csv', tmp_path / 'local file.csv')
    assert 'private-detail' not in str(error.value)
    command, kwargs = calls[0]
    assert command[:7] == ['smbclient', '//server/share', '-A', 'auth path', '-D', 'directory with spaces', '-c']
    assert command[7] == f'get "master with spaces.csv" "{tmp_path / "local file.csv"}"'
    assert kwargs['timeout'] == 300 and not kwargs.get('shell', False)


def test_cli_configuration_access_update_and_failure(inputs):
    master, _, report = inputs
    env = {k: v for k, v in os.environ.items() if not k.startswith('SARSSEQ_')}
    env['SARSSEQ_MASTER_CSV'] = str(master)
    command = [sys.executable, str(SCRIPT), '--workflow', 'fastq']
    before = master.read_bytes()
    for check in ('--check-config', '--check-access'):
        result = subprocess.run(command + [check], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert master.read_bytes() == before
    result = subprocess.run(command + ['--report', str(report)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert '"written": true' in result.stdout
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert result.returncode == 1 and 'Final report CSV is missing' in result.stderr


@pytest.mark.parametrize('remote', [False, True])
@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_text_repair_backup_retry_and_qc(inputs, remote, workflow):
    master, metadata, report = inputs
    master.write_text('Prove_LW_ID;NGS_LW_ID;Pasient_Fylke_Name;PCR_SC2_EXT_Res\n'
                      '001;SEQ1;Tr ndelag;PÃ¥vist\n002;SEQ2; stfold;Ikke p vist\n')
    metadata.write_text('Prove_LW_ID;NGS_LW_ID;PCR_SC2_EXT_Res\n001;SEQ1;P vist\n')
    report.write_text('Sample\nSEQ1\n')
    before = master.read_bytes(), metadata.read_bytes(), report.read_bytes()
    config = remote_config(master.parent) if remote else local_config(master)
    output = report.with_name('run_qc.html')
    stats = updater.update(config, report, workflow, qc_output=output)
    assert stats['written'] and stats['text_repaired'] == 2
    backups = list(master.parent.glob('master.csv.bak.*'))
    assert len(backups) == 1 and backups[0].read_bytes() == before[0]
    assert (metadata.read_bytes(), report.read_bytes()) == before[1:]
    _, rows = updater.read_table(master)
    assert [(row['Pasient_Fylke_Name'], row['PCR_SC2_EXT_Res']) for row in rows] == [
        ('Trøndelag', 'Påvist'), ('Østfold', 'Ikke påvist')]
    qpcr = json.loads(output.with_suffix('.json').read_text())['samples'][0]['qpcr']
    assert qpcr['status'] == 'Positive qPCR'
    assert qpcr['results']['PCR_SC2_EXT_Res'] == 'Påvist'
    after = master.read_bytes()
    retry = updater.update(config, report, workflow, qc_output=output)
    assert not retry['written'] and master.read_bytes() == after
    # The still-damaged metadata is repaired again in memory, without another write.
    assert retry['text_repaired'] == 1
    assert list(master.parent.glob('master.csv.bak.*')) == backups
    assert not Path(str(master) + '.lock').exists()


@pytest.mark.parametrize('encoding', ['utf-8', 'utf-8-sig', 'utf-16', 'cp1252'])
def test_norwegian_text_survives_sc2_update_encodings(inputs, encoding):
    master, metadata, report = inputs
    metadata.write_bytes(('Prove_LW_ID;NGS_LW_ID;Pasient_Fylke_Name;PCR_SC2_EXT_Res\n'
                          '001;SEQ1;Møre og Romsdal;Påvist\n').encode(encoding))
    before = metadata.read_bytes()
    stats = updater.update(local_config(master), report, 'fastq')
    assert stats['text_repaired'] == 0
    _, rows = updater.read_table(master)
    assert rows[0]['Pasient_Fylke_Name'] == 'Møre og Romsdal'
    assert rows[0]['PCR_SC2_EXT_Res'] == 'Påvist'
    assert metadata.read_bytes() == before
