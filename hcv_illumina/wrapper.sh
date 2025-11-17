#!/usr/bin/env bash

set -euo pipefail

# Send all stdout/stderr to the main wrapper log (and to the console when not detached)
exec > >(tee -a /home/ngs/hcv_illumina_wrapper.log) 2>&1

# Error log file (history of errors and status appends)
LOGFILE="/home/ngs/hcv_illumina_wrapper_error.log"

# Small helper to write status; STATUS_FILE is set after args are parsed.
# Writes to LOGFILE (append), wrapper log (append) and updates STATUS_FILE atomically
set_status() {
    msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    # history
    echo "$msg" >> "$LOGFILE"
    # main log as well
    echo "$msg" >> /home/ngs/hcv_illumina_wrapper.log
    # atomic write of the single-line status file if it's defined
    if [ -n "${STATUS_FILE:-}" ]; then
        tmp="${STATUS_FILE}.tmp"
        printf '%s\n' "$msg" > "$tmp" && mv "$tmp" "$STATUS_FILE"
    fi
}

# Trap for detailed error info: line number and command
trap 'set_status "Error at line $LINENO: \"$BASH_COMMAND\" exited with status $?"' ERR

# Trap for any script exits (success or failure)
trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    msg="Script exited with error code $ec"
    set_status "$msg"
    echo "$msg" >&2
    echo "Did you remember to change \"RUN_NAME\"?" >&2
  else
    msg="Script completed successfully."
    set_status "$msg"
    echo "$msg"
  fi' EXIT

# Activate conda helper (conda.sh) later when needed
# source ~/miniconda3/etc/profile.d/conda.sh will be called after we parse args

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: 1.0

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g., NGS_SEQ-20240214-03)"
    echo "  -a, --agens       Specify agens (e.g., HCV and ROV)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    echo "  -v, --version     Optional: Specify which version of the hcv_illumina pipeline to run"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""
VERSION="v1.1.5"  # Default version

# Parse options
while getopts "hr:a:y:v:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VERSION="$OPTARG";;
        ?) usage ;;
    esac
done

# Setup a simple per-run status file in $HOME so other terminals can poll it
if [ -n "${RUN:-}" ]; then
    STATUS_FILE="$HOME/hcv_illumina_${RUN}_status.txt"
else
    STATUS_FILE="$HOME/hcv_illumina_unknown_status.txt"
fi

# initialize status file and log initial status
printf '[%s] Initialized\n' "$(date +'%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
set_status "Started wrapper. RUN=$RUN AGENS=$AGENS YEAR=$YEAR VERSION=$VERSION"

# Make sure the latest version of the ngs_scripts repo is present locally
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

set_status "Ensuring local copy of ngs_scripts (pull/clone)"
if [ -d "$REPO" ]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    cd "$REPO"
    git pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    git clone "$REPO_URL" "$REPO"
fi

cd $HOME

# Remove potentially conflicting local pipeline clone
if [ -d "$HOME/hcvtyper" ]; then 
    rm -rf $HOME/hcvtyper
    set_status "Removed local hcvtyper directory to avoid conflicts"
fi

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment variables and paths
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq_hcv
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/${YEAR}
# Uncomment for testing
#SMB_DIR=Virologi/NGS/tmp/

# Decide SMB_INPUT based on YEAR and RUN
current_year=$(date +"%Y")
if [ -z "${YEAR:-}" ]; then
    echo "Error: YEAR not provided"
    exit 1
fi

if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/${YEAR}/Illumina_Run/$RUN"
elif [ "$YEAR" -lt "$current_year" ]; then 
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/Arkiv/${YEAR}/Illumina_Run/$RUN"
else 
    echo "Error: Year cannot be larger than $current_year"
    exit 1
fi

# Special cases for test runs
if [ "$RUN" = "TEST" ]; then
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/TEST/HCV/$RUN"
elif [ "$RUN" = "FULL_TEST" ]; then 
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/TEST/HCV/$RUN"
fi

# Prepare working directories
if [ -d "$HOME/$RUN" ]; then
    rm -rf "$HOME/$RUN"
fi
mkdir -p "$HOME/$RUN"

if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

### Prepare the run ###
set_status "Copying fastq files from the N drive (SMB_INPUT=$SMB_INPUT)"
echo "Copying fastq files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_INPUT <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

set_status "Fastq copy complete. Files are in $TMP_DIR"

# Create a samplesheet by running the supplied Rscript in a docker container.
set_status "Creating samplesheet"
echo "Creating samplesheet"
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR/ \
    -v $HOME/$RUN:/out \
    ghcr.io/jonbra/viralseq_utils:v1.0.2 \
    $TMP_DIR /out/samplesheet.csv

set_status "Samplesheet created: $HOME/$RUN/samplesheet.csv"

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
# Temporarily disable set -u because the JAVA_HOME variable might be unset
set +u
source ~/miniconda3/etc/profile.d/conda.sh
conda activate NEXTFLOW
set -u

set_status "Activated NEXTFLOW conda environment"

# Log which version will be used
set_status "Using VERSION=${VERSION}"
echo "Using VERSION=${VERSION}" | tee -a /home/ngs/hcv_illumina_wrapper.log >> "$LOGFILE"

# Pull the pipeline version
set_status "Pulling hcvtyper version ${VERSION}"
nextflow pull folkehelseinstituttet/hcvtyper -r $VERSION
set_status "Pulled hcvtyper version ${VERSION}"

# Start the pipeline (this is the long-running step)
set_status "Starting Nextflow run"
echo "Map to references and create consensus sequences"

# Adjust command flags as needed for your environment. The command below mirrors the typical invocation.
nextflow run folkehelseinstituttet/hcvtyper -r "$VERSION" -profile server \
    --input "$HOME/$RUN/samplesheet.csv" \
    --outdir "$HOME/$RUN" \
    -with-tower \
    --platform "illumina" \
    --skip_hcvglue false \
    --skip_assembly false

set_status "Nextflow run finished"

## Create a Labware import file from the Summary file
set_status "Creating labware import file from Summary"
mkdir -p $HOME/$RUN/labware_import
docker run --rm \
  -v "$HOME/$RUN/summary:/input" \
  -v "$HOME/$RUN/labware_import:/output" \
  ghcr.io/jonbra/hcv-labware-import:v1.0.2 \
  /input/Summary.csv \
  /output/$RUN

set_status "Labware import file created"

## Then move the results to the N: drive
set_status "Moving results to the N: drive"
echo "Moving results to the N: drive"
mkdir -p $HOME/out_hcv
cp -r $RUN/ out_hcv/

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $HOME/out_hcv/
mput *
EOF

set_status "Results copied to N: drive"

## Clean up
set_status "Cleaning up temporary files"
rm -rf $HOME/out_hcv
rm -rf $RUN
rm -rf $TMP_DIR
nextflow clean -f

set_status "Cleanup complete"

# End of script
