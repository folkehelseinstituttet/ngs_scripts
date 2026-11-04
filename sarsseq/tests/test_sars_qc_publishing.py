"""CLI publication guards, read-only checks and local-only generation."""

import os
from pathlib import Path
import subprocess
import sys

import pytest

UPDATER = Path(__file__).resolve().parents[1] / 'master_csv/update_master.py'


@pytest.fixture
def publishing(tmp_path, qc_smb_env):
    master = tmp_path / 'master.csv'
    master.write_text('Prove_LW_ID;NGS_LW_ID\n001;SEQ1\n')
    (tmp_path / 'NGS_PREP_SC2_report.csv').write_text('Prove_LW_ID;NGS_LW_ID\n001;SEQ1\n')
    report = tmp_path / 'run.csv'
    report.write_text('Sample;RunID\nSEQ1;SYNTHETIC\n')
    output = tmp_path / 'run_qc.html'
    env = {key: value for key, value in os.environ.items() if not key.startswith('SARSSEQ_')}
    env.update(qc_smb_env, SARSSEQ_MASTER_UPDATE='true', SARSSEQ_MASTER_CSV=str(master))
    command = [sys.executable, str(UPDATER), '--workflow', 'fastq', '--report', str(report)]
    flags = ['--qc-output', str(output), '--qc-smb-share', '//unused/share',
             '--qc-smb-dir', 'validation', '--qc-smb-auth', env['QC_TEST_AUTH']]
    return command, flags, env, master, output


@pytest.mark.parametrize('missing', ['--qc-output', '--qc-smb-share', '--qc-smb-dir'])
def test_incomplete_publishing_options_fail_before_master_write(publishing, missing):
    command, flags, env, master, output = publishing
    before = master.read_bytes()
    offset = flags.index(missing)
    del flags[offset:offset + 2]
    result = subprocess.run(command + flags, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0
    assert 'QC upload requires' in result.stderr
    assert master.read_bytes() == before
    assert not output.exists()
    assert not Path(env['EVENTS']).exists()


@pytest.mark.parametrize('check', ['--check-config', '--check-access'])
def test_readonly_checks_never_generate_or_publish_qc(publishing, check):
    command, flags, env, master, output = publishing
    before = master.read_bytes()
    # Even existing outputs must not be republished in check mode.
    output.write_text('existing report')
    output.with_suffix('.json').write_text('existing JSON')
    result = subprocess.run(command + flags + [check], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert master.read_bytes() == before
    assert output.read_text() == 'existing report'
    assert output.with_suffix('.json').read_text() == 'existing JSON'
    assert not Path(env['EVENTS']).exists()


def test_local_qc_option_does_not_publish_implicitly(publishing):
    command, flags, env, master, output = publishing
    result = subprocess.run(command + flags[:2], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert output.is_file() and output.with_suffix('.json').is_file()
    assert not Path(env['EVENTS']).exists()


def test_invalid_share_fails_before_master_write(publishing):
    command, flags, env, master, output = publishing
    before = master.read_bytes()
    flags[flags.index('--qc-smb-share') + 1] = 'invalid-share'
    result = subprocess.run(command + flags, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode != 0
    assert master.read_bytes() == before
    assert not output.exists()
    assert not Path(env['EVENTS']).exists()
