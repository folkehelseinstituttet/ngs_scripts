#!/usr/bin/env bash
set -euo pipefail

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r <run>           Specify the run name (e.g., INF077) (required)"
    echo "  -p <primer>        Specify the primer version (e.g., V5.4.2)"
    echo "  -a <agens>         Specify agens (e.g., sars) (required)"
    echo "  -s <season>        Specify the season directory of the fastq files on the N-drive (e.g., Ses2425)"
    echo "  -y <year>          Specify the year directory of the fastq files on the N-drive"
    echo "  -v <validation>    Specify validation flag (e.g., VER)"
    echo "  -b <branch>        Pipeline branch/tag to use (default: master)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
PRIMER=""
VALIDATION_FLAG=""
SKIP_RESULTS_MOVE=false
PIPELINE_BRANCH="master"

# Parse options
while getopts "hr:p:a:s:y:v:b:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        p) PRIMER="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        b) PIPELINE_BRANCH="$OPTARG" ;;
        ?) usage ;;
    esac
done

# Validate required arguments
if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "ERROR: -r, -a, and -y are required."
    usage
fi

# Print parsed arguments
echo "Run: $RUN"
echo "Primer: $PRIMER"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Pipeline branch: $PIPELINE_BRANCH"

# Repo setup
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

if [ -d "$REPO" ]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    cd "$REPO"
    git pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    git clone "$REPO_URL" "$REPO"
fi

cd "$HOME"

# Remove locally cloned pipeline to avoid version conflicts
rm -rf "$HOME/sarsseq"

# Tower config
export TOWER_ACCESS_TOKEN="eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm"
export TOWER_WORKSPACE_ID="150755685543204"

# Base paths
BASE_DIR="/mnt/tempdata"
TMP_DIR="/mnt/tempdata/fastq"
SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"

# Output locations
LOCAL_RUN_OUTDIR="$HOME/$RUN"
LOCAL_UPLOAD_ROOT="$HOME/out_sarsseq"
LOCAL_UPLOAD_RUN="$LOCAL_UPLOAD_ROOT/$RUN"

# SARS destinations on SMB
SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/8-FASTA-ANALYSIS"
SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/8-FASTA-ANALYSIS/report"

current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/7-Export"
elif [ "$YEAR" -lt "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/7-Export"
else
    echo "ERROR: Year cannot be larger than $current_year"
    exit 1
fi

# Prepare local dirs
mkdir -p "$TMP_DIR"
mkdir -p "$LOCAL_UPLOAD_ROOT"
rm -rf "$TMP_DIR/$RUN"
rm -rf "$LOCAL_RUN_OUTDIR"
rm -rf "$LOCAL_UPLOAD_RUN"

echo "Copying run folder from the N drive"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget $RUN
EOF

# Database assets
SARS_DATABASE="/mnt/tempdata/sars_db/assets"

# Find FASTA
FASTA=$(find "$TMP_DIR/$RUN" -maxdepth 2 -type f -name '*.fasta' | head -n 1)

if [[ -z "$FASTA" ]]; then
    echo "ERROR: No FASTA file found under $TMP_DIR/$RUN"
    exit 1
fi

echo "Using FASTA: $FASTA"

# Activate Nextflow env
set +u
conda activate NEXTFLOW
set -u

echo "Running SARS pipeline"
nextflow pull RasmusKoRiis/nf-core-sars -r "$PIPELINE_BRANCH"

nextflow run RasmusKoRiis/nf-core-sars/main.nf \
  -r "$PIPELINE_BRANCH" \
  -profile docker,server \
  --fasta "$FASTA" \
  --outdir "$LOCAL_RUN_OUTDIR" \
  --file fasta-workflow \
  --runid "$RUN" \
  --spike "$SARS_DATABASE/Spike_mAbs_inhibitors.csv" \
  --rdrp "$SARS_DATABASE/RdRP_inhibitors.csv" \
  --clpro "$SARS_DATABASE/3CLpro_inhibitors.csv" \
  --release_version "v1.0.0"

# Verify results exist
if [[ ! -d "$LOCAL_RUN_OUTDIR" ]]; then
    echo "ERROR: Expected output directory was not created: $LOCAL_RUN_OUTDIR"
    exit 1
fi

if [[ -z "$(find "$LOCAL_RUN_OUTDIR" -mindepth 1 -print -quit)" ]]; then
    echo "ERROR: Output directory exists but is empty: $LOCAL_RUN_OUTDIR"
    exit 1
fi

echo "Pipeline output created at: $LOCAL_RUN_OUTDIR"
find "$LOCAL_RUN_OUTDIR" -maxdepth 2 | head -n 50

echo "Moving results to local upload staging area"
mv "$LOCAL_RUN_OUTDIR" "$LOCAL_UPLOAD_ROOT/"

if [ "$SKIP_RESULTS_MOVE" = false ]; then
    echo "Uploading full run folder to N drive: $SMB_DIR"

    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
mkdir $RUN
cd $RUN
lcd $LOCAL_UPLOAD_RUN
mput *
EOF
fi

if [ "$SKIP_RESULTS_MOVE" = true ]; then
    echo "Uploading report CSV files only to N drive: $SMB_DIR_ANALYSIS"

    if [[ ! -d "$LOCAL_UPLOAD_RUN/report" ]]; then
        echo "ERROR: Report directory not found: $LOCAL_UPLOAD_RUN/report"
        exit 1
    fi

    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd $LOCAL_UPLOAD_RUN/report
mput *.csv
EOF
fi

echo "Done. Final local result location:"
echo "$LOCAL_UPLOAD_RUN"
