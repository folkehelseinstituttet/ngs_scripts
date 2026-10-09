#!/usr/bin/env bash

# Error/history log file (default before args are parsed)
LOGFILE="/home/ngs/esv_unknown_wrapper_error.log"

# Provide a conservative default STATUS_FILE early so very early failures still write somewhere.
# This will be overwritten with the run-specific file after argument parsing.
STATUS_FILE="$HOME/esv_unknown_status.txt"

# Small helper to write status; the log files will be updated after args are parsed.
# Writes to LOGFILE (append), wrapper log (append) and updates STATUS_FILE atomically.
set_status() {
    msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    # history
    echo "$msg" >> "$LOGFILE"
    # also write to the main wrapper log for completeness
    echo "$msg" >> "${WRAPPER_LOG:-/home/ngs/esv_unknown_wrapper.log}"
    # atomic write of the single-line status file if it's defined
    if [ -n "${STATUS_FILE:-}" ]; then
        tmp="${STATUS_FILE}.tmp"
        if printf '%s\n' "$msg" > "$tmp"; then
            mv "$tmp" "$STATUS_FILE" || echo "[$(date)] Failed to mv $tmp to $STATUS_FILE" >> "$LOGFILE"
        else
            echo "[$(date)] Failed to write status to $tmp" >> "$LOGFILE"
        fi
    fi
}

# --- Log clean-up ----------------------------------------------------------
# After a verified upload the log files are on the N: drive with the results,
# so remove them from the server. Called from the EXIT trap, after the final
# status line, so nothing recreates them. If the run fails they are kept.
LOGS_UPLOADED=0
# Extra text for the final status line on failure (e.g. how to retry an upload)
EXIT_HINT=""

delete_run_logs() {
    rm -f "$LOGFILE" "$STATUS_FILE" "$WRAPPER_LOG" "$NEXTFLOW_LOG" "$NEXTFLOW_LOG".[0-9]*
}

# Trap for detailed error info: line number and command
trap 'set_status "Error at line $LINENO: \"$BASH_COMMAND\" exited with status $?"' ERR

# Trap for termination signals so we update the status file on graceful termination
trap 'set_status "Received SIGTERM - terminating"; exit 143' SIGTERM
trap 'set_status "Received SIGHUP - terminating"; exit 129' SIGHUP

# Trap for any script exits (success or failure)
trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    set_status "Script exited with error code $ec${EXIT_HINT:+. $EXIT_HINT}"
    echo "Script exited with error code $ec" >&2
    echo "Did you remember to change \"RUN_NAME\"?" >&2
  else
    set_status "Script completed successfully."
    echo "Script completed successfully."
  fi
  if [ $ec -eq 0 ] && [ "$LOGS_UPLOADED" = 1 ]; then delete_run_logs || true; fi' EXIT


# --- 1. INITIALIZATION & ARGUMENTS ---


SCRIPT_NAME=$(basename "$0")

# DB aliases must match profile names in nextflow.config (profiles block).
VALID_DB_ALIASES=("v3_2_4" "HEV")

# Host aliases must match host_<alias> profile names in nextflow.config.
VALID_HOST_ALIASES=("human" "moose")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g. NGS_SEQ-20260210-01)"
    echo "  -a, --agens       Specify agens subfolder on the N-drive (e.g. UkjentVirus)"
    echo "  -y, --year        Specify the year (e.g. 2026)"
    echo "  -d, --db          EsViritu database alias (default: v3_2_4)"
    echo "                    Available: ${VALID_DB_ALIASES[*]}"
    echo "  -H, --host        Host reference alias (default: human)"
    echo "                    Available: ${VALID_HOST_ALIASES[*]}"
    echo "      --resume      Resume a previous Nextflow run (passes -resume to nextflow)
      --sensitive-filter  Use high-sensitivity host filtering (slower; unpaired --very-sensitive-local)
      --upload-only Only upload the results of a finished run whose upload failed
                    (skips download and pipeline; needs the same -r/-a/-y)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""
DB="v3_2_4"
HOST="human"
RESUME=false
SENSITIVE_FILTER=false
UPLOAD_ONLY=false

# Pre-scan for --resume and --db (getopts only handles short options)
filtered_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resume)
            RESUME=true
            shift
            ;;
        --sensitive-filter)
            SENSITIVE_FILTER=true
            shift
            ;;
        --upload-only)
            UPLOAD_ONLY=true
            shift
            ;;
        --db)
            DB="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        *)
            filtered_args+=("$1")
            shift
            ;;
    esac
done
set -- "${filtered_args[@]}"

while getopts "hr:a:y:d:H:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        H) HOST="$OPTARG" ;;
        ?) usage ;;
    esac
done

if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

# Validate DB alias against known profiles
if [[ ! " ${VALID_DB_ALIASES[*]} " =~ " ${DB} " ]]; then
    echo "Error: Unknown database alias '${DB}'."
    echo "Available aliases: ${VALID_DB_ALIASES[*]}"
    echo "Add a corresponding 'db_${DB}' profile block to nextflow.config to register a new alias."
    exit 1
fi

# Validate HOST alias against known profiles
if [[ ! " ${VALID_HOST_ALIASES[*]} " =~ " ${HOST} " ]]; then
    echo "Error: Unknown host alias '${HOST}'."
    echo "Available aliases: ${VALID_HOST_ALIASES[*]}"
    echo "Add a corresponding 'host_${HOST}' profile block to nextflow.config to register a new alias."
    exit 1
fi

# Now that arguments are parsed, set run-specific log files and initialize them.
# All of them are copied to the N: drive with the results and deleted from the
# server when the upload has been verified. If the run fails they are kept.
LOG_PREFIX="/home/ngs/esv_${RUN:-unknown}"
LOGFILE="${LOG_PREFIX}_wrapper_error.log"
STATUS_FILE="${LOG_PREFIX}_status.txt"
WRAPPER_LOG="${LOG_PREFIX}_wrapper.log"
NEXTFLOW_LOG="${LOG_PREFIX}_nextflow.log"

# Send all stdout/stderr to the wrapper log (and to the console when not detached)
exec > >(tee -a "$WRAPPER_LOG") 2>&1

printf '[%s] Initialized\n' "$(date +'%Y-%m-%d %H:%M:%S')" >> "$STATUS_FILE"
set_status "Started wrapper. RUN=$RUN AGENS=$AGENS YEAR=$YEAR DB=$DB HOST=$HOST RESUME=$RESUME SENSITIVE_FILTER=$SENSITIVE_FILTER UPLOAD_ONLY=$UPLOAD_ONLY"

# Set working directory
cd $HOME

# --- 2. ENVIRONMENT CONFIGURATION ---

# Set up paths
# TMP_DIR will hold the raw fastq files and results
TMP_DIR=/mnt/tempdata/fastq_esv/raw/${RUN}
TMP_RES=/mnt/tempdata/fastq_esv/analysis/${RUN}
#MAKE SURE CSV FILE PATH IS PARSED CORRECTLY
TMP_SAMPLESHEET_DIR=/mnt/tempdata/fastq_esv/data/samplesheets/

# SMB Credentials and remote Paths
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
# Results are uploaded into a per-run subfolder under the agens results tree.
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/${YEAR}/${RUN}
# Samplesheets live in a single shared folder (no year/run subfolder).
SMB_SAMPLESHEET_REMOTE=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/samplesheets

# Local mount prefix for the N-drive SMB share.
# fastq_dir paths in the samplesheet start with this prefix; it is stripped
# to derive the SMB-relative path for smbclient.
SMB_MOUNT_PREFIX="/mnt/N/"

# --- UPLOAD & CLEAN-UP HELPERS (used by section 6 and --upload-only) ---

# Activate the conda environment that holds Nextflow
# Temporarily disable set -u because the JAVA_HOME variable is unset
activate_nextflow() {
    set +u
    source ~/miniconda3/etc/profile.d/conda.sh
    conda activate NEXTFLOW
    set -u
    set_status "Activated NEXTFLOW conda environment"
}

# Copy the run's log files into the results so they are uploaded with them.
# Rotated Nextflow logs (.1, .2, ...) come from earlier attempts of the same run.
copy_logs() {
    mkdir -p "$TMP_RES/logs"
    for f in "$WRAPPER_LOG" "$LOGFILE" "$STATUS_FILE" "$NEXTFLOW_LOG" "$NEXTFLOW_LOG".[0-9]*; do
        if [ -f "$f" ]; then
            cp "$f" "$TMP_RES/logs/"
        fi
    done
}

# Stop without deleting anything: results, FASTQs, work directory and logs are
# kept, so the upload can be retried with --upload-only (or the run resumed).
upload_failed() {
    EXIT_HINT="Upload failed; results kept in $TMP_RES. Retry with: $SCRIPT_NAME -r $RUN -a $AGENS -y $YEAR --upload-only"
    set_status "Error: upload to N: drive failed ($1). $EXIT_HINT"
    exit 1
}

# Compare the number of files and total bytes in $TMP_RES with a recursive
# listing of the remote run folder. smbclient file lines end with
# "<attributes> <size> <weekday> <month> <day> <hh:mm:ss> <year>";
# directories have a D in the attributes and are skipped.
verify_upload() {
    local local_stats remote_stats
    local_stats=$(find "$TMP_RES" -type f -printf '%s\n' | awk '{ n++; b += $1 } END { printf "%d files, %.0f bytes", n, b }')
    remote_stats=$(smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" -c "recurse ON; ls" 2>/dev/null | awk '
        NF >= 7 && $NF ~ /^[0-9][0-9][0-9][0-9]$/ && $(NF-1) ~ /^[0-9]+:[0-9][0-9]:[0-9][0-9]$/ &&
        $(NF-5) ~ /^[0-9]+$/ && $(NF-6) ~ /^[A-Z]+$/ && $(NF-6) !~ /D/ { n++; b += $(NF-5) }
        END { printf "%d files, %.0f bytes", n, b }') || return 1
    echo "Upload check: local ${local_stats}; N: drive ${remote_stats}"
    [ "$local_stats" = "$remote_stats" ]
}

# Upload the contents of $TMP_RES into the run folder on the N: drive and
# verify it. Exits via upload_failed on any problem.
upload_results() {
    set_status "Uploading results and log files to the N: drive: $SMB_DIR"

    # Create the remote run folder. mkdir fails if it already exists (e.g. on
    # an --upload-only retry), so check that the folder is there afterwards.
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "${SMB_DIR%/*}" -c "mkdir ${RUN}" >/dev/null 2>&1 || true
    if ! smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" -c "ls" >/dev/null 2>&1; then
        upload_failed "remote folder $SMB_DIR not found and could not be created"
    fi

    # mput overwrites, so a retry completes a partial earlier upload.
    if ! smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $TMP_RES
mput *
EOF
    then
        upload_failed "smbclient exited with an error"
    fi

    if ! verify_upload; then
        upload_failed "files on the N: drive do not match $TMP_RES"
    fi

    LOGS_UPLOADED=1
    set_status "Results and log files copied to N: drive"
}

# Remove local copies and this run's Nextflow work directories. Only called
# after a verified upload. The run name is read from this run's Nextflow log;
# a bare 'nextflow clean' would clean whichever run was launched last.
clean_up() {
    echo "Cleaning up local files..."
    rm -rf "$TMP_DIR" "$TMP_RES"

    local nf_run_name
    nf_run_name=$(sed -n 's/.*CmdRun - Launching `[^`]*` \[\([^]]*\)\].*/\1/p' "$NEXTFLOW_LOG" 2>/dev/null | tail -n 1)
    if [ -n "$nf_run_name" ]; then
        set_status "Cleaning Nextflow work directories of run $nf_run_name"
        nextflow clean -f "$nf_run_name" || set_status "Warning: nextflow clean failed for run $nf_run_name"
    else
        set_status "Warning: Nextflow run name not found in $NEXTFLOW_LOG; work directories not cleaned"
    fi
}

# --upload-only: the pipeline has already finished but the upload failed.
if $UPLOAD_ONLY; then
    if [ ! -d "$TMP_RES" ] || [ -z "$(ls -A "$TMP_RES")" ]; then
        set_status "Error: --upload-only but no results found in $TMP_RES"
        exit 1
    fi
    activate_nextflow
    copy_logs
    upload_results
    clean_up
    echo "Done."
    exit 0
fi

# Create directories
mkdir -p "$TMP_RES"
mkdir -p "$TMP_DIR"
mkdir -p "$TMP_SAMPLESHEET_DIR"

# --- 3. DOWNLOAD SAMPLESHEET & FASTQ FILES ---

# Step 3a: Download the samplesheet from the N-drive.
# Format: sample;fastq_dir  (semicolon-delimited, UTF-8 or Windows BOM)
echo "Downloading samplesheet: ${RUN}_samplesheet.csv"
if ! smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SAMPLESHEET_REMOTE" -c "ls" >/dev/null 2>&1; then
    set_status "Error: Samplesheet remote path not found: $SMB_SAMPLESHEET_REMOTE"
    echo "Error: Cannot reach samplesheet folder on N-drive: $SMB_SAMPLESHEET_REMOTE"
    exit 1
fi

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SAMPLESHEET_REMOTE" <<EOF
prompt OFF
lcd $TMP_SAMPLESHEET_DIR
get ${RUN}_samplesheet.csv
EOF

RAW_SAMPLESHEET="${TMP_SAMPLESHEET_DIR}/${RUN}_samplesheet.csv"

if [ ! -f "$RAW_SAMPLESHEET" ]; then
    set_status "Error: Samplesheet not found after download: $RAW_SAMPLESHEET"
    exit 1
fi

# Remove BOM (Byte Order Mark) if present (common in Windows-created CSV files)
sed -i '1s/^\xEF\xBB\xBF//' "$RAW_SAMPLESHEET"

# Step 3b: Download FASTQs for each sample listed in the samplesheet.
# The samplesheet fastq_dir column holds the absolute path on the local N-drive mount
# (e.g. /mnt/N/Virologi/NGS/.../SampleA). Strip the mount prefix to get the
# SMB-relative path, then download each sample directory individually.
echo "Downloading per-sample FASTQ directories..."

while IFS=';' read -r sample fastq_dir; do
    # Strip Windows carriage returns
    sample="${sample%$'\r'}"
    fastq_dir="${fastq_dir%$'\r'}"

    # Skip header and empty lines
    [[ "$sample" == "sample" ]] && continue
    [[ -z "$sample" ]] && continue

    # Derive SMB-relative path by stripping the local mount prefix
    if [[ "$fastq_dir" != "${SMB_MOUNT_PREFIX}"* ]]; then
        echo "Error: fastq_dir '$fastq_dir' does not start with '$SMB_MOUNT_PREFIX'"
        echo "Check that the samplesheet was created on the server with absolute /mnt/N/ paths."
        exit 1
    fi
    smb_sample_path="${fastq_dir#${SMB_MOUNT_PREFIX}}"

    echo "  Sample: $sample  ->  $smb_sample_path"

    # Verify the remote directory exists before attempting download
    if ! smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$smb_sample_path" -c "ls" >/dev/null 2>&1; then
        set_status "Error: Remote sample directory not found: $smb_sample_path"
        echo "Error: Cannot reach sample directory on N-drive: $smb_sample_path"
        exit 1
    fi

    mkdir -p "${TMP_DIR}/${sample}"
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$smb_sample_path" <<EOF
prompt OFF
recurse ON
lcd ${TMP_DIR}/${sample}
mget *
EOF

    set_status "Downloaded sample: $sample"
done < <(tail -n +2 "$RAW_SAMPLESHEET")

echo "All samples downloaded."

# --- 4. BUILD NEXTFLOW SAMPLESHEET ---

# The N-drive samplesheet has format: sample;fastq_dir
# Replace each fastq_dir with the local path where the sample was just downloaded.
FINAL_SAMPLESHEET="${TMP_SAMPLESHEET_DIR}/${RUN}_samplesheet_filled.csv"

echo "Building Nextflow samplesheet..."
echo "  Input:    $RAW_SAMPLESHEET"
echo "  Output:   $FINAL_SAMPLESHEET"
echo "  FASTQ base: $TMP_DIR"

awk -F';' -v OFS=';' -v base="$TMP_DIR" '
function trim(s) { gsub(/^[[:space:]\r]+|[[:space:]\r]+$/, "", s); return s }
NR == 1 { print "sample;fastq_dir"; next }
$0 ~ /^[[:space:]]*$/ { next }
{
    sid = trim($1)
    if (sid == "") { next }
    if (sid ~ / /) {
        print "ERROR: sample ID \"" sid "\" contains spaces at line " NR > "/dev/stderr"
        exit 1
    }
    print sid ";" base "/" sid
}
' "$RAW_SAMPLESHEET" > "$FINAL_SAMPLESHEET"

if [ $? -ne 0 ]; then
    echo "Error: Failed to build Nextflow samplesheet."
    exit 1
fi

echo "Samplesheet created: $FINAL_SAMPLESHEET"


# --- 5. RUN PIPELINE ---

activate_nextflow

# 1. Set the version (switch back to 'main' once development is complete and merged)
VERSION="Assembly_v2"

# 2. Tell Nextflow to refresh the code from GitHub
nextflow pull alexanderhes/Ukjent_virus -r $VERSION || {
    set_status "Error: Nextflow pull failed"
    exit 1
}

# 3. Build the custom Docker image from the Dockerfile in the pulled repo.
#    This adds the dataui R package (required for EsViritu coverage sparklines).
#    The Nextflow assets cache is always at ~/.nextflow/assets/<handle>.
PIPELINE_ASSETS="$HOME/.nextflow/assets/alexanderhes/Ukjent_virus"
set_status "Building Docker image from ${PIPELINE_ASSETS}/docker/"
docker build -t esviritu_pipeline:latest "${PIPELINE_ASSETS}/docker/" || {
    set_status "Error: Docker build failed"
    exit 1
}
set_status "Docker image built successfully"

# 4. Run it directly from the GitHub handle
# host_index is resolved from the 'host_<alias>' profile selected via -H.
# esviritu_db is resolved from the 'db_<alias>' profile selected via -d.
RESUME_FLAG=""
$RESUME && RESUME_FLAG="-resume"

SENSITIVE_FILTER_FLAG=""
$SENSITIVE_FILTER && SENSITIVE_FILTER_FLAG="--sensitive_host_filter true"

set_status "Using database profile: db_${DB}"
set_status "Using host profile: host_${HOST}"

set_status "Starting Nextflow run. Nextflow log: $NEXTFLOW_LOG"
nextflow -log "$NEXTFLOW_LOG" run alexanderhes/Ukjent_virus -r $VERSION \
    $RESUME_FLAG \
    $SENSITIVE_FILTER_FLAG \
    -profile "server,host_${HOST},db_${DB}" \
    --validate \
    --samplesheet "$FINAL_SAMPLESHEET" \
    --outdir "$TMP_RES" || {
    set_status "Error: Nextflow pipeline execution failed"
    exit 1
}


# --- 6. UPLOAD RESULTS AND CLEAN UP ---

# Nothing is deleted unless the upload has been verified (see upload_results).
copy_logs
upload_results
clean_up

echo "Done."
