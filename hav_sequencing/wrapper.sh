#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variables, and pipefail


# ── Argument parsing ──────────────────────────────────────────────────────────
MODE=""
BATCH_NAME=""
YEAR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --batch-name)
            BATCH_NAME="$2"
            shift 2
            ;;
        --year)
            YEAR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" || -z "$BATCH_NAME" || -z "$YEAR" ]]; then
    echo "Usage: $0 --mode <mode> --batch-name <batch_name> --year <year>"
    exit 1
fi


# ── Resolve paths ─────────────────────────────────────────────────────────────
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/hav_input
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR="/mnt/n/Virologi/Hepatitt/Hepatitt A/HAV genteknologi/$YEAR/$BATCH_NAME"



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