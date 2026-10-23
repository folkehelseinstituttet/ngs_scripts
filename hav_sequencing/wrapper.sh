#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variables, and pipefail

usage() {
    echo "Usage: $0 [--local] [--test] --mode <sanger|wgs> <batch_name> <year>"
    echo "  --local   Run locally instead of on the server (default: server)"
    echo "  --test    Do not modify the database (2PA.fa) on the N drive; write 2PA_test_<date_time>.fa instead"
}

# ── Environment selection (server is default) ────────────────────────────────
# BASE_DIR: temporary/input data. OUT_BASE: home-like base for repos, logs, results.
ENVIRONMENT="server"
for arg in "$@"; do
    [[ "$arg" == "--local" ]] && ENVIRONMENT="local"
done

if [[ "$ENVIRONMENT" == "local" ]]; then
    export OUT_BASE="$HOME/ngs_local"
    export BASE_DIR="$OUT_BASE"
else
    export BASE_DIR="/mnt/tempdata"
    export OUT_BASE="/home/ngs"
fi
mkdir -p "$OUT_BASE" "$BASE_DIR"

# Run-specific log files are set up after the arguments are parsed (see below).
# They are copied to the N: drive with the results and deleted from the server
# when the run succeeds. If the run fails they are kept for debugging.
LOGS_UPLOADED=0

# Small helper to write status lines. stdout goes through tee to LOGFILE and the terminal.
set_status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

delete_run_logs() {
    rm -f "$LOGFILE" "$ERRORLOG"
}

# On exit: report status and, after a successful upload, remove the logs from the server.
trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    echo "Script exited with error code $ec. Details are in ${LOGFILE:-<not set>}" >&2
  elif [ "$LOGS_UPLOADED" = 1 ]; then
    delete_run_logs || true
  fi' EXIT


# ── Argument parsing ──────────────────────────────────────────────────────────
MODE=""
BATCH_NAME=""
YEAR=""

POSITIONAL=()
TEST_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:?--mode requires a value (sanger or wgs)}"
      shift 2 ;;
    --local)
      shift ;;
    --test)
      TEST_MODE=1; shift ;;
    --help)
      usage; exit 0 ;;
     -*)
      echo "ERROR: Unknown option: $1" >&2; usage; exit 1 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 ]] && BATCH_NAME="${POSITIONAL[0]}"
[[ ${#POSITIONAL[@]} -ge 2 ]] && YEAR="${POSITIONAL[1]}"

if [[ -z "$MODE" || -z "$BATCH_NAME" || -z "$YEAR" ]]; then
    usage
    exit 1
fi

# Run-specific log files (also used by hav_wrapper.sh via the environment)
export LOGFILE="$OUT_BASE/hav_sequencing_${BATCH_NAME}_wrapper.log"
export ERRORLOG="$OUT_BASE/hav_sequencing_${BATCH_NAME}_wrapper.error.log"

exec > >(tee -a "$LOGFILE") \
     2> >(tee -a "$LOGFILE" "$ERRORLOG" >&2)

echo Environment: "$ENVIRONMENT"
echo Mode: "$MODE"
echo Batch name: "$BATCH_NAME"
echo Year: "$YEAR"

export MODE="$MODE"
export BATCH_NAME="$BATCH_NAME"
export YEAR="$YEAR"


# ── Resolve paths ─────────────────────────────────────────────────────────────
export TMP_DIR="$BASE_DIR/hav_input" # Fasta, lokal database
export SMB_AUTH="$OUT_BASE/.smbcreds"
export SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
export SMB_DIR="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/${YEAR}/${BATCH_NAME}"
export SMB_DIR_DATASET="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Databaser/"
export SMB_DIR_METADATA="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Databaser/Metadata"
export SMB_DIR_METAREQUEST="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Requests"

echo "SMB_DIR: $SMB_DIR"
echo "SMB_DIR_DATASET: $SMB_DIR_DATASET"

# Ensure $TMP_DIR exists and is clean
if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"
mkdir -p "$TMP_DIR/Fasta"
mkdir -p "$TMP_DIR/local_dataset"

# Opprett mappe for ny database
HAV_DB_DIR="$OUT_BASE/hav_database"
mkdir -p "$HAV_DB_DIR"
export HAV_DB_DIR="$HAV_DB_DIR"


echo "Temporary directory: $TMP_DIR"

# Create directory to hold the output of the analysis
# Ensure $OUT_BASE/$BATCH_NAME exists and is clean
if [ -d "$OUT_BASE/$BATCH_NAME" ]; then
    rm -rf "$OUT_BASE/$BATCH_NAME"
fi
export RESULTS_DIR="$OUT_BASE/${BATCH_NAME}_results"
mkdir -p "$RESULTS_DIR"
echo "Output directory: $RESULTS_DIR"

# Make sure the latest version of the ngs_scripts repo is present locally
export REPO="$OUT_BASE/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

# Scripts used by --local are read directly from the Windows project folder
LOCAL_SCRIPTS_DIR="/mnt/c/Users/kain/OneDrive - Folkehelseinstituttet/Prosjekter"

# HAV_SEQ_REPO can be overridden from the environment (useful for --local)
if [[ "$ENVIRONMENT" == "local" ]]; then
    export REPO="$LOCAL_SCRIPTS_DIR/ngs_scripts"
    export HAV_SEQ_REPO="${HAV_SEQ_REPO:-$LOCAL_SCRIPTS_DIR/hav_seq}"
else
    export HAV_SEQ_REPO="${HAV_SEQ_REPO:-$OUT_BASE/hav_seq}"
fi
export HAV_SEQ_REPO_URL="https://github.com/folkehelseinstituttet/hav_seq.git"

if [[ "$ENVIRONMENT" == "local" ]]; then
    set_status "Local mode: skipping pull/clone of ngs_scripts and hav_seq"
    if [ ! -d "$HAV_SEQ_REPO" ]; then
        echo "ERROR: hav_seq not found at $HAV_SEQ_REPO. Set HAV_SEQ_REPO to your local copy." >&2
        exit 1
    fi
else
    set_status "Ensuring local copy of ngs_scripts (pull/clone)"
    # Check if the directory exists
    if [ -d "$REPO" ]; then
        echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
        cd "$REPO"
        git pull
    else
        echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
        git clone "$REPO_URL" "$REPO"
    fi

    set_status "Ensuring local copy of hav_seq (pull/clone)"
    if [ -d "$HAV_SEQ_REPO" ]; then
        echo "Directory 'hav_seq' exists. Pulling latest changes..."
        cd "$HAV_SEQ_REPO"
        git pull
    else
        echo "Directory 'hav_seq' does not exist. Cloning repository..."
        git clone "$HAV_SEQ_REPO_URL" "$HAV_SEQ_REPO"
    fi
fi


set_status "Copying fasta files from the N drive (SMB_DIR=$SMB_DIR/Fasta)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR/Fasta" <<EOF
prompt OFF
recurse ON
lcd "$TMP_DIR/Fasta"
mget *
EOF
set_status "Fasta copy complete. Files are in $TMP_DIR/Fasta"

# ── Verify and copy HAV_lw_uttrekk.tsv ───────────────────────────────────────

LW_FILENAME="HAV_lw_uttrekk.tsv"
LW_FILE="$TMP_DIR/$LW_FILENAME"

set_status "Checking modification date for $LW_FILENAME on the N drive"

# Read metadata from the original file on the SMB share.
LW_INFO=$(
    smbclient "$SMB_HOST" \
        -A "$SMB_AUTH" \
        -D "$SMB_DIR_METADATA" \
        -c "allinfo $LW_FILENAME"
)

# Log the SMB metadata to make future troubleshooting easier.
printf '%s\n' "$LW_INFO"

# allinfo normally reports the modification timestamp as write_time.
WRITE_TIME=$(
    printf '%s\n' "$LW_INFO" |
        sed -n 's/^[[:space:]]*write_time:[[:space:]]*//p' |
        head -n 1
)

if [[ -z "$WRITE_TIME" ]]; then
    echo "ERROR: Could not read write_time for $LW_FILENAME from the N drive." >&2
    echo "Output from smbclient allinfo:" >&2
    printf '%s\n' "$LW_INFO" >&2
    exit 1
fi

# Convert the SMB timestamp to YYYY-MM-DD.
if ! FILE_DATE=$(date -d "$WRITE_TIME" +%F); then
    echo "ERROR: Could not interpret SMB write_time: $WRITE_TIME" >&2
    exit 1
fi

TODAY=$(date +%F)

echo "Original file timestamp: $WRITE_TIME"
echo "File date: $FILE_DATE"
echo "Today's date: $TODAY"

if [[ "$FILE_DATE" != "$TODAY" ]]; then
    echo "ERROR: $LW_FILENAME on the N drive is not from today." >&2
    echo "File date: $FILE_DATE" >&2
    echo "Today's date: $TODAY" >&2
    echo 'Kopier dagens LabWare-uttrekk "HAV_lw_uttrekk.tsv" fra V:\Prod\FromSecure\LW_Datauttrekk til N:\Virologi\Hepatitt\Hepatitt A\HAV genteknologi\Databaser\Metadata' >&2
    exit 1
fi

set_status "Verified that $LW_FILENAME on the N drive is dated today ($TODAY)"

set_status "Copying $LW_FILENAME from the N drive (SMB_DIR=$SMB_DIR_METADATA)"

smbclient "$SMB_HOST" \
    -A "$SMB_AUTH" \
    -D "$SMB_DIR_METADATA" <<EOF
lcd "$TMP_DIR"
get $LW_FILENAME
EOF

if [[ ! -s "$LW_FILE" ]]; then
    echo "ERROR: Metadata file $LW_FILE was not downloaded or is empty." >&2
    exit 1
fi

set_status "Metadata copy complete. File is in $LW_FILE"

set_status "Copying meta-data for requests from the N drive (SMB_DIR=$SMB_DIR_METAREQUEST)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_METAREQUEST" <<EOF
prompt OFF
recurse ON
lcd "$TMP_DIR"
mget Requests.xlsx
EOF
set_status "Requests-meta copy complete. Files are in $TMP_DIR"


set_status "Copying database file from the N drive (SMB_DIR=$SMB_DIR_DATASET)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_DATASET" <<EOF
prompt OFF
recurse ON
lcd "$TMP_DIR/local_dataset"
mget 2PA.fa
EOF
set_status "Database copy complete. File is in $TMP_DIR/local_dataset" 



# Run the HAV sequencing wrapper script with the specified arguments
HAV_WRAPPER_ARGS=(--mode "$MODE")
[[ "$TEST_MODE" -eq 1 ]] && HAV_WRAPPER_ARGS+=(--test)
bash "$HAV_SEQ_REPO/scripts/hav_wrapper.sh" "${HAV_WRAPPER_ARGS[@]}" "$BATCH_NAME" "$YEAR"


## Move the results to the N: drive
set_status "Moving results to the N: drive"

# Include the log files in the upload
mkdir -p "$RESULTS_DIR/logs"
for f in "$LOGFILE" "$ERRORLOG"; do
    if [ -f "$f" ]; then
        cp "$f" "$RESULTS_DIR/logs/"
    fi
done

mkdir -p "$OUT_BASE/out_hav"
cp -r "$RESULTS_DIR"/ "$OUT_BASE/out_hav/"

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd "$OUT_BASE/out_hav/"
mput *
EOF

set_status "Results and log files copied to N: drive"
LOGS_UPLOADED=1


## Move the updated database to the N: drive
set_status "Moving updated database to the N: drive"
mkdir -p "$OUT_BASE/out_hav_database"
cp -r "$HAV_DB_DIR"/* "$OUT_BASE/out_hav_database/"

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_DATASET" <<EOF
prompt OFF
recurse ON
lcd "$OUT_BASE/out_hav_database/"
mput *
EOF

set_status "Updated database copied to N: drive"


## Clean up
rm -rf "$OUT_BASE/out_hav"
rm -rf "$OUT_BASE/out_hav_database"
rm -rf "$HAV_DB_DIR"
rm -rf "$RESULTS_DIR"
rm -rf "$TMP_DIR"

set_status "Cleanup complete"

# End of script