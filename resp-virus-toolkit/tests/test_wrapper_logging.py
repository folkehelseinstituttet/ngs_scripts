"""Test the wrapper lifecycle with mock SMB, Nextflow and Teams; never live services."""

import json
import os
from pathlib import Path
import signal
import subprocess
import time

import pytest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "resp-virus-toolkit/wrapper_logging.sh"
WORKFLOWS = ("fluseq", "rsvseq", "sarsseq")
SESSION = "01234567-89ab-cdef-0123-456789abcdef"

MOCK_SMB = r'''#!/usr/bin/env python3
import json, os, shlex, shutil, sys
from pathlib import Path
args = sys.argv[1:]
remote = args[args.index('-D') + 1]
commands = args[args.index('-c') + 1] if '-c' in args else sys.stdin.read()
with open(os.environ['SMB_CALLS'], 'a') as out:
    out.write(json.dumps([remote, commands]) + '\n')
directory = Path(os.environ['REMOTE_ROOT']) / remote
mode = os.environ.get('SMB_MODE', '')
if mode == 'offline-forbidden':
    sys.exit(95)
for command in commands.replace(';', '\n').splitlines():
    words = shlex.split(command)
    if not words:
        continue
    op = words[0]
    if op == 'mput':
        if mode == 'result-failure':
            print('NT_STATUS_ACCESS_DENIED opening remote file')
            sys.exit(0)  # A failed command hidden by a successful batch exit.
        if mode == 'result-nonzero':
            sys.exit(23)
    elif op == 'mkdir':
        if not directory.is_dir(): sys.exit(1)
        (directory / words[1]).mkdir(exist_ok=True)
    elif op == 'put':
        source, target = Path(words[1]), directory / words[2]
        if mode == 'archive-failure': sys.exit(29)
        if mode == 'final-archive-failure' and Path(os.environ['CLEAN_CALLS']).exists():
            sys.exit(31)
        if mode != 'missing-upload': shutil.copyfile(source, target)
    elif op == 'get':
        source, target = directory / words[1], Path(words[2])
        if source.is_file(): shutil.copyfile(source, target)
        if mode == 'corrupt-readback' and target.is_file():
            data = target.read_bytes()
            target.write_bytes(b'!' + data[1:])  # Same size, different bytes.
sys.exit(0)
'''

MOCK_NEXTFLOW = r'''#!/usr/bin/env python3
import os, shutil, sys
from pathlib import Path
args = sys.argv[1:]
log = Path(args[args.index('-log') + 1])
for i in range(8, 0, -1):
    older = Path(str(log) + '.' + str(i))
    if older.exists(): older.rename(str(log) + '.' + str(i + 1))
if log.exists(): log.rename(str(log) + '.1')
session = '01234567-89ab-cdef-0123-456789abcdef'
if 'clean' in args:
    with open(os.environ['CLEAN_CALLS'], 'a') as out:
        out.write(' '.join(args) + '\n')
    assert args[-2:] == ['-f', session], args
    log.write_text('Nextflow cleanup for ' + session + '\n')
    print('Nextflow cleanup output')
    if os.environ.get('CLEAN_FAIL'): sys.exit(37)
    shutil.rmtree(Path(os.environ['WORK_ROOT']) / session)
else:
    log.write_text('Session UUID: ' + session + '\n' if not os.environ.get('NO_SESSION') else 'No session ID\n')
    if os.environ.get('SEQERA', 'yes') == 'yes':
        with log.open('a') as out: out.write('https://cloud.seqera.io/watch/current-id\n')
        Path('nf-current-id-reports.tsv').write_text('report\tpath\n')
    print('pipeline stdout')
    print('pipeline stderr', file=sys.stderr)
    sys.exit(int(os.environ.get('PIPELINE_EXIT', '0')))
'''

MOCK_CURL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
payload = json.loads(args[args.index('--data-binary') + 1])
record = {
    'args': args, 'config': sys.stdin.read(), 'payload': payload,
    'local_logs': [p.name for p in Path(os.environ['WRAPPER_LOG_DIR']).glob('*_wrapper.log')],
    'cleaned': Path(os.environ['CLEAN_CALLS']).exists(),
}
with open(os.environ['TEAMS_CALLS'], 'a') as out:
    out.write(json.dumps(record) + '\n')
print(os.environ.get('TEAMS_HTTP', '202'), end='')
sys.exit(int(os.environ.get('TEAMS_CURL_EXIT', '0')))
'''

HARNESS = r'''
set -euo pipefail
source "$HELPER"
wrapper_logs_init "$WORKFLOW" "$RUN_ID"
if [[ "${HOLD:-}" == 1 ]]; then
    printf '%s' "$BASHPID" > "$PID_FILE"
    while :; do sleep 0.05; done
fi
wrapper_logs_nextflow_start
nextflow -log "$NEXTFLOW_LOG" run simulated
WRAPPER_PHASE="Result preparation and uploads"
if [[ -n "$LOG_DESTINATION" ]]; then
    wrapper_smb_upload mock-host -A mock-auth -D "$LOG_DESTINATION" -c 'mput example.csv'
fi
wrapper_logs_status 'Required result uploads completed'
# This large final burst exercises draining the asynchronous tee process.
for ((i=0; i<500; i++)); do printf 'last output %04d\n' "$i"; done
wrapper_logs_complete "$OUTPUT" "$LOG_DESTINATION" "$INPUT_RUN" "$SAMPLESHEET" "$REMOVE_OUTPUT"
'''


@pytest.fixture
def env(tmp_path):
    commands = tmp_path / "commands"
    commands.mkdir()
    for name, source in [("smbclient", MOCK_SMB), ("nextflow", MOCK_NEXTFLOW), ("curl", MOCK_CURL)]:
        script = commands / name
        script.write_text(source)
        script.chmod(0o755)
    paths = {
        "WRAPPER_LOG_DIR": tmp_path / "logs with spaces",
        "REMOTE_ROOT": tmp_path / "remote",
        "OUTPUT": tmp_path / "staged" / "TEST001",
        "INPUT_RUN": tmp_path / "input" / "TEST001",
        "WORK_ROOT": tmp_path / "work",
        "LAUNCH_DIR": tmp_path / "launch",
    }
    for path in paths.values():
        path.mkdir(parents=True)
    (paths["REMOTE_ROOT"] / "routine").mkdir()
    (paths["REMOTE_ROOT"] / "validation").mkdir()
    (paths["OUTPUT"] / "result.txt").write_text("result")
    (paths["INPUT_RUN"] / "input.txt").write_text("input")
    (paths["INPUT_RUN"].parent / "other-run").mkdir()
    (paths["WORK_ROOT"] / SESSION).mkdir()
    (paths["WORK_ROOT"] / "other-session").mkdir()
    samplesheet = paths["INPUT_RUN"].parent / "TEST001.csv"
    samplesheet.write_text("sample\n")
    harness = tmp_path / "harness.sh"
    harness.write_text(HARNESS)
    return dict(
        os.environ,
        **{key: str(path) for key, path in paths.items()},
        HELPER=str(HELPER), HARNESS=str(harness), WORKFLOW="fluseq",
        RUN_ID="TEST001", LOG_DESTINATION="routine", REMOVE_OUTPUT="1",
        SAMPLESHEET=str(samplesheet), SMB_HOST="mock-host", SMB_AUTH="mock-auth",
        SMB_CALLS=str(tmp_path / "smb-calls.jsonl"),
        CLEAN_CALLS=str(tmp_path / "clean-calls.txt"),
        TEAMS_WEBHOOK_FILE=str(tmp_path / "webhook-url"),
        TEAMS_CALLS=str(tmp_path / "teams-calls.jsonl"),
        TEST_MODE="false", OFFLINE_MODE="false",
        PID_FILE=str(tmp_path / "wrapper.pid"),
        PATH=str(commands) + os.pathsep + os.environ["PATH"],
    )


@pytest.fixture
def teams_env(env):
    Path(env["TEAMS_WEBHOOK_FILE"]).write_text("https://teams.example.invalid/webhook?sig=TEST_SECRET\n")
    return env


def teams_call(env):
    calls = Path(env["TEAMS_CALLS"]).read_text().splitlines()
    assert len(calls) == 1
    call = json.loads(calls[0])
    message = call["payload"]
    assert message["type"] == "message"
    attachment = message["attachments"][0]
    assert attachment["contentType"] == "application/vnd.microsoft.card.adaptive"
    card = attachment["content"]
    assert card["type"] == "AdaptiveCard" and card["version"] == "1.4"
    return call, card["body"]


def run(env, **overrides):
    return subprocess.run(
        ["bash", env["HARNESS"]], env=dict(env, **overrides),
        cwd=env["LAUNCH_DIR"], capture_output=True, text=True, timeout=20,
    )


def local(env, suffix):
    return Path(env["WRAPPER_LOG_DIR"]) / f'{env["WORKFLOW"]}_{env["RUN_ID"]}_{suffix}'


def assert_retained(env):
    for suffix in ("wrapper.log", "wrapper_error.log", "status.txt", "nextflow.log"):
        assert local(env, suffix).is_file(), suffix
    assert Path(env["OUTPUT"], "result.txt").is_file()
    assert Path(env["INPUT_RUN"], "input.txt").is_file()
    assert Path(env["SAMPLESHEET"]).is_file()
    assert Path(env["WORK_ROOT"], SESSION).is_dir()


@pytest.mark.parametrize("workflow", WORKFLOWS)
def test_success_archives_final_logs_and_cleans_only_this_run(env, workflow):
    env["WORKFLOW"] = workflow
    # A failed earlier attempt, plus a manifest belonging to another run.
    local(env, "nextflow.log.1").write_text('https://cloud.seqera.io/watch/old-id\n')
    local(env, "nextflow.log.notes").write_text("unrelated file")
    launch = Path(env["LAUNCH_DIR"])
    (launch / "nf-old-id-reports.tsv").write_text("old report\n")
    (launch / "nf-unrelated-reports.tsv").write_text("other run\n")
    result = run(env)
    assert result.returncode == 0, result.stdout + result.stderr
    remote = Path(env["REMOTE_ROOT"], "routine/TEST001/logs")
    console = (remote / f"{workflow}_TEST001_wrapper.log").read_text()
    assert "pipeline stdout" in console and "pipeline stderr" in console
    assert "last output 0499" in console
    assert "Nextflow cleanup output" in console
    assert "Intermediate cleanup complete" in console
    assert "Removed staged results" in console
    status = (remote / f"{workflow}_TEST001_status.txt").read_text()
    assert "Processing completed successfully" in status
    assert "Intermediate cleanup complete" in status
    assert (remote / "nf-current-id-reports.tsv").is_file()
    assert (remote / "nf-old-id-reports.tsv").is_file()
    assert not (remote / "nf-unrelated-reports.tsv").exists()
    assert not local(env, "wrapper.log").exists()
    assert not local(env, "nextflow.log").exists()
    assert local(env, "nextflow.log.notes").read_text() == "unrelated file"
    assert not (launch / "nf-current-id-reports.tsv").exists()
    assert (launch / "nf-unrelated-reports.tsv").is_file()
    assert not Path(env["OUTPUT"]).exists()
    assert not Path(env["INPUT_RUN"]).exists()
    assert not Path(env["SAMPLESHEET"]).exists()
    assert not Path(env["WORK_ROOT"], SESSION).exists()
    assert Path(env["WORK_ROOT"], "other-session").is_dir()
    assert Path(env["INPUT_RUN"]).parent.joinpath("other-run").is_dir()


@pytest.mark.parametrize("code", [7, 42])
def test_pipeline_failure_preserves_logs_data_and_exit_code(env, code):
    result = run(env, PIPELINE_EXIT=str(code))
    assert result.returncode == code
    assert_retained(env)
    assert "Error at" in local(env, "wrapper_error.log").read_text()
    assert f"error code {code}" in local(env, "status.txt").read_text()
    assert not Path(env["CLEAN_CALLS"]).exists()
    assert not Path(env["SMB_CALLS"]).exists()


@pytest.mark.parametrize("mode", [
    "result-failure", "result-nonzero", "archive-failure", "missing-upload", "corrupt-readback",
])
def test_upload_failure_or_bad_readback_prevents_cleanup(env, mode):
    result = run(env, SMB_MODE=mode)
    assert result.returncode != 0, result.stdout + result.stderr
    assert_retained(env)
    assert not Path(env["CLEAN_CALLS"]).exists()
    assert "failed" in local(env, "wrapper.log").read_text().lower()


def test_final_archive_failure_retains_logs_after_verified_cleanup(env):
    result = run(env, SMB_MODE="final-archive-failure")
    assert result.returncode == 31
    for suffix in ("wrapper.log", "wrapper_error.log", "status.txt", "nextflow.log"):
        assert local(env, suffix).is_file()
    assert "Log archival/cleanup failed" in local(env, "status.txt").read_text()
    assert Path(env["REMOTE_ROOT"], "routine/TEST001/logs/fluseq_TEST001_wrapper.log").is_file()


def test_cleanup_failure_preserves_logs_and_remaining_data(env):
    result = run(env, CLEAN_FAIL="1")
    assert result.returncode == 37
    assert_retained(env)
    assert "Nextflow cleanup output" in local(env, "wrapper.log").read_text()


@pytest.mark.parametrize("workflow", WORKFLOWS)
def test_validation_keeps_full_results_but_archives_logs(env, workflow):
    env["WORKFLOW"] = workflow
    result = run(env, LOG_DESTINATION="validation", REMOVE_OUTPUT="0")
    assert result.returncode == 0, result.stdout + result.stderr
    assert Path(env["OUTPUT"], "result.txt").is_file()
    assert Path(env["REMOTE_ROOT"], f"validation/TEST001/logs/{workflow}_TEST001_wrapper.log").is_file()
    assert not local(env, "wrapper.log").exists()
    assert not Path(env["INPUT_RUN"]).exists()


def test_offline_retains_logs_results_and_intermediates_without_smb(env):
    result = run(env, LOG_DESTINATION="", SMB_MODE="offline-forbidden")
    assert result.returncode == 0, result.stdout + result.stderr
    assert_retained(env)
    assert Path(env["OUTPUT"], "logs/fluseq_TEST001_wrapper.log").is_file()
    assert not Path(env["CLEAN_CALLS"]).exists()
    assert not Path(env["SMB_CALLS"]).exists()


def test_absent_seqera_manifest_is_optional(env):
    result = run(env, SEQERA="no")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not list(Path(env["REMOTE_ROOT"]).rglob("nf-*-reports.tsv"))


def test_unidentified_session_never_cleans_the_last_run(env):
    result = run(env, NO_SESSION="1")
    assert result.returncode == 0, result.stdout + result.stderr
    assert not Path(env["CLEAN_CALLS"]).exists()
    assert Path(env["WORK_ROOT"], SESSION).is_dir()
    assert Path(env["WORK_ROOT"], "other-session").is_dir()
    archived = Path(env["REMOTE_ROOT"], "routine/TEST001/logs/fluseq_TEST001_wrapper.log")
    assert "retaining work files" in archived.read_text()


def test_retry_archives_previous_failed_attempt(env):
    failed = run(env, PIPELINE_EXIT="42")
    assert failed.returncode == 42
    succeeded = run(env)
    assert succeeded.returncode == 0, succeeded.stdout + succeeded.stderr
    archived = Path(env["REMOTE_ROOT"], "routine/TEST001/logs/fluseq_TEST001_wrapper.log")
    assert "error code 42" in archived.read_text()
    assert "Processing completed successfully" in archived.read_text()
    assert not local(env, "wrapper.log").exists()


def test_explicit_output_and_user_inputs_are_retained(env):
    result = run(env, INPUT_RUN="", SAMPLESHEET="", REMOVE_OUTPUT="0")
    assert result.returncode == 0, result.stdout + result.stderr
    assert Path(env["OUTPUT"], "result.txt").is_file()
    assert Path(env["INPUT_RUN"], "input.txt").is_file()
    assert Path(env["SAMPLESHEET"]).is_file()


@pytest.mark.parametrize(("sig", "code"), [(signal.SIGTERM, 143), (signal.SIGINT, 130), (signal.SIGHUP, 129)])
def test_signal_keeps_logs_and_original_signal_exit_code(teams_env, sig, code):
    env = teams_env
    proc = subprocess.Popen(
        ["bash", env["HARNESS"]], env=dict(env, HOLD="1"), cwd=env["LAUNCH_DIR"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        deadline = time.monotonic() + 5
        while not Path(env["PID_FILE"]).exists():
            assert time.monotonic() < deadline
            time.sleep(0.01)
        proc.send_signal(sig)
        proc.communicate(timeout=5)
        assert proc.returncode == code
        assert "Received SIG" in local(env, "status.txt").read_text()
        assert local(env, "wrapper.log").is_file()
        assert not Path(env["CLEAN_CALLS"]).exists()
        _, body = teams_call(env)
        assert f"exit code {code}" in body[1]["text"]
        assert "Received SIG" in json.dumps(body)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.communicate(timeout=5)


def test_duplicate_run_cannot_modify_active_logs(env):
    proc = subprocess.Popen(
        ["bash", env["HARNESS"]], env=dict(env, HOLD="1"), cwd=env["LAUNCH_DIR"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        deadline = time.monotonic() + 5
        while not Path(env["PID_FILE"]).exists():
            assert time.monotonic() < deadline
            time.sleep(0.01)
        before = local(env, "status.txt").read_bytes()
        duplicate = run(env)
        assert duplicate.returncode != 0
        assert "already using run" in duplicate.stderr
        assert local(env, "status.txt").read_bytes() == before
    finally:
        proc.terminate()
        proc.communicate(timeout=5)


@pytest.mark.parametrize(("workflow", "flags"),
                         [(workflow, flags) for workflow in WORKFLOWS for flags in ([], ["-t"])]
                         + [("sarsseq", ["--test"]), ("sarsseq", ["-o"])])
def test_actual_wrapper_captures_conda_setup_failure(teams_env, workflow, tmp_path, flags):
    env = teams_env
    env["WORKFLOW"] = workflow
    env["RUN_ID"] = "WRAPPER_LOGGING_TEST"
    conda = tmp_path / "conda.sh"
    conda.write_text('echo "simulated conda failure" >&2\nreturn 17\n')
    result = subprocess.run(
        ["bash", str(ROOT / workflow / f"{workflow}_wrapper.sh"),
         "-r", env["RUN_ID"], "-a", "test", "-s", "Ses2526", "-y", "2026"]
        + flags,
        env=dict(env, CONDA_PROFILE=str(conda)), capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == 17, result.stdout + result.stderr
    assert "simulated conda failure" in local(env, "wrapper.log").read_text()
    assert "error code 17" in local(env, "status.txt").read_text()
    assert not Path(env["SMB_CALLS"]).exists()
    if flags:
        assert not Path(env["TEAMS_CALLS"]).exists()
        assert "Teams notifications disabled" in result.stdout
    else:
        _, body = teams_call(env)
        assert body[0]["text"].endswith("WRAPPER_LOGGING_TEST: failed")
        assert "during Setup (exit code 17)" in body[1]["text"]


@pytest.mark.parametrize("workflow", WORKFLOWS)
def test_help_does_not_initialize_conda_or_logs(teams_env, workflow):
    env = teams_env
    result = subprocess.run(
        ["bash", str(ROOT / workflow / f"{workflow}_wrapper.sh"), "-h"],
        env=dict(env, CONDA_PROFILE="/nonexistent/conda.sh"), capture_output=True, text=True, timeout=5,
    )
    assert result.returncode == 0
    assert not list(Path(env["WRAPPER_LOG_DIR"]).iterdir())
    assert not Path(env["TEAMS_CALLS"]).exists()


@pytest.mark.parametrize(("workflow", "label"), [
    ("fluseq", "Influenza"), ("rsvseq", "RSV"), ("sarsseq", "SARS-CoV-2"),
])
def test_success_notifies_after_final_archive_and_cleanup(teams_env, workflow, label):
    env = teams_env
    result = run(env, WORKFLOW=workflow)
    assert result.returncode == 0, result.stdout + result.stderr
    call, body = teams_call(env)
    assert body[0]["text"] == f"✅ {label} — TEST001: completed"
    assert body[0]["color"] == "Good"
    assert "including required result and log uploads and cleanup" in body[1]["text"]
    facts = {f["title"]: f["value"] for f in body[2]["facts"]}
    assert facts["Exit code"] == "0" and facts["Stage"] == "Completed"
    assert facts["Started"] and facts["Finished"] and facts["Duration"]
    assert "routine/TEST001/logs" in body[3]["text"]
    assert "Intermediate cleanup complete" in json.dumps(body)
    assert call["cleaned"] and not call["local_logs"]
    assert not list(Path(env["WRAPPER_LOG_DIR"]).glob("*_wrapper.log"))
    assert "Teams notification accepted (HTTP 202)" in result.stdout
    assert "TEST_SECRET" not in result.stdout + result.stderr
    assert all("TEST_SECRET" not in arg for arg in call["args"])
    assert call["config"] == 'url = "https://teams.example.invalid/webhook?sig=TEST_SECRET"\n'
    assert call["args"][0] == "--disable"
    assert call["args"][call["args"].index("--max-time") + 1] == "15"


@pytest.mark.parametrize(("overrides", "code", "stage"), [
    ({"PIPELINE_EXIT": "42"}, 42, "Nextflow"),
    ({"SMB_MODE": "result-nonzero"}, 23, "Result preparation and uploads"),
    ({"SMB_MODE": "archive-failure"}, 29, "Initial log upload"),
    ({"CLEAN_FAIL": "1"}, 37, "Cleanup"),
    ({"SMB_MODE": "final-archive-failure"}, 31, "Final log upload"),
])
def test_notification_reflects_final_failure(teams_env, overrides, code, stage):
    result = run(teams_env, **overrides)
    assert result.returncode == code, result.stdout + result.stderr
    call, body = teams_call(teams_env)
    assert body[0]["text"].endswith(": failed") and body[0]["color"] == "Attention"
    assert f"during {stage} (exit code {code})" in body[1]["text"]
    assert "Local logs on" in body[3]["text"]
    assert call["local_logs"]
    assert any("Error at" in item.get("text", "") or "failed (exit code" in item.get("text", "") for item in body)


@pytest.mark.parametrize("code", [0, 42])
@pytest.mark.parametrize(("http", "curl_exit"), [("400", "0"), ("500", "0"), ("000", "28")])
def test_teams_delivery_failure_preserves_wrapper_outcome(teams_env, code, http, curl_exit):
    result = run(teams_env, PIPELINE_EXIT=str(code), TEAMS_HTTP=http, TEAMS_CURL_EXIT=curl_exit)
    assert result.returncode == code
    teams_call(teams_env)
    assert "WARNING: Teams notification failed" in result.stdout
    assert local(teams_env, "wrapper.log").exists() == (code != 0)


@pytest.mark.parametrize("overrides", [
    {"TEST_MODE": "true"},
    {"OFFLINE_MODE": "true", "LOG_DESTINATION": "", "SMB_MODE": "offline-forbidden"},
])
@pytest.mark.parametrize("code", [0, 42])
def test_test_and_offline_runs_never_post(teams_env, overrides, code):
    result = run(teams_env, PIPELINE_EXIT=str(code), **overrides)
    assert result.returncode == code
    assert not Path(teams_env["TEAMS_CALLS"]).exists()


@pytest.mark.parametrize("url", [None, "", "http://example.invalid/secret", 'https://example.invalid/"secret',
                                 "https://example.invalid/\\secret", "https://example.invalid/ secret"])
def test_missing_or_invalid_webhook_is_optional(env, url):
    if url is not None:
        Path(env["TEAMS_WEBHOOK_FILE"]).write_text(url)
    result = run(env)
    assert result.returncode == 0
    assert "Teams notification skipped" in result.stdout
    assert not Path(env["TEAMS_CALLS"]).exists()
    assert not local(env, "wrapper.log").exists()


@pytest.mark.parametrize("line_ending", [b"", b"\r\n"])
def test_payload_escapes_values_and_marks_validation(teams_env, line_ending):
    branch = 'test/"quoted"\\branch\næøå'
    # URL files without a final newline and CRLF files both work.
    Path(teams_env["TEAMS_WEBHOOK_FILE"]).write_bytes(b"https://example.invalid/test" + line_ending)
    result = run(teams_env, PIPELINE_BRANCH=branch, VALIDATION_FLAG="VER", LOG_DESTINATION="validation", REMOVE_OUTPUT="0")
    assert result.returncode == 0
    _, body = teams_call(teams_env)
    facts = {f["title"]: f["value"] for f in body[2]["facts"]}
    assert facts["Pipeline branch/tag"] == branch
    assert facts["Mode"] == "Validation (VER)"
    assert "validation/TEST001/logs" in body[3]["text"]


@pytest.mark.parametrize(("workflow", "suffix"), [("fluseq", "inf"), ("rsvseq", "rsv"), ("sarsseq", "sars")])
def test_default_webhook_filename(env, workflow, suffix):
    script = 'source "$HELPER"; wrapper_logs_init "$WORKFLOW" "$RUN_ID"; printf "WEBHOOK_FILE=%s\\n" "$TEAMS_WEBHOOK_FILE"'
    environ = dict(env, WORKFLOW=workflow, TEST_MODE="true")
    del environ["TEAMS_WEBHOOK_FILE"]
    result = subprocess.run(["bash", "-euc", script], env=environ, capture_output=True, text=True, timeout=5)
    assert result.returncode == 0
    assert f'WEBHOOK_FILE={environ["HOME"]}/.teams_webhook_{suffix}' in result.stdout
    assert not Path(env["TEAMS_CALLS"]).exists()
