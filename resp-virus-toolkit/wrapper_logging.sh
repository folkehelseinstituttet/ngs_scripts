#!/usr/bin/env bash
# Shared lifecycle for the fluseq, rsvseq and sarsseq wrappers. Source this file,
# call wrapper_logs_init after parsing arguments (before setup), and call
# wrapper_logs_complete only after all required processing/uploads succeed.
# Always use explicit return statuses: a bare return inside an EXIT trap can
# inherit the pre-trap status instead of the command failure being handled.

wrapper_logs_status() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
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
    printf 'Console log: %s\nStatus: %s\nNextflow log: %s\n' "$WRAPPER_LOG" "$STATUS_FILE" "$NEXTFLOW_LOG"
}

# Call immediately before Nextflow run so Seqera manifests are resolved against
# the actual launch directory, including on retries.
wrapper_logs_nextflow_start() {
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
    wrapper_logs_collect || return "$?"
    # Offline runs keep their output, logs and intermediates locally.
    wrapper_logs_archive 0 || return "$?"
    [[ -n "$WRAPPER_LOG_REMOTE_BASE" ]] || return 0
    wrapper_logs_status 'Initial log archive verified; starting run cleanup.' || return "$?"
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
    wrapper_logs_collect || return "$?"
    wrapper_logs_archive 1 || return "$?"
    if [[ "$WRAPPER_REMOVE_OUTPUT" == 1 ]]; then
        # The final snapshot temporarily recreated output/logs. Remove the now
        # empty output directory without touching anything added concurrently.
        rmdir -- "$output" 2>/dev/null || true
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
        wrapper_logs_status "Console log writer failed (exit code $step_ec); retaining local logs." || true
    fi
    if (( ec == 0 && WRAPPER_RUN_COMPLETE == 1 )); then
        wrapper_logs_finalize
        ec=$?
        if (( ec != 0 )); then
            wrapper_logs_status "Log archival/cleanup failed (exit code $ec); local logs retained where possible." || true
        fi
    fi
    exit "$ec"
}
