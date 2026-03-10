#!/usr/bin/env bash
set -euo pipefail

# Activate conda base hooks
source ~/miniconda3/etc/profile.d/conda.sh

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r <run>           Specify the run name (e.g., RSV001) (required)"
    echo "  -a <agens>         Specify agens (e.g., rsv) (required)"
    echo "  -s <season>        Specify season directory (optional)"
    echo "  -y <year>          Specify year directory (required)"
    echo "  -v <validation>    Specify validation flag (e.g., VER)"
    echo "  -p <scheme>        Primer scheme version (default: V1)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""
PRIMER_SCHEME="V1"

# Parse options
while getopts "hr:a:s:y:v:p:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        p) PRIMER_SCHEME="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "Error: -r, -a and -y are required."
    usage
fi

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "Error: -y must be a 4-digit year."
    exit 1
fi

# Print parsed arguments
echo "Run: $RUN"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Primer scheme: $PRIMER_SCHEME"

# Make sure the latest version of the ngs_scripts repo is present locally
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

if [[ -d "$REPO/.git" ]]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    git -C "$REPO" pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    rm -rf "$REPO"
    git clone "$REPO_URL" "$REPO"
fi

cd "$HOME"

# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
rm -rf "$HOME/rsvseq"

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN="eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm"
export TOWER_WORKSPACE_ID="150755685543204"

## Set up environment
BASE_DIR="/mnt/tempdata"
TMP_DIR="/mnt/tempdata/fastq"
SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"
SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/2-Resultater"

SKIP_RESULTS_MOVE=false
SMB_DIR_ANALYSIS=""

if [[ -n "$VALIDATION_FLAG" ]]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/4-Validering/1-rsvseq-validering/Run"
    SKIP_RESULTS_MOVE=true
fi

# Input fastq dir on storage
current_year=$(date +"%Y")

if (( YEAR > current_year )); then
    echo "Error: Year cannot be larger than $current_year"
    exit 1
fi

SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"

# Create directories
mkdir -p "$HOME/$RUN"
mkdir -p "$TMP_DIR"

### Prepare the run ###
echo "Copying fastq files from the N drive"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

## Set up
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit)
SAMPLESHEET="$TMP_DIR/${RUN}.csv"
RSV_DATABASE="/mnt/tempdata/rsv_db/assets"

if [[ -z "${SAMPLEDIR:-}" ]]; then
    echo "Error: Could not find sample directory under $TMP_DIR/$RUN"
    exit 1
fi

if [[ ! -f "$SAMPLESHEET" ]]; then
    echo "Error: Could not find samplesheet: $SAMPLESHEET"
    exit 1
fi

if [[ ! -d "$RSV_DATABASE" ]]; then
    echo "Error: RSV database directory not found: $RSV_DATABASE"
    exit 1
fi

echo "Sample directory found: $SAMPLEDIR"
echo "Samplesheet found: $SAMPLESHEET"

### Run the main pipeline ###
echo "Activating NEXTFLOW conda environment"

# Conda activation can fail under 'set -u' because some activate scripts
# reference unset vars like JAVA_HOME. Temporarily disable nounset.
set +u
conda activate NEXTFLOW
set -u

echo "Map to references and create consensus sequences"

nextflow pull RasmusKoRiis/nf-core-rsvseq -r master

nextflow run RasmusKoRiis/nf-core-rsvseq \
    -r master \
    -profile docker,server \
    --input "$SAMPLESHEET" \
    --samplesDir "$SAMPLEDIR" \
    --primerdir "$RSV_DATABASE/primer" \
    --primer_schemes_dir "$RSV_DATABASE/primer_schemes" \
    --primer_scheme "$PRIMER_SCHEME" \
    --outdir "$HOME/$RUN" \
    --runid "$RUN" \
    --release_version "v1.0.0"

echo "Preparing results for upload"
mkdir -p "$HOME/out_rsvseq"
rm -rf "$HOME/out_rsvseq/$RUN"
mv "$HOME/$RUN" "$HOME/out_rsvseq/"

if [[ "$SKIP_RESULTS_MOVE" == false ]]; then
    echo "Uploading full results to N: drive"
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $HOME/out_rsvseq
mput *
EOF
else
    echo "Validation mode detected: uploading report CSV files only"
    if [[ ! -d "$HOME/out_rsvseq/$RUN/report" ]]; then
        echo "Error: Report directory not found: $HOME/out_rsvseq/$RUN/report"
        exit 1
    fi

    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd $HOME/out_rsvseq/$RUN/report
mput *.csv
EOF
fi

echo "Run completed successfully."

## Clean up
# nextflow clean -f
# rm -rf "$HOME/out_rsvseq"
# rm -rf "$TMP_DIR/$RUN"
# rm -f "$SAMPLESHEET"
