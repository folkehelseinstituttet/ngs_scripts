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

echo "Temporary directory: $TMP_DIR"

# Create directory to hold the output of the analysis
# Ensure $HOME/$BATCH_NAME exists and is clean
if [ -d "$HOME/$BATCH_NAME" ]; then
    rm -rf "$HOME/$BATCH_NAME"
fi
mkdir -p "$HOME/$BATCH_NAME"
echo "Output directory: $HOME/$BATCH_NAME"

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

set_status "Copying HAV_lw_uttrekk.tsv from the N drive (SMB_DIR=$SMB_DIR_METADATA)"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_METADATA" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget HAV_lw_uttrekk.tsv
EOF
set_status "Metadata copy complete. File is in $TMP_DIR/HAV_lw_uttrekk.tsv"

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

# Sette opp variabler
# Sjekke evt. filer tilstede
# Starte en log-fil
# Skrive beskjeder til log-fil + skjerm

# Kopiere filer fra N: (manuelf flytte metadata.tsv)
# - metadata.tsv
# - fasta (Sanger)
# - Lokal database
# Kopiere metadata.tsv fra V: (venter på tilgang)

# Synce hav_seq til nyeste versjon
#git pull -C /home/ngs/folkehelseinstituttet/hav_seq/
# Kjøre scriptet - "sub-wrapper" fra /home/ngs/folkehelseinstituttet/hav_seq/

# Flytte resultater tilbake til N: