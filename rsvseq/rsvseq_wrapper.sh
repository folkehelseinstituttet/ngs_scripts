#!/usr/bin/env bash
set -euo pipefail

# Activate conda
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

# Print parsed arguments (for debugging)
echo "Run: $RUN"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Primer scheme: $PRIMER_SCHEME"

# Make sure the latest version of the ngs_scripts repo is present locally
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

if [[ -d "$REPO" ]]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    cd "$REPO"
    git pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    git clone "$REPO_URL" "$REPO"
fi

cd "$HOME"

# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
rm -rf "$HOME/rsvseq"

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/2-Resultater

if [[ -n "$VALIDATION_FLAG" ]]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/4-Validering/1-rsvseq-validering/Run"
    SKIP_RESULTS_MOVE=true
else
    SKIP_RESULTS_MOVE=false
fi

# Input fastq dir on storage
current_year=$(date +"%Y")
if [[ "$YEAR" -eq "$current_year" ]]; then
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
elif [[ "$YEAR" -lt "$current_year" ]]; then
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
else
    echo "Error: Year cannot be larger than $current_year"
    exit 1
fi

# Create directory to hold the output of the analysis
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
SAMPLESHEET="/mnt/tempdata/fastq/${RUN}.csv"
RSV_DATABASE="/mnt/tempdata/rsv_db/assets"

if [[ -z "$SAMPLEDIR" ]]; then
    echo "Error: Could not find sample directory under $TMP_DIR/$RUN"
    exit 1
fi

### Run the main pipeline ###
conda activate NEXTFLOW

echo "Map to references and create consensus sequences"
nextflow pull RasmusKoRiis/nf-core-rsvseq
nextflow run RasmusKoRiis/nf-core-rsvseq/main.nf \
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

echo "Moving results to the N: drive"
mkdir -p "$HOME/out_rsvseq"
mv "$RUN/" "$HOME/out_rsvseq/"

if [[ "$SKIP_RESULTS_MOVE" == false ]]; then
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $HOME/out_rsvseq/
mput *
EOF
fi

if [[ "$SKIP_RESULTS_MOVE" == true ]]; then
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd $HOME/out_rsvseq/$RUN/report/
cd ${SMB_DIR_ANALYSIS}
mput *.csv
EOF
fi

## Clean up
# nextflow clean -f
# rm -rf "$HOME/out"
# rm -rf "$TMP_DIR"
