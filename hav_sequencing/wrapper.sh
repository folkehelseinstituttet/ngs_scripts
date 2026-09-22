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
CONSOLE_EXTRA=0
if [ -n "${CONSOLE_TTY:-}" ] && ( : >>"$CONSOLE_TTY" ) 2>/dev/null; then
    exec 3>>"$CONSOLE_TTY"
    CONSOLE_EXTRA=1
fi

console() {
    printf '%s\n' "$*"
    if [ "$CONSOLE_EXTRA" = 1 ]; then
        # Never fail the run if that terminal has gone away (user logged out).
        printf '%s\n' "$*" >&3 2>/dev/null || true
    fi
}

# Send all stdout/stderr to the main wrapper log (and to the console when not detached)
exec > >(tee -a /home/ngs/hav_sequencing_wrapper.log) 2>&1

# Error/history log file (default before args are parsed)
LOGFILE="/home/ngs/hav_sequencing_wrapper_error.log"

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
    # Show it to the human: stdout -> tee -> the main wrapper log and the
    # screen window, plus $CONSOLE_TTY when launched detached.
    console "$msg"
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

# ── Resolve paths ─────────────────────────────────────────────────────────────
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/hav_input # Fasta, lokal database
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/${YEAR}/${BATCH_NAME}"
SMB_DIR_DATASET="Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Databaser/local_datasets"

echo "SMB_DIR: $SMB_DIR"
echo "SMB_DIR_DATASET: $SMB_DIR_DATASET"

LATEST_DATASET=$(
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_DATASET" -c "ls" \
    | awk '{print $1}' \
    | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    | sort \
    | tail -n 1
)

echo "Latest dataset: $LATEST_DATASET"

#LATEST_DATASET=$(basename "$(printf '%s\n' '/mnt/n/Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Databaser/local_datasets'/* | sort | tail -n 1)")
DEFAULT_DATASET_DATE="$LATEST_DATASET"



# Ensure $TMP_DIR exists and is clean
if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

echo "Temporary directory: $TMP_DIR"

# Create directory to hold the output of the analysis
# Ensure $HOME/$BATCH_NAME exists and is clean
if [ -d "$HOME/$BATCH_NAME" ]; then
    rm -rf "$HOME/$BATCH_NAME"
fi
mkdir -p "$HOME/$BATCH_NAME"
echo "Output directory: $HOME/$BATCH_NAME"

# Make sure the latest version of the ngs_scripts repo is present locally
REPO="$HOME/ngs_scripts"
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
HAV_SEQ_REPO="$HOME/hav_seq"
HAV_SEQ_REPO_URL="https://github.com/folkehelseinstituttet/hav_seq.git"

if [ -d "$HAV_SEQ_REPO" ]; then
    echo "Directory 'hav_seq' exists. Pulling latest changes..."
    cd "$HAV_SEQ_REPO"
    git pull
else
    echo "Directory 'hav_seq' does not exist. Cloning repository..."
    git clone "$HAV_SEQ_REPO_URL" "$HAV_SEQ_REPO"
fi

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