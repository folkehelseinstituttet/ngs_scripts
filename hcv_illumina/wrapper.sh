#!/usr/bin/env bash

set -euo pipefail

exec > >(tee -a /home/ngs/hcv_illumina_wrapper.log) 2>&1

# Trap errors and log them
LOGFILE="/home/ngs/hcv_illumina_wrapper_error.log"

trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    msg="[$(date)] Script exited with error code $ec"
    echo "$msg" >> "$LOGFILE"
    echo "$msg" >&2
    echo "Did you remember to change \"RUN_NAME\"?" >&2
  else
    msg="[$(date)] Script completed successfully."
    echo "$msg" >> "$LOGFILE"
    echo "$msg"
  fi' EXIT

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

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
VERSION="v1.0.6"  # Default version
RESUME=""

while getopts "hr:a:y:v:z" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VERSION="$OPTARG";;
        z) RESUME="-resume";;
        ?) usage ;;
    esac
done

# Make sure the latest version of the ngs_scripts repo is present locally

# Define the directory and the GitHub repository URL
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

# Check if the directory exists
if [ -d "$REPO" ]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    cd "$REPO"
    git pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    git clone "$REPO_URL" "$REPO"
fi

cd $HOME


# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
if [ -d "$HOME/hcv_illumina" ]; then 
    rm -rf $HOME/hcv_illumina
fi

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/${YEAR}
# Uncomment for testing
#SMB_DIR=Virologi/NGS/tmp/

# Old data is moved to Arkiv
current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/${YEAR}/Illumina_Run/$RUN"
elif [ "$YEAR" -lt "$current_year" ]; then 
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/Arkiv/${YEAR}/Illumina_Run/$RUN"
else 
    echo "Error: Year cannot be larger than $current_year"
    exit 1
fi

# If we run on the TEST or FULL_TEST data
if [ "$RUN" = "TEST" ]; then
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/TEST/HCV/$RUN"
elif [ "$RUN" = "FULL_TEST" ]; then 
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/TEST/HCV/$RUN"
fi

# Create directory to hold the output of the analysis
# Ensure $HOME/$RUN exists and is clean
if [ -d "$HOME/$RUN" ]; then
    rm -rf "$HOME/$RUN"
fi
mkdir -p "$HOME/$RUN"

# Ensure $TMP_DIR exists and is clean
if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
mkdir -p "$TMP_DIR"

### Prepare the run ###

echo "Copying fastq files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_INPUT <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF
    
# Create a samplesheet by running the supplied Rscript in a docker container.
echo "Creating samplesheet"
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR/ \
    -v $HOME/$RUN:/out \
    docker.io/jonbra/create_samplesheet:1.0 \
    Rscript create_samplesheet.R $TMP_DIR /out/samplesheet.csv ${AGENS}

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
# Temporarily disable set -u because the JAVA_HOME variable is unset
set +u
conda activate NEXTFLOW
set -u

# If not resuming a nextflow run, then clean-up the nextflow work and cache
if [ -z "$RESUME" ]; then # -z tests if the variable is empty
  # Clean up Nextflow cache to remove unused files
  nextflow clean -f -before "$( nextflow log -q | tail -n 1 )"
  # Clean up empty work directories
  # || true allows the script to continue if it can't delete everything
  find /mnt/tempdata/work -type d -empty -delete || true
fi

# Make sure the latest pipeline is available
nextflow pull folkehelseinstituttet/hcv_illumina -r $VERSION

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow run folkehelseinstituttet/hcv_illumina/ -r $VERSION -profile server --input "$HOME/$RUN/samplesheet.csv" --outdir "$HOME/$RUN" --agens $AGENS -with-tower --platform "illumina" --skip_hcvglue false --skip_assembly false --labware true $RESUME

## Rename LW import file 
mv $HOME/$RUN/summarize/Genotype_mapping_summary_long_LW_import.tsv $HOME/$RUN/summarize/${RUN}_HCV_genotype_and_GLUE_summary.tsv

## Then move the results to the N: drive
echo "Moving results to the N: drive"
mkdir $HOME/out_hcv
mv $RUN/ out_hcv/

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $HOME/out_hcv/
mput *
EOF

## Clean up
nextflow clean -f
rm -rf $HOME/out_hcv
rm -rf $TMP_DIR
