#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "  -b <branch>        Pipeline branch/tag to use (default: master)"
    echo "  -P <path>          PCR JSON file or directory (default: /mnt/tempdata/rsv_db/pcr-primers)"
    echo "  -N <dir>           NGS schemes root containing RSVA/<scheme> and RSVB/<scheme>"
    exit "${1:-1}"
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""
PRIMER_SCHEME="V1"
PIPELINE_BRANCH="master"
PRIMER_CHECK_PCR="${PRIMER_CHECK_PCR:-/mnt/tempdata/rsv_db/pcr-primers}"
PRIMER_CHECK_NGS_DIR="${PRIMER_CHECK_NGS_DIR:-}"
PRIMER_CHECK_CONTAINER="${PRIMER_CHECK_CONTAINER:-ghcr.io/rasmuskoriis/primer-checker:latest}"
PRIMER_CHECK_ENABLED="${PRIMER_CHECK_ENABLED:-true}"

# Parse options
while getopts "hr:a:s:y:v:p:b:P:N:" opt; do
    case "$opt" in
        h) usage 0 ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        p) PRIMER_SCHEME="$OPTARG" ;;
        b) PIPELINE_BRANCH="$OPTARG" ;;
        P) PRIMER_CHECK_PCR="$OPTARG" ;;
        N) PRIMER_CHECK_NGS_DIR="$OPTARG" ;;
        *) usage ;;
    esac
done

# shellcheck source=../resp-virus-toolkit/wrapper_logging.sh
source "$SCRIPT_DIR/../resp-virus-toolkit/wrapper_logging.sh"
wrapper_logs_init rsvseq "$RUN"

if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "Error: -r, -a and -y are required."
    usage
fi

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "Error: -y must be a 4-digit year."
    exit 1
fi

# Initialize conda after logging is ready so setup failures are retained.
source "${CONDA_PROFILE:-$HOME/miniconda3/etc/profile.d/conda.sh}"

# Print parsed arguments
echo "Run: $RUN"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Primer scheme: $PRIMER_SCHEME"
echo "Pipeline branch: $PIPELINE_BRANCH"

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
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" \
  -c "prompt OFF; recurse ON; lcd $TMP_DIR; mget *"

## Set up
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit)
SAMPLESHEET="$TMP_DIR/${RUN}.csv"
RSV_DATABASE="/mnt/tempdata/rsv_db/assets"
PRIMER_CHECK_NGS_DIR="${PRIMER_CHECK_NGS_DIR:-$RSV_DATABASE/primer_schemes}"

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

export NXF_VER="24.10.2"
unset NXF_DEFAULT_DSL
export NXF_HOME="/tmp/nxf_${USER}"

echo "NXF env:"
env | grep '^NXF_' | sort || true

echo "NXF env:"
env | grep '^NXF_' | sort || true

echo "Map to references and create consensus sequences"

nextflow -log "$NEXTFLOW_LOG" pull RasmusKoRiis/nf-core-rsvseq -r "$PIPELINE_BRANCH"

wrapper_logs_nextflow_start
nextflow -log "$NEXTFLOW_LOG" -c "$SCRIPT_DIR/../resp-virus-toolkit/wrapper_cleanup.config" \
    run RasmusKoRiis/nf-core-rsvseq \
    -r "$PIPELINE_BRANCH" \
    -profile docker,server \
    --input "$SAMPLESHEET" \
    --samplesDir "$SAMPLEDIR" \
    --primerdir "$RSV_DATABASE/primer" \
    --primer_schemes_dir "$RSV_DATABASE/primer_schemes" \
    --primer_scheme "$PRIMER_SCHEME" \
    --outdir "$HOME/$RUN" \
    --runid "$RUN" \
    --primer_check "$PRIMER_CHECK_ENABLED" \
    --primer_check_pcr "$PRIMER_CHECK_PCR" \
    --primer_check_ngs_dir "$PRIMER_CHECK_NGS_DIR" \
    --primer_check_container "$PRIMER_CHECK_CONTAINER" \
    --release_version "v1.0.0"

wrapper_logs_status "Nextflow finished; preparing results for upload"
mkdir -p "$HOME/out_rsvseq"
if [ -e "$HOME/out_rsvseq/$RUN" ]; then
    PREVIOUS_RESULTS="$HOME/out_rsvseq/${RUN}.previous.$(date +%Y%m%dT%H%M%S).$$"
    echo "Archiving previous local results to $PREVIOUS_RESULTS"
    mv "$HOME/out_rsvseq/$RUN" "$PREVIOUS_RESULTS"
fi
mv "$HOME/$RUN" "$HOME/out_rsvseq/"

if [[ "$SKIP_RESULTS_MOVE" == false ]]; then
    echo "Uploading full results to N: drive"
    wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" \
      -c "prompt OFF; recurse ON; lcd \"$HOME/out_rsvseq\"; mput \"$RUN\""
else
    echo "Validation mode detected: uploading report CSV files only"
    if [[ ! -d "$HOME/out_rsvseq/$RUN/report" ]]; then
        echo "Error: Report directory not found: $HOME/out_rsvseq/$RUN/report"
        exit 1
    fi

    wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" \
      -c "prompt OFF; lcd \"$HOME/out_rsvseq/$RUN/report\"; mput *.csv"
    if [[ -d "$HOME/out_rsvseq/$RUN/primer_check" ]]; then
        wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" \
          -c "prompt OFF; lcd \"$HOME/out_rsvseq/$RUN/primer_check\"; mput *.csv"
    fi
fi

wrapper_logs_status "Required result uploads completed"
if [[ "$SKIP_RESULTS_MOVE" == true ]]; then
    wrapper_logs_complete "$HOME/out_rsvseq/$RUN" "$SMB_DIR_ANALYSIS" "$TMP_DIR/$RUN" "$SAMPLESHEET" 0
else
    wrapper_logs_complete "$HOME/out_rsvseq/$RUN" "$SMB_DIR" "$TMP_DIR/$RUN" "$SAMPLESHEET" 1
fi

# The shared EXIT handler verifies logs and cleans only this run.
