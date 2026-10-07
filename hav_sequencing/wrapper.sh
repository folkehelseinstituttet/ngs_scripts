#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variables, and pipefail

# --- Console channel -------------------------------------------------------
# Progress messages should be visible to a human, not just buried in the logs.
# They go to stdout, which the "exec | tee" below sends to the main wrapper log
# *and* to this script's own terminal. Under "screen" that terminal is the
# screen window, so the messages are live while attached and still sitting in
# the scrollback when you reattach later with "screen -r hcv".
#
# That alone is not enough for a fully detached launch
# ("screen -dmS hcv wrapper.sh ..."), because screen gives the script a brand
# new pty: nothing reaches the terminal the user actually typed in. Export
# CONSOLE_TTY at launch to mirror the messages there too, so the user gets
# immediate confirmation that the run really started before they log out:
#
#   CONSOLE_TTY=$(tty) screen -dmS hcv ~/ngs_scripts/hcv_illumina/wrapper.sh -r RUN -a HCV -y 2026
#
# After logout that pty is destroyed and the mirror silently stops; the run
# keeps going and the log files remain the durable record.

# History log file (default before args are parsed)
export LOGFILE="/home/ngs/hav_sequencing_wrapper.log"
export ERRORLOG="/home/ngs/hav_sequencing_wrapper.error.log"

exec > >(tee -a "$LOGFILE") \
     2> >(tee -a "$LOGFILE" >> "$ERRORLOG")

# Small helper to write status; STATUS_FILE will be updated after args are parsed.
# Writes to LOGFILE (append), wrapper log (append) and updates STATUS_FILE atomically.
set_status() {
    msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    # history
    echo "$msg" >> "$LOGFILE"
    # Append status line to STATUS_FILE if it's defined
    if [ -n "${STATUS_FILE:-}" ]; then
        if ! printf '%s\n' "$msg" >> "$STATUS_FILE"; then
            echo "[$(date)] Failed to append status to $STATUS_FILE" >> "$LOGFILE"
        fi
    fi
    
}


# ── Argument parsing ──────────────────────────────────────────────────────────
MODE=""
BATCH_NAME=""
YEAR=""

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:?--mode requires a value (sanger or wgs)}"
      shift 2 ;;
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
    echo "Usage: $0 --mode <mode> --batch-name <batch_name> --year <year>"
    exit 1
fi

echo Mode: "$MODE"
echo Batch name: "$BATCH_NAME"
echo Year: "$YEAR"

export MODE="$MODE"
export BATCH_NAME="$BATCH_NAME"
export YEAR="$YEAR"


# ── Resolve paths ─────────────────────────────────────────────────────────────
export BASE_DIR=/mnt/tempdata/
export TMP_DIR=/mnt/tempdata/hav_input # Fasta, lokal database
export SMB_AUTH=/home/ngs/.smbcreds
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
HAV_DB_DIR="$HOME/hav_database"
mkdir -p "$HAV_DB_DIR"
export HAV_DB_DIR="$HAV_DB_DIR"


echo "Temporary directory: $TMP_DIR"

# Create directory to hold the output of the analysis
# Ensure $HOME/$BATCH_NAME exists and is clean
if [ -d "$HOME/$BATCH_NAME" ]; then
    rm -rf "$HOME/$BATCH_NAME"
fi
mkdir -p "$HOME/${BATCH_NAME}_results"
echo "Output directory: $HOME/${BATCH_NAME}_results"
export OUT_BASE="$HOME/${BATCH_NAME}_results"

# Make sure the latest version of the ngs_scripts repo is present locally
export REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

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
# Check if the directory exists
export HAV_SEQ_REPO="$HOME/hav_seq"
export HAV_SEQ_REPO_URL="https://github.com/folkehelseinstituttet/hav_seq.git"

if [ -d "$HAV_SEQ_REPO" ]; then
    echo "Directory 'hav_seq' exists. Pulling latest changes..."
    cd "$HAV_SEQ_REPO"
    git pull
else
    echo "Directory 'hav_seq' does not exist. Cloning repository..."
    git clone "$HAV_SEQ_REPO_URL" "$HAV_SEQ_REPO"
fi


set_status "Copying fasta files from the N drive (SMB_DIR=$SMB_DIR/Fasta)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR/Fasta" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR/Fasta
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
lcd $TMP_DIR
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
lcd $TMP_DIR
mget Requests.xlsx
EOF
set_status "Requests-meta copy complete. Files are in $TMP_DIR"


set_status "Copying database file from the N drive (SMB_DIR=$SMB_DIR_DATASET)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_DATASET" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR/local_dataset
mget 2PA.fa
EOF
set_status "Database copy complete. File is in $TMP_DIR/local_dataset" 



# Run the HAV sequencing wrapper script with the specified arguments
bash ~/hav_seq/scripts/hav_wrapper.sh --mode "$MODE" "$BATCH_NAME" "$YEAR"


## Move the results to the N: drive
set_status "Moving results to the N: drive"
mkdir -p $HOME/out_hav
cp -r "$HOME/${BATCH_NAME}_results"/ $HOME/out_hav/

smbclient $SMB_HOST -A $SMB_AUTH -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $HOME/out_hav/
mput *
EOF

set_status "Results copied to N: drive"


## Move the updated database to the N: drive
set_status "Moving updated database to the N: drive"
mkdir -p $HOME/out_hav_database
cp -r "$HAV_DB_DIR"/* $HOME/out_hav_database/

smbclient $SMB_HOST -A $SMB_AUTH -D "$SMB_DIR_DATASET" <<EOF
prompt OFF
recurse ON
lcd $HOME/out_hav_database/
mput *
EOF

set_status "Updated database copied to N: drive"


## Clean up
rm -rf $HOME/out_hav
rm -rf $HOME/out_hav_database
rm -rf $HOME/hav_database
rm -rf $HOME/${BATCH_NAME}_results
rm -rf $TMP_DIR

set_status "Cleanup complete"

# End of script