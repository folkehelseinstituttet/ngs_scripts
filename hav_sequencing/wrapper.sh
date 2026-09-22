#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variables, and pipefail


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
    lp)
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
SMB_DIR="/mnt/n/Virologi/Hepatitt/Hepatitt A/HAV genteknologi/${YEAR}/${BATCH_NAME}"
SMB_DIR_DATASET="/mnt/n/Virologi/Hepatitt/Hepatitt A/HAV genteknologi/Databaser/local_datasets"

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