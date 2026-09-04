#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"

# Activate conda
source "$HOME/miniconda3/etc/profile.d/conda.sh"

# TODO

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g., INF077)"
    echo "  -a, --agens       Specify agens (e.g., influensa and avian)"
    echo "  -s, --season      Specify the season directory of the fastq files on the N-drive (e.g., Ses2425)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    echo "  -v, --validation  Specify validation flag (e.g., VER)"
    echo "  -b, --branch      Specify pipeline branch/tag to use (default: master)"
    exit "${1:-1}"
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""
PIPELINE_BRANCH="master"

while getopts "hr:a:s:y:v:b:" opt; do
    case "$opt" in
        h) usage 0 ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        b) PIPELINE_BRANCH="$OPTARG" ;;
        ?) usage ;;
    esac
done

[ -z "$RUN" ] && { echo "ERROR: -r RUN is required"; usage; }
[ -z "$SEASON" ] && { echo "ERROR: -s SEASON is required"; usage; }
[ -z "$YEAR" ] && { echo "ERROR: -y YEAR is required"; usage; }

if [[ ! "$RUN" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: RUN may contain only letters, numbers, dot, underscore, and hyphen."
    exit 1
fi
if [[ ! "$SEASON" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: SEASON may contain only letters, numbers, dot, underscore, and hyphen."
    exit 1
fi
if [[ ! "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "ERROR: YEAR must contain exactly four digits."
    exit 1
fi
if [[ ! "$PIPELINE_BRANCH" =~ ^[A-Za-z0-9._/-]+$ || "$PIPELINE_BRANCH" == *..* ]]; then
    echo "ERROR: Invalid pipeline branch or tag: $PIPELINE_BRANCH"
    exit 1
fi

if [ -e "$HOME/$RUN" ]; then
    echo "ERROR: Working output already exists: $HOME/$RUN"
    echo "Move or remove it before starting a new run."
    exit 1
fi

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

cd "$HOME"


# Load the Seqera/Tower credential from a private file when it is not inherited.
TOWER_ENV_FILE="${FLUSEQ_TOWER_ENV:-$HOME/.config/fluseq/tower.env}"
if [ -f "$TOWER_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$TOWER_ENV_FILE"
fi
if [ -n "${TOWER_ACCESS_TOKEN:-}" ]; then
    export TOWER_ACCESS_TOKEN
else
    echo "WARNING: TOWER_ACCESS_TOKEN is not set; continuing without Seqera/Tower monitoring."
fi
export TOWER_WORKSPACE_ID="${TOWER_WORKSPACE_ID:-150755685543204}"

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/results
SMB_DIR_ANALYSIS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/powerBI

# If validation flag is set, update SMB_DIR_ANALYSIS and skip the results move step
if [ -n "$VALIDATION_FLAG" ]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/4-Validering/1-fluseq-validering/Run"
    SKIP_RESULTS_MOVE=true
else
    SKIP_RESULTS_MOVE=false
fi

# Old data is moved to Arkiv
current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/${YEAR}/Nanopore_Grid_Run/${RUN}
elif [ "$YEAR" -lt "$current_year" ]; then 
	SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/Arkiv/${YEAR}/Nanopore_Grid_Run/${RUN}
else 
	echo "Error: Year cannot be larger than $current_year"
	exit 1
fi


# Create the temporary input root. Nextflow creates the output after preflight.
mkdir -p "$TMP_DIR"

### Prepare the run ###

echo "Copying fastq files from the N drive"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

## Set up databases
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit)
SAMPLESHEET=/mnt/tempdata/fastq/${RUN}.csv
FLU_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db
HA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_HA.fasta
NA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_NA.fasta
MAMMALIAN_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Mammalian_Mutations_of_Intrest_2324.xlsx
INHIBTION_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Inhibtion_Mutations_of_Intrest_2324.xlsx
REASSORTMENT_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/reassortment_database.fasta
GENOTYPE_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/H5_genotype_database.fasta
SEQUENCE_REFERENCES=/mnt/tempdata/influensa_db/flu_seq_db/sequence_references
NEXTCLADE_DATASET=/mnt/tempdata/influensa_db/flu_seq_db/nextclade_datasets
MUTATION_LITS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/Mutation_lists
SEASON_FILES=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}

echo "Updateing mutation lists"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$MUTATION_LITS" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE
mget *
EOF

echo "Updating reassortment database"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SEASON_FILES" <<EOF
prompt OFF
lcd $FLU_DATABASE
mget reassortment_database.fasta
EOF

echo "Updating H5 genotype database"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SEASON_FILES" <<EOF
prompt OFF
lcd $FLU_DATABASE
mget H5_genotype_database.fasta
EOF

    
# Create a samplesheet by running the supplied Rscript in a docker container.
#ADD CODE FOR HANDLING OF SAMPLESHEET

for required_file in "$SAMPLESHEET" "$HA_DATABASE" "$NA_DATABASE" "$GENOTYPE_DATABASE" "$MAMMALIAN_MUTATION_DATABASE" "$INHIBTION_MUTATION_DATABASE" "$REASSORTMENT_DATABASE"; do
    if [ ! -f "$required_file" ]; then
        echo "ERROR: Required pipeline input is missing: $required_file"
        exit 1
    fi
done
for required_dir in "$SAMPLEDIR" "$SEQUENCE_REFERENCES" "$NEXTCLADE_DATASET"; do
    if [ ! -d "$required_dir" ]; then
        echo "ERROR: Required pipeline directory is missing: $required_dir"
        exit 1
    fi
done

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
set +u
conda activate NEXTFLOW
set -u

# Make sure the latest pipeline is available
#nextflow pull folkehelseinstituttet/viralseq

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow pull RasmusKoRiis/nf-core-fluseq -r "$PIPELINE_BRANCH"
nextflow run RasmusKoRiis/nf-core-fluseq/main.nf \
  -r "$PIPELINE_BRANCH" \
  -profile docker,server \
  --file avian-fastq   \
  --genotype_database "$GENOTYPE_DATABASE" \
  --input "$SAMPLESHEET" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --ha_database "$HA_DATABASE" \
  --na_database "$NA_DATABASE" \
  --mamalian_mutation_db "$MAMMALIAN_MUTATION_DATABASE" \
  --inhibtion_mutation_db "$INHIBTION_MUTATION_DATABASE" \
  --sequence_references "$SEQUENCE_REFERENCES" \
  --nextclade_dataset  "$NEXTCLADE_DATASET" \
  --reassortment_database  "$REASSORTMENT_DATABASE" \
  --runid "$RUN" \
  --release_version "v1.0.2" 

echo "Moving results to the N: drive"
mkdir -p "$HOME/out_fluseq"
if [ -e "$HOME/out_fluseq/$RUN" ]; then
    PREVIOUS_RESULTS="$HOME/out_fluseq/${RUN}.previous.$(date +%Y%m%dT%H%M%S)"
    echo "Archiving previous local results to $PREVIOUS_RESULTS"
    mv "$HOME/out_fluseq/$RUN" "$PREVIOUS_RESULTS"
fi
mv "$HOME/$RUN" "$HOME/out_fluseq/"

if [ "$SKIP_RESULTS_MOVE" = false ]; then
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $HOME/out_fluseq/
mput *
EOF
fi

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd $HOME/out_fluseq/${RUN}/reporthuman/
cd ${SMB_DIR_ANALYSIS}
mput *.csv
EOF


## Clean up
#nextflow clean -f
#rm -rf $HOME/out
#rm -rf $TMP_DIR
