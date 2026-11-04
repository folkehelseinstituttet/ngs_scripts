"""Exercise wrapper preflight and post-upload integration without running analysis."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

import pytest

SARS = Path(__file__).resolve().parents[1]
HELPER = SARS / 'master_csv/wrapper_integration.sh'
WRAPPERS = {
    'routine-fastq': SARS / 'sarsseq_wrapper.sh',
    'routine-fasta': SARS / 'sarsseq_wrapper.sh',
    'fasta': SARS / 'sarsseq_fasta_wrapper.sh',
}


def clean_env():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(('SARSSEQ_', 'LOCAL_', 'OUTPUT_DIR', 'OFFLINE_', 'WRAPPER_', 'TEAMS_'))}


@pytest.mark.parametrize('kind', WRAPPERS)
def test_real_wrapper_preflight_runs_before_downloads_and_analysis(tmp_path, kind):
    home = tmp_path / 'home'
    conda = home / 'miniconda3/etc/profile.d/conda.sh'
    conda.parent.mkdir(parents=True)
    conda.write_text(':\n')
    tools = tmp_path / 'custom master tools'
    tools.mkdir()
    calls = tmp_path / 'calls.json'
    (tools / 'update_master.py').write_text(
        'import json, os, pathlib, sys\n'
        'pathlib.Path(os.environ["MASTER_CALLS"]).write_text(json.dumps(sys.argv[1:]))\n'
        'sys.exit(73)\n'
    )
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    marker = tmp_path / 'unexpected-external-command'
    for name in ('git', 'nextflow', 'smbclient'):
        script = binaries / name
        script.write_text('#!/bin/bash\ntouch "$UNEXPECTED_COMMAND"\nexit 89\n')
        script.chmod(0o755)
    env = dict(clean_env(), HOME=str(home), CONDA_PROFILE=str(conda), MASTER_CALLS=str(calls),
               SARSSEQ_MASTER_TOOLS=str(tools), UNEXPECTED_COMMAND=str(marker),
               WRAPPER_LOG_DIR=str(tmp_path / 'logs'), PATH=str(binaries) + os.pathsep + os.environ['PATH'])
    args = ['bash', str(WRAPPERS[kind]), '-r', 'SART001', '-a', 'sars', '-y', '2025', '-v', 'VER']
    if kind.startswith('routine'):
        args += ['-t']
    if kind == 'routine-fasta':
        args += ['--local-fasta', str(tmp_path / 'input.fasta')]
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 73, result.stdout + result.stderr
    assert json.loads(calls.read_text()) == [
        '--workflow', 'fastq' if kind == 'routine-fastq' else 'fasta',
        '--validation', 'VER', '--check-config']
    assert not marker.exists()


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize(('inherited', 'options', 'expected'), [
    (None, [], 'true'), ('', [], 'true'), ('true', [], 'true'),
    ('false', [], 'false'), ('auto', [], 'auto'), ('FALSE', [], 'FALSE'),
    ('true', ['-M'], 'false'), ('auto', ['-M'], 'false'),
    ('invalid', ['-M'], 'false'),
])
def test_wrapper_mode_controls_match_influenza(tmp_path, kind, inherited, options, expected):
    home = tmp_path / 'home'
    conda = home / 'miniconda3/etc/profile.d/conda.sh'
    conda.parent.mkdir(parents=True)
    conda.write_text(':\n')
    tools = tmp_path / 'tools'
    tools.mkdir()
    # Same preflight probe as the Influenza control tests; no external work runs.
    (tools / 'update_master.py').write_text(
        'import os, sys\n'
        'print("MASTER_MODE=" + os.environ["SARSSEQ_MASTER_UPDATE"], flush=True)\n'
        'sys.exit(73)\n'
    )
    env = dict(clean_env(), HOME=str(home), CONDA_PROFILE=str(conda), SARSSEQ_MASTER_TOOLS=str(tools),
               WRAPPER_LOG_DIR=str(tmp_path / 'logs'))
    if inherited is not None:
        env['SARSSEQ_MASTER_UPDATE'] = inherited
    args = ['bash', str(WRAPPERS[kind]), '-r', 'SART001', '-a', 'sars', '-y', '2025']
    if kind.startswith('routine'):
        args += ['-t']  # Notification suppression must not disable master updates.
    if kind == 'routine-fasta':
        args += ['--local-fasta', '/unused/input.fasta']
    result = subprocess.run(args + options, env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 73, result.stdout + result.stderr
    assert f'MASTER_MODE={expected}' in result.stdout


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize(('mode', 'options', 'skip'), [
    ('true', ['-v', 'VER'], True), ('true', ['-M'], True),
    ('false', [], True), ('invalid', [], False),
    ('invalid', ['-v', 'VER'], False), ('true', [], False),
])
def test_real_preflight_checks_or_skips_before_external_work(tmp_path, kind, mode, options, skip):
    home = tmp_path / 'home'
    conda = home / 'miniconda3/etc/profile.d/conda.sh'
    conda.parent.mkdir(parents=True)
    conda.write_text(':\n')
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    for name in ('git', 'smbclient', 'nextflow'):
        script = binaries / name
        script.write_text('#!/bin/bash\necho EXTERNAL_WORK_REACHED\nexit 89\n')
        script.chmod(0o755)
    env = dict(clean_env(), HOME=str(home), CONDA_PROFILE=str(conda), SARSSEQ_MASTER_UPDATE=mode,
               SARSSEQ_MASTER_CSV=str(tmp_path / 'unavailable-master.csv'),
               WRAPPER_LOG_DIR=str(tmp_path / 'logs'), PATH=str(binaries) + os.pathsep + os.environ['PATH'])
    args = ['bash', str(WRAPPERS[kind]), '-r', 'SART001', '-a', 'sars', '-y', '2025']
    if kind.startswith('routine'):
        args += ['-t']
    if kind == 'routine-fasta':
        args += ['--local-fasta', '/unused/input.fasta']
    result = subprocess.run(args + options, env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    if skip:
        assert result.returncode == 89, output
        assert 'Master CSV update skipped:' in output
        assert 'EXTERNAL_WORK_REACHED' in output
    else:
        assert result.returncode == 1, output
        assert 'EXTERNAL_WORK_REACHED' not in output
        assert ('must be auto, true, or false' if mode == 'invalid' else 'Configured master CSV does not exist') in output


@pytest.mark.parametrize('kind', ['routine-fastq', 'routine-fasta'])
def test_real_offline_wrapper_skips_master_preflight(tmp_path, kind):
    home = tmp_path / 'home'
    home.mkdir()
    conda = tmp_path / 'conda.sh'
    # Stop immediately after the preflight position, before any analysis/setup.
    conda.write_text('echo OFFLINE_PREFLIGHT_PASSED\nexit 73\n')
    env = dict(clean_env(), HOME=str(home), CONDA_PROFILE=str(conda), SARSSEQ_MASTER_UPDATE='true',
               SARSSEQ_MASTER_TOOLS='/unavailable/updater', SARSSEQ_MASTER_CSV='/unavailable/master.csv',
               WRAPPER_LOG_DIR=str(tmp_path / 'logs'))
    args = ['bash', str(WRAPPERS[kind]), '-r', 'SART001', '-a', 'sars', '-y', '2025', '-o']
    if kind == 'routine-fasta':
        args += ['--local-fasta', '/unused/input.fasta']
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 73, result.stdout + result.stderr
    assert 'OFFLINE_PREFLIGHT_PASSED' in result.stdout


def post_upload_script(kind):
    """Execute the real wrapper tail, replacing only external uploads/lifecycle calls."""
    source = WRAPPERS[kind].read_text()
    if kind.startswith('routine'):
        start = source.index('echo "Moving results to the N: drive"')
    else:
        start = source.index('if [ "$SKIP_RESULTS_MOVE" = false ]; then')
    return '''set -euo pipefail
source "$INTEGRATION_HELPER"
smbclient() {
    if [[ " $* " == *" -c "* ]]; then return 0; fi
    cat >/dev/null
    printf 'upload\n' >> "$EVENTS"
    return "$UPLOAD_STATUS"
}
wrapper_smb_upload() { smbclient "$@"; }
wrapper_logs_status() { printf '%s\n' "$*" >> "$EVENTS"; }
wrapper_logs_complete() {
    printf 'complete\n' >> "$EVENTS"
    if [[ "${5:-0}" == 1 ]]; then
        rm -rf -- "$1"
        printf 'cleanup\n' >> "$EVENTS"
    fi
}
''' + source[start:]


@pytest.fixture
def run_env(tmp_path, qc_smb_env):
    root = tmp_path / 'mounted SC2'
    root.mkdir()
    master = root / 'master.csv'
    master.write_text('Prove_LW_ID;NGS_LW_ID\n001;SEQ1\n')
    (root / 'NGS_PREP_SC2_report.csv').write_text('Prove_LW_ID;NGS_LW_ID;RekvNr\n001;SEQ1;legacy\n')
    run_out = tmp_path / 'staged results' / 'SART001'
    (run_out / 'report').mkdir(parents=True)
    (run_out / 'report/SART001.fasta').write_text('>SEQ1 synthetic record\nACGTNN\n')
    (run_out / 'report/SART001.iupac.fasta').write_text('>OTHER\nAAAA\n')
    events = tmp_path / 'events'
    env = dict(clean_env(), SCRIPT_DIR=str(SARS), INTEGRATION_HELPER=str(HELPER),
               SARSSEQ_MASTER_CSV=str(master), RUN='SART001', RUN_OUT=str(run_out),
               LOCAL_UPLOAD_RUN=str(run_out), MASTER_WORKFLOW='fastq',
               VALIDATION_FLAG='', OFFLINE_MODE='false', SKIP_RESULTS_MOVE='false',
               SMB_HOST='//unused/share', SMB_AUTH='unused-auth', SMB_DIR='results',
               SMB_DIR_ANALYSIS='validation', EVENTS=str(events), UPLOAD_STATUS='0',
               CLEAN_TMP='false', LOCAL_SAMPLESHEET='', OUTPUT_DIR=str(run_out))
    env.update(qc_smb_env)
    return env, master, run_out, events


def run_tail(kind, env):
    env = dict(env, MASTER_WORKFLOW='fastq' if kind == 'routine-fastq' else 'fasta')
    return subprocess.run(['bash', '-c', post_upload_script(kind)], env=env,
                          capture_output=True, text=True, timeout=15)


def read_master(master):
    # Import through the updater's established module path.
    sys.path.insert(0, str(SARS / 'master_csv'))
    from preview_merge import read_table
    return read_table(master)[1]


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize('with_versions', [False, True])
def test_exact_current_report_merged_after_uploads(run_env, kind, with_versions):
    env, master, run_out, events = run_env
    # A legacy-key FASTA name confirms the workflow-specific matching is used.
    sample = 'SEQ1' if kind == 'routine-fastq' else 'legacy'
    primary = run_out / 'report/SART001.csv'
    primary.write_text(f'Sample;RunID\n{sample};primary\n')
    if with_versions:
        (run_out / 'report/SART001_with_software_versions.csv').write_text(
            f'Sample;RunID;NGS_Script_vers\n{sample};versioned;test-tools\n')
    (run_out / 'report/OTHER_with_software_versions.csv').write_text('not,a,valid,report\n')
    result = run_tail(kind, env)
    assert result.returncode == 0, result.stdout + result.stderr
    rows = read_master(master)
    assert len(rows) == 1 and rows[0]['Prove_LW_ID'] == '001'
    assert rows[0]['NGS_Run_ID'] == ('versioned' if with_versions else 'primary')
    if with_versions:
        assert rows[0]['NGS_Script_vers'] == 'test-tools'
    assert (master.parent / 'master.fasta').read_text() == '>SEQ1 synthetic record\nACGTNN\n'
    assert events.read_text().splitlines()[0] == 'upload'
    for suffix in ('html', 'json'):
        local = run_out / f'report/SART001_qc.{suffix}'
        remote = Path(env['QC_TEST_ROOT']) / f'results/SART001/report/{local.name}'
        assert remote.read_bytes() == local.read_bytes()
    assert 'SARS QC HTML and JSON uploaded and verified' in result.stdout
    if kind.startswith('routine'):
        assert events.read_text().splitlines()[-1] == 'complete'
    else:
        assert 'Done. Final local result location:' in result.stdout
    assert run_out.exists()  # Explicit caller-owned output is retained.


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize('failure', ['missing', 'duplicate', 'upload', 'bad-versioned', 'missing-fasta', 'conflicting-fasta'])
def test_failed_upload_or_merge_stops_completion_and_preserves_results(run_env, kind, failure):
    env, master, run_out, events = run_env
    before = master.read_bytes()
    # Routine cleanup would remove this staged output if completion were reached.
    env['OUTPUT_DIR'] = ''
    if failure != 'missing':
        report = run_out / 'report/SART001.csv'
        report.write_text('Sample\nSEQ1\nSEQ1\n' if failure == 'duplicate' else 'Sample\nSEQ1\n')
    # Never silently fall back to an older primary when a versioned report is malformed.
    if failure == 'bad-versioned':
        (run_out / 'report/SART001_with_software_versions.csv').write_text('Sample\nSEQ1\nSEQ1\n')
    if failure == 'upload':
        env['UPLOAD_STATUS'] = '19'
    if failure == 'missing-fasta':
        (run_out / 'report/SART001.fasta').unlink()
    if failure == 'conflicting-fasta':
        (run_out / 'report/SART001.fasta').write_text('>SEQ1\nACGT\n>SEQ1\nAAAA\n')
    result = run_tail(kind, env)
    assert result.returncode != 0
    assert master.read_bytes() == before
    assert not list(master.parent.glob('*.bak.*'))
    assert not (master.parent / 'master.fasta').exists()
    assert run_out.exists()
    assert 'complete' not in events.read_text().splitlines()
    assert 'cleanup' not in events.read_text().splitlines()
    assert 'Done. Final local result location:' not in result.stdout
    if failure == 'upload':
        assert 'Updating SC2 master' not in result.stdout


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize('skip', ['validation', 'disabled', 'unconfigured'])
def test_skip_controls_still_publish_qc_without_master_or_fasta(run_env, kind, skip):
    env, master, run_out, _ = run_env
    (run_out / 'report/SART001.csv').write_text('Sample\nSEQ1\n')
    (run_out / 'report/SART001.fasta').unlink()
    before = master.read_bytes()
    if skip == 'validation':
        env['VALIDATION_FLAG'] = 'VER'
        env['SARSSEQ_MASTER_CSV'] = '/unavailable/master.csv'
    elif skip == 'disabled':
        env['SARSSEQ_MASTER_UPDATE'] = 'false'
        env['SARSSEQ_MASTER_CSV'] = '/unavailable/master.csv'
    else:
        env['SARSSEQ_MASTER_UPDATE'] = 'auto'
        env.pop('SARSSEQ_MASTER_CSV')
    result = run_tail(kind, env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert master.read_bytes() == before
    assert not (master.parent / 'master.fasta').exists()
    assert 'Master CSV update skipped:' in result.stdout
    assert 'SARS QC HTML and JSON uploaded and verified' in result.stdout


def test_routine_staged_cleanup_only_after_successful_master_update(run_env):
    env, master, run_out, events = run_env
    env['OUTPUT_DIR'] = ''
    (run_out / 'report/SART001.csv').write_text('Sample;RunID\nSEQ1;completed\n')
    result = run_tail('routine-fastq', env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert read_master(master)[0]['NGS_Run_ID'] == 'completed'
    assert events.read_text().splitlines()[-2:] == ['complete', 'cleanup']
    assert not run_out.exists()


def test_offline_preflight_never_invokes_updater(tmp_path):
    # A missing updater would fail immediately if preflight attempted Python.
    env = dict(clean_env(), SCRIPT_DIR=str(SARS), SARSSEQ_MASTER_TOOLS=str(tmp_path / 'missing'),
               SARSSEQ_MASTER_UPDATE='true')
    script = f'''set -euo pipefail
source {shlex.quote(str(HELPER))}
sars_master_preflight fastq '' true
'''
    result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
@pytest.mark.parametrize('failure', [False, True])
def test_routine_offline_qc_without_master_access_or_upload(run_env, workflow, failure):
    env, master, run_out, _ = run_env
    env.update(OFFLINE_MODE='true', SARSSEQ_MASTER_CSV='/unavailable/master.csv',
               SARSSEQ_MASTER_UPDATE='true', MASTER_WORKFLOW=workflow)
    if not failure:
        (run_out / 'report/SART001.csv').write_text('Sample\nSEQ1\n')
    source = WRAPPERS['routine-fastq'].read_text()
    start = source.index('if [ "$OFFLINE_MODE" = true ]; then\n    echo "Offline mode enabled: skipping dashboard')
    before = master.read_bytes()
    script = ('set -euo pipefail\nsource "$INTEGRATION_HELPER"\n'
              'wrapper_logs_complete() { echo COMPLETE; }\n' + source[start:])
    result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
    assert (result.returncode != 0) == failure, result.stdout + result.stderr
    assert ('COMPLETE' in result.stdout) == (not failure)
    assert ('Done. Results' in result.stdout) == (not failure)
    assert not Path(env['EVENTS']).exists()  # No SMB calls, including for master files.
    assert (run_out / 'report/SART001_qc.html').exists() == (not failure)
    assert (run_out / 'report/SART001_qc.json').exists() == (not failure)
    assert master.read_bytes() == before and run_out.exists()


@pytest.mark.parametrize('kind', WRAPPERS)
def test_validation_qc_destination_matches_result_destination(run_env, kind):
    env, master, run_out, events = run_env
    env.update(SKIP_RESULTS_MOVE='true', VALIDATION_FLAG='VER', SARSSEQ_MASTER_UPDATE='true')
    before = master.read_bytes()
    (run_out / 'report/SART001.csv').write_text('Sample\nSEQ1\n')
    result = run_tail(kind, env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert master.read_bytes() == before
    assert 'qc get validation/SART001_qc.json' in events.read_text()
    assert not list((Path(env['QC_TEST_ROOT']) / 'results').rglob('*_qc.*'))
    assert run_out.exists()


@pytest.mark.parametrize('kind', WRAPPERS)
@pytest.mark.parametrize('fault', ['corrupt', 'put-exit', 'get-exit', 'put-status', 'get-status'])
@pytest.mark.parametrize('suffix', ['.html', '.json'])
def test_qc_publishing_failure_retains_results_and_blocks_completion(run_env, kind, fault, suffix):
    env, master, run_out, events = run_env
    env.update(OUTPUT_DIR='', QC_TEST_FAULT=fault, QC_TEST_SUFFIX=suffix)
    (run_out / 'report/SART001.csv').write_text('Sample;RunID\nSEQ1;completed\n')
    result = run_tail(kind, env)
    assert result.returncode != 0
    assert 'uploaded and verified' not in result.stdout
    assert 'Done.' not in result.stdout
    assert 'complete' not in events.read_text().splitlines()
    assert 'cleanup' not in events.read_text().splitlines()
    assert read_master(master)[0]['NGS_Run_ID'] == 'completed'
    assert (run_out / 'report/SART001_qc.html').is_file()
    assert (run_out / 'report/SART001_qc.json').is_file()
    assert not list(master.parent.glob('*.lock'))


def test_qc_upload_retry_completes_before_staged_cleanup(run_env):
    env, master, run_out, events = run_env
    env.update(OUTPUT_DIR='', QC_TEST_FAULT='corrupt')
    (run_out / 'report/SART001.csv').write_text('Sample;RunID\nSEQ1;completed\n')
    assert run_tail('routine-fastq', env).returncode != 0
    before = master.read_bytes()
    backups = set(master.parent.glob('*.bak.*'))
    env.pop('QC_TEST_FAULT')
    result = run_tail('routine-fastq', env)
    assert result.returncode == 0, result.stdout + result.stderr
    assert master.read_bytes() == before
    assert set(master.parent.glob('*.bak.*')) == backups
    assert events.read_text().splitlines()[-3:] == [
        'Required result uploads completed', 'complete', 'cleanup']
    assert not run_out.exists()


@pytest.mark.parametrize('kind', WRAPPERS)
def test_wrapper_qc_threshold_overrides(run_env, kind):
    env, _, run_out, _ = run_env
    env.update(SARSSEQ_QC_COVERAGE_THRESHOLD='90', SARSSEQ_QC_CDS_THRESHOLD='85', SARSSEQ_QC_MIXED_THRESHOLD='4')
    (run_out / 'report/SART001.csv').write_text('Sample\nSEQ1\n')
    result = run_tail(kind, env)
    assert result.returncode == 0, result.stdout + result.stderr
    rules = json.loads((run_out / 'report/SART001_qc.json').read_text())['rules']
    assert rules['coverage_threshold_percent'] == 90
    assert rules['cds_threshold_percent'] == 85
    assert rules['mixed_sites_threshold'] == 4


@pytest.mark.parametrize(('workflow', 'local_fastq', 'offline', 'downloads'), [
    ('fastq-workflow', '', 'true', False),
    ('fastq-workflow', '/local/reads', 'true', False),
    ('fasta-workflow', '', 'true', False),
    ('fastq-workflow', '', 'false', True),
])
def test_input_copy_respects_offline_mode(tmp_path, workflow, local_fastq, offline, downloads):
    source = WRAPPERS['routine-fastq'].read_text()
    start = source.index('if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then\n    echo "Local FASTA input provided;')
    end = source.index('# Locate sample dir & samplesheet', start)
    env = dict(clean_env(), PIPELINE_FILE=workflow, LOCAL_FASTQ_DIR=local_fastq, OFFLINE_MODE=offline,
               TMP_DIR=str(tmp_path), RUN='SART001', SMB_HOST='//unused/share', SMB_AUTH='unused', SMB_INPUT='unused')
    script = 'set -euo pipefail\nsmbclient() { cat >/dev/null; echo DOWNLOAD_ATTEMPT; }\n' + source[start:end]
    result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert ('DOWNLOAD_ATTEMPT' in result.stdout) == downloads


@pytest.mark.parametrize('explicit_fastq', [False, True])
def test_cached_samplesheet_uses_configured_temp_directory(tmp_path, explicit_fastq):
    source = WRAPPERS['routine-fastq'].read_text()
    start = source.index('if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then\n    SAMPLEDIR=""')
    end = source.index('if [ "$PIPELINE_FILE" = "fastq-workflow" ] && [ -z "${SAMPLEDIR}" ]; then', start)
    fastq = tmp_path / 'SART001/X001/fastq_pass'
    fastq.mkdir(parents=True)
    env = dict(clean_env(), PIPELINE_FILE='fastq-workflow', LOCAL_FASTQ_DIR=str(fastq) if explicit_fastq else '',
               LOCAL_SAMPLESHEET='', TMP_DIR=str(tmp_path), RUN='SART001')
    script = 'set -euo pipefail\n' + source[start:end] + 'printf "%s\\n%s\\n" "$SAMPLEDIR" "$SAMPLESHEET"\n'
    result = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.splitlines() == [str(fastq), str(tmp_path / 'SART001.csv')]


@pytest.mark.parametrize('script', [*set(WRAPPERS.values()), HELPER])
def test_shell_syntax(script):
    subprocess.run(['bash', '-n', str(script)], check=True, capture_output=True)
