#!/usr/bin/env bash
# Shared lifecycle for the fluseq, rsvseq and sarsseq wrappers. Source this file,
# call wrapper_logs_init after parsing arguments (before setup), and call
# wrapper_logs_complete only after all required processing/uploads succeed.
# Always use explicit return statuses: a bare return inside an EXIT trap can
# inherit the pre-trap status instead of the command failure being handled.

wrapper_logs_status() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    # Keep this attempt's recent progress available after successful log deletion.
    WRAPPER_RECENT_STATUS+=("$message")
    if (( ${#WRAPPER_RECENT_STATUS[@]} > 6 )); then
        WRAPPER_RECENT_STATUS=("${WRAPPER_RECENT_STATUS[@]: -6}")
    fi
    printf '%s\n' "$message" >> "$LOGFILE" || return "$?"
    printf '%s\n' "$message" >> "$STATUS_FILE" || return "$?"
    if [[ "$WRAPPER_LOG_STREAM_OPEN" == 0 ]]; then
        printf '%s\n' "$message" >> "$WRAPPER_LOG" || return "$?"
    fi
    printf '%s\n' "$message"
}

wrapper_logs_init() {
    local workflow="$1" run="${2:-unknown-$$}" file
    if [[ ! "$workflow" =~ ^[a-z][a-z0-9_]*$ || ! "$run" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        printf 'ERROR: Invalid workflow/run name for log files: %s/%s\n' "$workflow" "$run" >&2
        return 2
    fi
    WRAPPER_LOG_DIR="${WRAPPER_LOG_DIR:-$HOME}"
    mkdir -p -- "$WRAPPER_LOG_DIR" || return "$?"
    WRAPPER_LOG_DIR="$(cd -- "$WRAPPER_LOG_DIR" && pwd)" || return "$?"
    # These characters cannot safely be embedded in smbclient's command syntax.
    case "$WRAPPER_LOG_DIR" in
        *';'*|*'"'*|*$'\n'*|*$'\r'*|*'\'*) echo 'ERROR: Unsupported character in WRAPPER_LOG_DIR' >&2; return 2 ;;
    esac
    WRAPPER_LOG_RUN="$run"
    LOG_PREFIX="$WRAPPER_LOG_DIR/${workflow}_${run}"
    LOGFILE="${LOG_PREFIX}_wrapper_error.log"
    STATUS_FILE="${LOG_PREFIX}_status.txt"
    WRAPPER_LOG="${LOG_PREFIX}_wrapper.log"
    NEXTFLOW_LOG="${LOG_PREFIX}_nextflow.log"

    # Keep the lock file: unlinking a flock file can let concurrent runs acquire
    # different inodes. The lock itself is released when this process exits.
    exec {WRAPPER_LOG_LOCK_FD}>"${LOG_PREFIX}.lock" || return "$?"
    if ! flock -n "$WRAPPER_LOG_LOCK_FD"; then
        echo "ERROR: Another $workflow wrapper is already using run $run" >&2
        return 1
    fi
    for file in "$WRAPPER_LOG" "$LOGFILE" "$STATUS_FILE"; do
        touch -- "$file" || return "$?"
    done
    WRAPPER_RUN_COMPLETE=0
    WRAPPER_RECENT_STATUS=()
    WRAPPER_PHASE="Setup"
    WRAPPER_STARTED_AT="$(date --iso-8601=seconds)"
    WRAPPER_STARTED_SECONDS=$SECONDS
    local webhook_name
    case "$workflow" in
        fluseq) WRAPPER_DISPLAY_NAME="Influenza"; webhook_name=inf ;;
        rsvseq) WRAPPER_DISPLAY_NAME="RSV"; webhook_name=rsv ;;
        sarsseq) WRAPPER_DISPLAY_NAME="SARS-CoV-2"; webhook_name=sars ;;
        *) WRAPPER_DISPLAY_NAME="$workflow"; webhook_name="$workflow" ;;
    esac
    TEAMS_WEBHOOK_FILE="${TEAMS_WEBHOOK_FILE:-$HOME/.teams_webhook_$webhook_name}"
    LOGS_UPLOADED=0
    WRAPPER_LOG_OUTPUT_DIR=""
    WRAPPER_LOG_REMOTE_BASE=""
    WRAPPER_NF_LAUNCH_DIR=""
    WRAPPER_CLEAN_INPUT_DIR=""
    WRAPPER_CLEAN_SAMPLESHEET=""
    WRAPPER_REMOVE_OUTPUT=0
    WRAPPER_LOG_STREAM_OPEN=1
    exec {WRAPPER_CONSOLE_OUT}>&1 {WRAPPER_CONSOLE_ERR}>&2
    exec > >(
        trap '' HUP INT TERM
        exec {WRAPPER_LOG_LOCK_FD}>&-
        exec tee --output-error=warn-nopipe -a "$WRAPPER_LOG"
    ) 2>&1
    WRAPPER_TEE_PID=$!
    set -E
    trap 'wrapper_logs_status "Error at ${BASH_SOURCE[0]:-$0}:$LINENO (exit code $?)"' ERR
    trap 'wrapper_logs_status "Received SIGINT"; exit 130' INT
    trap 'wrapper_logs_status "Received SIGTERM"; exit 143' TERM
    trap 'wrapper_logs_status "Received SIGHUP"; exit 129' HUP
    trap 'wrapper_logs_exit "$?"' EXIT
    wrapper_logs_status "Started $workflow wrapper for run $run"
    if [[ "${TEST_MODE:-false}" == true || "${OFFLINE_MODE:-false}" == true ]]; then
        wrapper_logs_status 'Teams notifications disabled for this test/offline run'
    fi
    printf 'Console log: %s\nStatus: %s\nNextflow log: %s\n' "$WRAPPER_LOG" "$STATUS_FILE" "$NEXTFLOW_LOG"
}

# Call immediately before Nextflow run so Seqera manifests are resolved against
# the actual launch directory, including on retries.
wrapper_logs_nextflow_start() {
    WRAPPER_PHASE="Nextflow"
    WRAPPER_NF_LAUNCH_DIR="$PWD"
    wrapper_logs_status "Starting Nextflow; log: $NEXTFLOW_LOG"
}

wrapper_logs_complete() {
    WRAPPER_LOG_OUTPUT_DIR="$(cd -- "$1" && pwd)/logs" || return "$?"
    WRAPPER_LOG_REMOTE_BASE="${2:-}"
    case "$WRAPPER_LOG_REMOTE_BASE" in
        *';'*|*'"'*|*$'\n'*|*$'\r'*|*'\'*) echo 'ERROR: Unsupported character in log upload destination' >&2; return 2 ;;
    esac
    WRAPPER_CLEAN_INPUT_DIR="${3:-}"
    WRAPPER_CLEAN_SAMPLESHEET="${4:-}"
    WRAPPER_REMOVE_OUTPUT="${5:-0}"
    WRAPPER_RUN_COMPLETE=1
}

# smbclient batch sessions can report individual transfer errors in their
# output. Treat those as failures even if the process exits with status zero.
# This function is only for uploads; it does not change download behaviour.
wrapper_smb_upload() {
    local transcript ec=0
    transcript=$(mktemp "$WRAPPER_LOG_DIR/.wrapper-upload.XXXXXX") || return "$?"
    smbclient "$@" 2>&1 | tee --output-error=warn-nopipe "$transcript" || ec=$?
    if grep -Eq 'NT_STATUS_|(^|[[:space:]])(Error|ERROR|failed|Failed)([[:space:]:]|$)' "$transcript"; then
        ec=1
    fi
    rm -f -- "$transcript"
    if (( ec != 0 )); then
        wrapper_logs_status "SMB upload failed (exit code $ec); retaining local logs"
    fi
    return "$ec"
}

wrapper_logs_collect() {
    local file id manifest
    local -a nextflow_logs=()
    local -A seen=()
    WRAPPER_LOG_FILES=("$WRAPPER_LOG" "$LOGFILE" "$STATUS_FILE")
    for file in "$NEXTFLOW_LOG" "$NEXTFLOW_LOG".[0-9]*; do
        [[ -f "$file" ]] || continue
        [[ "$file" == "$NEXTFLOW_LOG" || "${file##*.}" =~ ^[0-9]+$ ]] || continue
        nextflow_logs+=("$file")
        WRAPPER_LOG_FILES+=("$file")
    done
    [[ -n "$WRAPPER_NF_LAUNCH_DIR" ]] || return 0
    # Read current and rotated logs: an earlier failed attempt can have its own
    # Seqera ID. Never sweep every nf-*-reports.tsv from the shared home folder.
    for file in "${nextflow_logs[@]}"; do
        while IFS= read -r id; do
            id="${id#watch/}"
            manifest="$WRAPPER_NF_LAUNCH_DIR/nf-${id}-reports.tsv"
            if [[ -f "$manifest" && -z "${seen[$manifest]:-}" ]]; then
                WRAPPER_LOG_FILES+=("$manifest")
                seen["$manifest"]=1
            fi
        done < <(grep -oE 'watch/[A-Za-z0-9_-]+' "$file" || true)
    done
}

wrapper_logs_stop_stream() {
    exec 1>&"$WRAPPER_CONSOLE_OUT" 2>&"$WRAPPER_CONSOLE_ERR"
    WRAPPER_LOG_STREAM_OPEN=0
    # Closing every writer before waiting ensures the archive contains the last
    # status line, even when tee is slower than the wrapper.
    wait "$WRAPPER_TEE_PID"
}

wrapper_logs_upload_archive() {
    local archive="$1" file name remote
    remote="${WRAPPER_LOG_REMOTE_BASE%/}/$WRAPPER_LOG_RUN"
    # Existing directories are normal on retries. Subsequent transfers use -D
    # directly and fail if the destination could not be created/accessed.
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$WRAPPER_LOG_REMOTE_BASE" \
        -c "mkdir \"$WRAPPER_LOG_RUN\"" || true
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$remote" -c 'mkdir logs' || true
    remote="$remote/logs"
    for file in "${WRAPPER_LOG_FILES[@]}"; do
        name="${file##*/}"
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$remote" \
            -c "put \"$archive/logs/$name\" \"$name\"" || return "$?"
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$remote" \
            -c "get \"$name\" \"$archive/verify/$name\"" || return "$?"
        # A fresh read-back also catches failed transfers hidden by a zero exit
        # status. Compare bytes, rather than trusting file names or sizes.
        cmp -s -- "$archive/logs/$name" "$archive/verify/$name" || {
            printf 'ERROR: Remote log verification failed: %s/%s\n' "$remote" "$name"
            return 1
        }
    done
}

wrapper_logs_archive() {
    local delete_local="${1:-0}" archive file name ec=0
    archive=$(mktemp -d "$WRAPPER_LOG_DIR/.wrapper-archive.XXXXXX") || return "$?"
    mkdir -p -- "$archive/logs" "$archive/verify" "$WRAPPER_LOG_OUTPUT_DIR" || return "$?"
    for file in "${WRAPPER_LOG_FILES[@]}"; do
        name="${file##*/}"
        cp -- "$file" "$archive/logs/$name" || return "$?"
        if [[ ! "$file" -ef "$WRAPPER_LOG_OUTPUT_DIR/$name" ]]; then
            cp -- "$file" "$WRAPPER_LOG_OUTPUT_DIR/$name" || return "$?"
        fi
    done
    if [[ -z "$WRAPPER_LOG_REMOTE_BASE" ]]; then
        printf 'Logs retained locally in %s and %s\n' "$WRAPPER_LOG_DIR" "$WRAPPER_LOG_OUTPUT_DIR"
        rm -rf -- "$archive"
        return 0
    fi
    wrapper_logs_upload_archive "$archive" > "$archive/transfer.log" 2>&1 || ec=$?
    if (( ec != 0 )); then
        cat "$archive/transfer.log" >> "$WRAPPER_LOG"
        cat "$archive/transfer.log" >&2
        rm -rf -- "$archive"
        return "$ec"
    fi
    LOGS_UPLOADED=1
    if [[ "$delete_local" == 0 ]]; then
        rm -rf -- "$archive"
        return 0
    fi
    # Only delete files in this verified snapshot. Preserve unrelated files,
    # work directories, Nextflow's resume cache, and other runs' manifests.
    for file in "${WRAPPER_LOG_FILES[@]}"; do
        name="${file##*/}"
        cmp -s -- "$file" "$archive/logs/$name" || { ec=1; break; }
    done
    if (( ec == 0 )); then
        for file in "${WRAPPER_LOG_FILES[@]}"; do
            rm -f -- "$file" "$WRAPPER_LOG_OUTPUT_DIR/${file##*/}" || ec=$?
        done
        rmdir -- "$WRAPPER_LOG_OUTPUT_DIR" 2>/dev/null || true
    fi
    rm -rf -- "$archive"
    if (( ec == 0 )); then
        printf 'Logs verified on N: %s/%s/logs; local run logs removed.\n' "$WRAPPER_LOG_REMOTE_BASE" "$WRAPPER_LOG_RUN"
    fi
    return "$ec"
}

wrapper_logs_cleanup_run() {
    local session input
    if [[ -n "$WRAPPER_CLEAN_INPUT_DIR" && -d "$WRAPPER_CLEAN_INPUT_DIR" ]]; then
        input="$(cd -- "$WRAPPER_CLEAN_INPUT_DIR" && pwd)" || return "$?"
        [[ "$WRAPPER_LOG_DIR/" != "$input/"* ]] || {
            wrapper_logs_status 'ERROR: Refusing to clean an input directory containing the live logs'
            return 2
        }
    fi
    # Do not guess 'last': another workflow may have launched from the same
    # directory. A missing session ID means work files must be retained.
    session=$(sed -nE 's/.*Session UUID: ([[:xdigit:]-]+).*/\1/p' "$NEXTFLOW_LOG" | tail -n 1)
    if [[ "$session" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ && -n "$WRAPPER_NF_LAUNCH_DIR" ]]; then
        wrapper_logs_status "Cleaning Nextflow work for session $session" || return "$?"
        (cd -- "$WRAPPER_NF_LAUNCH_DIR" && nextflow -log "$NEXTFLOW_LOG" clean -f "$session") >> "$WRAPPER_LOG" 2>&1 || return "$?"
    else
        wrapper_logs_status 'WARNING: Nextflow session could not be identified; retaining work files' || return "$?"
    fi
    if [[ -n "$WRAPPER_CLEAN_INPUT_DIR" ]]; then
        [[ "${WRAPPER_CLEAN_INPUT_DIR##*/}" == "$WRAPPER_LOG_RUN" ]] || return 2
        rm -rf -- "$WRAPPER_CLEAN_INPUT_DIR" || return "$?"
    fi
    if [[ -n "$WRAPPER_CLEAN_SAMPLESHEET" ]]; then
        [[ "${WRAPPER_CLEAN_SAMPLESHEET##*/}" == "$WRAPPER_LOG_RUN.csv" ]] || return 2
        rm -f -- "$WRAPPER_CLEAN_SAMPLESHEET" || return "$?"
    fi
    wrapper_logs_status 'Intermediate cleanup complete; finalizing log archive.'
}

wrapper_logs_finalize() {
    local output
    WRAPPER_PHASE="Initial log upload"
    wrapper_logs_collect || return "$?"
    # Offline runs keep their output, logs and intermediates locally.
    wrapper_logs_archive 0 || return "$?"
    [[ -n "$WRAPPER_LOG_REMOTE_BASE" ]] || return 0
    wrapper_logs_status 'Initial log archive verified; starting run cleanup.' || return "$?"
    WRAPPER_PHASE="Cleanup"
    wrapper_logs_cleanup_run || return "$?"
    if [[ "$WRAPPER_REMOVE_OUTPUT" == 1 ]]; then
        output="${WRAPPER_LOG_OUTPUT_DIR%/logs}"
        [[ "${output##*/}" == "$WRAPPER_LOG_RUN" ]] || return 2
        # Refuse to remove an output tree containing the authoritative live logs.
        [[ "$WRAPPER_LOG_DIR/" != "$output/"* ]] || return 2
        rm -rf -- "$output" || return "$?"
        wrapper_logs_status "Removed staged results for $WRAPPER_LOG_RUN" || return "$?"
    fi
    # Nextflow clean can rotate the Nextflow log. Refresh the file list and
    # upload the final logs, including cleanup output, before deleting any logs.
    WRAPPER_PHASE="Final log upload"
    wrapper_logs_collect || return "$?"
    wrapper_logs_archive 1 || return "$?"
    if [[ "$WRAPPER_REMOVE_OUTPUT" == 1 ]]; then
        # The final snapshot temporarily recreated output/logs. Remove the now
        # empty output directory without touching anything added concurrently.
        rmdir -- "$output" 2>/dev/null || true
    fi
}

# Delivery is best effort and happens after final archival/cleanup. Never write
# through wrapper_logs_status here: that would recreate successfully deleted logs.
wrapper_teams_notify() {
    local ec="$1" webhook_url="" payload http curl_ec=0 outcome=failed logs
    [[ "${TEST_MODE:-false}" != true && "${OFFLINE_MODE:-false}" != true ]] || return 0
    if [[ ! -r "$TEAMS_WEBHOOK_FILE" ]]; then
        printf 'Teams notification skipped: webhook file is missing or unreadable: %s\n' "$TEAMS_WEBHOOK_FILE"
        return 0
    fi
    IFS= read -r webhook_url < "$TEAMS_WEBHOOK_FILE" || true
    webhook_url="${webhook_url%$'\r'}"
    # Restrict curl's config input to one HTTPS URL; never print its secret value.
    if [[ "$webhook_url" != https://?* || "$webhook_url" == *[[:space:]\"\\]* ]]; then
        printf 'Teams notification skipped: webhook file must contain an HTTPS URL on one line.\n'
        return 0
    fi
    if ! command -v python3 >/dev/null || ! command -v curl >/dev/null; then
        printf 'Teams notification skipped: python3 and curl are required.\n'
        return 0
    fi
    logs="Local logs on ${HOSTNAME:-unknown}: $WRAPPER_LOG_DIR (run $WRAPPER_LOG_RUN); remaining files retained on failure."
    if (( ec == 0 && WRAPPER_RUN_COMPLETE == 1 )); then
        outcome=completed
        WRAPPER_PHASE="Completed"
        if [[ "$LOGS_UPLOADED" == 1 ]]; then
            logs="Logs on N: ${WRAPPER_LOG_REMOTE_BASE%/}/$WRAPPER_LOG_RUN/logs"
        else
            logs="Local logs: $WRAPPER_LOG_DIR and $WRAPPER_LOG_OUTPUT_DIR"
        fi
    elif (( ec == 0 )); then
        outcome="exited before completion"
    fi
    payload=$(python3 - "$WRAPPER_DISPLAY_NAME" "$WRAPPER_LOG_RUN" "$outcome" "$ec" \
        "$WRAPPER_PHASE" "${HOSTNAME:-unknown}" "$WRAPPER_STARTED_AT" \
        "$(date --iso-8601=seconds)" "$(( SECONDS - WRAPPER_STARTED_SECONDS ))" \
        "${PIPELINE_BRANCH:-unknown}" "${VALIDATION_FLAG:-}" "$logs" \
        "${WRAPPER_RECENT_STATUS[@]}" <<'PY'
import json
import sys

name, run, outcome, code, phase, host, started, finished, seconds, branch, validation, logs = sys.argv[1:13]
ok = outcome == "completed"
duration = int(seconds)
facts = [
    ("Run", run), ("Host", host), ("Pipeline branch/tag", branch),
    ("Mode", f"Validation ({validation})" if validation else "Routine"),
    ("Started", started), ("Finished", finished),
    ("Duration", f"{duration // 3600}h {duration % 3600 // 60}m {duration % 60}s"),
    ("Stage", phase), ("Exit code", code),
]
summary = (
    "The wrapper script completed successfully, including required result and log uploads and cleanup."
    if ok else
    f"The wrapper script {outcome} during {phase} (exit code {code}). Check the retained server logs for details."
)
body = [
    {"type": "TextBlock", "text": f"{'✅' if ok else '❌'} {name} — {run}: {outcome}",
     "weight": "Bolder", "size": "Medium", "color": "Good" if ok else "Attention", "wrap": True},
    {"type": "TextBlock", "text": summary, "wrap": True},
    {"type": "FactSet", "facts": [{"title": title, "value": value[:500]} for title, value in facts]},
    {"type": "TextBlock", "text": logs[:2000], "wrap": True},
]
if sys.argv[13:]:
    body.append({"type": "TextBlock", "text": "Recent wrapper status", "weight": "Bolder"})
    body.extend({"type": "TextBlock", "text": line[:1000], "wrap": True} for line in sys.argv[13:])
print(json.dumps({
    "type": "message",
    "attachments": [{
        "contentType": "application/vnd.microsoft.card.adaptive",
        "content": {"$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard", "version": "1.4", "body": body},
    }],
}, ensure_ascii=False))
PY
    ) || { printf 'Teams notification skipped: could not build the message.\n'; return 0; }
    # Keep the URL out of process arguments. Ignore .curlrc, bound delivery time,
    # and do not retry (a lost response could otherwise cause duplicate posts).
    http=$(printf 'url = "%s"\n' "$webhook_url" | curl --disable --config - \
        --silent --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 5 --max-time 15 --proto '=https' \
        -H 'Content-Type: application/json' --data-binary "$payload" 2>/dev/null) || curl_ec=$?
    if (( curl_ec == 0 )) && [[ "$http" =~ ^2[0-9][0-9]$ ]]; then
        printf 'Teams notification accepted (HTTP %s).\n' "$http"
    else
        printf 'WARNING: Teams notification failed (curl exit %s, HTTP %s); wrapper exit code remains %s.\n' \
            "$curl_ec" "${http:-unknown}" "$ec"
    fi
}

wrapper_logs_exit() {
    local ec="$1" step_ec
    trap - EXIT ERR
    set +e
    if (( ec == 0 && WRAPPER_RUN_COMPLETE == 1 )); then
        wrapper_logs_status 'Processing completed successfully; preparing final log archive.' || ec=$?
    elif (( ec != 0 )); then
        wrapper_logs_status "Script exited with error code $ec; retaining local logs." || true
    else
        wrapper_logs_status 'Wrapper exited before archive preparation; retaining local logs.' || true
    fi
    wrapper_logs_stop_stream
    step_ec=$?
    if (( step_ec != 0 )); then
        (( ec != 0 )) || ec=$step_ec
        WRAPPER_PHASE="Console log finalization"
        wrapper_logs_status "Console log writer failed (exit code $step_ec); retaining local logs." || true
    fi
    if (( ec == 0 && WRAPPER_RUN_COMPLETE == 1 )); then
        wrapper_logs_finalize
        ec=$?
        if (( ec != 0 )); then
            wrapper_logs_status "Log archival/cleanup failed (exit code $ec); local logs retained where possible." || true
        fi
    fi
    wrapper_teams_notify "$ec" || true
    exit "$ec"
}
