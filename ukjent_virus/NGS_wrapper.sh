#!/usr/bin/env bash

# Send all stdout/stderr to the main wrapper log (and to the console when not detached)
exec > >(tee -a /home/ngs/esv_wrapper.log) 2>&1

# Error/history log file
LOGFILE="/home/ngs/esv_wrapper_error.log"

# Provide a conservative default STATUS_FILE early so very early failures still write somewhere.
# This will be overwritten with the run-specific file after argument parsing.
STATUS_FILE="$HOME/esv_unknown_status.txt"
printf '[%s] Initialized (unknown run)\n' "$(date +'%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"

# Small helper to write status; STATUS_FILE will be updated after args are parsed.
# Writes to LOGFILE (append), wrapper log (append) and updates STATUS_FILE atomically.
set_status() {
    msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    # history
    echo "$msg" >> "$LOGFILE"
    # also write to the main wrapper log for completeness
    echo "$msg" >> /home/ngs/esv_wrapper.log
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

# Trap for detailed error info: line number and command
trap 'set_status "Error at line $LINENO: \"$BASH_COMMAND\" exited with status $?"' ERR

# Trap for termination signals so we update the status file on graceful termination
trap 'set_status "Received SIGTERM - terminating"; exit 143' SIGTERM
trap 'set_status "Received SIGHUP - terminating"; exit 129' SIGHUP

# Trap for any script exits (success or failure)
trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    set_status "Script exited with error code $ec"
    echo "Script exited with error code $ec" >&2
    echo "Did you remember to change \"RUN_NAME\"?" >&2
  else
    set_status "Script completed successfully."
    echo "Script completed successfully."
  fi' EXIT


# --- 1. INITIALIZATION & ARGUMENTS ---


SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g. NGS_SEQ-20260210-01)"
    echo "  -a, --agens       Specify agens subfolder on the N-drive (e.g. UkjentVirus)"
    echo "  -y, --year        Specify the year (e.g. 2026)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""

while getopts "hr:a:y:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        ?) usage ;;
    esac
done

if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

# Now that arguments are parsed, set a run-specific status file and initialize it.
if [ -n "${RUN:-}" ]; then
    STATUS_FILE="$HOME/esv_${RUN}_status.txt"
else
    STATUS_FILE="$HOME/esv_unknown_status.txt"
fi
printf '[%s] Initialized\n' "$(date +'%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
set_status "Started wrapper. RUN=$RUN AGENS=$AGENS YEAR=$YEAR"

# Set working directory
cd $HOME

# --- 2. ENVIRONMENT CONFIGURATION ---

# Set up paths
BASE_DIR=/mnt/tempdata/
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

# Activate the conda environment that holds Nextflow
# Temporarily disable set -u because the JAVA_HOME variable is unset
set +u
source ~/miniconda3/etc/profile.d/conda.sh
conda activate NEXTFLOW
set -u

set_status "Activated NEXTFLOW conda environment"

# 1. Set the version (switch back to 'main' once development is complete and merged)
VERSION="main"

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
# DB/index paths (host_index, esviritu_db) are resolved from the 'server'
# profile in nextflow.config — no need to pass them as CLI flags.
nextflow run alexanderhes/Ukjent_virus -r $VERSION \
    -profile server \
    --validate \
    --samplesheet "$FINAL_SAMPLESHEET" \
    --outdir "$TMP_RES" || {
    set_status "Error: Nextflow pipeline execution failed"
    exit 1
}


# --- 6. UPLOAD RESULTS AND CLEAN UP ---

echo "Moving results to the N: drive"
mkdir -p "$BASE_DIR/move_ESV"

# Move content to staging folder
mv "$TMP_RES/" "$BASE_DIR/move_ESV"

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $BASE_DIR/move_ESV
mput *
EOF

echo "Cleaning up local files..."
rm -rf "$TMP_DIR" "$TMP_RES" "$BASE_DIR/move_ESV"

nextflow clean -f

echo "Done."
