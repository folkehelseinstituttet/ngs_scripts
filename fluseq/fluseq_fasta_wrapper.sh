#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Standalone reference validation runs before conda, downloads, or pipeline work.
# Header format: STRAIN|EPI_ISL_<digits>_<segment>
validate_reference_type() {
    python3 "$SCRIPT_DIR/reference_validation.py" "$@"
}

if [[ "${1:-}" == "--check-references" ]]; then
    if [[ $# -lt 3 || $# -gt 4 ]]; then
        echo "Usage: $0 --check-references REFERENCE_ROOT REFERENCE_TABLE [human|human_vaccine]" >&2
        exit 2
    fi
    reference_type="${4:-human}"
    if [[ "$reference_type" != "human" && "$reference_type" != "human_vaccine" ]]; then
        echo "ERROR: Reference type must be human or human_vaccine" >&2
        exit 2
    fi
    validate_reference_type "$2/$reference_type" "$reference_type" "$3"
    exit $?
fi

# Activate conda safely
export JAVA_HOME="${JAVA_HOME:-}"
source "$HOME/miniconda3/etc/profile.d/conda.sh"

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "       $SCRIPT_NAME --check-references REFERENCE_ROOT REFERENCE_TABLE [human|human_vaccine]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r RUN             Specify the run name (e.g., INF077)"
    echo "  -a AGENS           Specify agens (e.g., influensa and avian)"
    echo "  -s SEASON          Specify the season directory (e.g., Ses2526)"
    echo "  -y YEAR            Specify the year directory of the fasta export"
    echo "  -v VALIDATION      Specify validation flag (e.g., VER)"
    echo "  -b BRANCH          Pipeline branch/tag to use (default: master)"
    echo "  -P PATH            PCR JSON file or directory (default: /mnt/tempdata/influensa_db/flu_seq_db/pcr-primers)"
    echo "  Master CSV: set FLUSEQ_MASTER_UPDATE=true; metadata defaults beside master.csv (see master_csv/README.md)"
    exit "${1:-1}"
}

RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""
PIPELINE_BRANCH="master"
PRIMER_CHECK_PCR="${PRIMER_CHECK_PCR:-/mnt/tempdata/influensa_db/flu_seq_db/pcr-primers}"
PRIMER_CHECK_CONTAINER="${PRIMER_CHECK_CONTAINER:-ghcr.io/rasmuskoriis/primer-checker:latest}"
PRIMER_CHECK_ENABLED="${PRIMER_CHECK_ENABLED:-true}"

while getopts "hr:a:s:y:v:b:P:" opt; do
    case "$opt" in
        h) usage 0 ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        b) PIPELINE_BRANCH="$OPTARG" ;;
        P) PRIMER_CHECK_PCR="$OPTARG" ;;
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

echo "Run: $RUN"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Pipeline branch: $PIPELINE_BRANCH"

# Validate master-merge configuration before downloads and analysis.
MASTER_CSV_TOOLS="${FLUSEQ_MASTER_TOOLS:-$SCRIPT_DIR/master_csv}"
python3 "$MASTER_CSV_TOOLS/bin/update_master_csv.py" \
    --workflow fasta --validation "$VALIDATION_FLAG" --check-config

download_single_file_from_smb() {
    local remote_dir="$1"
    local local_dir="$2"
    local filename="$3"

    mkdir -p "$local_dir"
    rm -f "$local_dir/$filename"

    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$remote_dir" <<EOF
prompt OFF
lcd $local_dir
mget $filename
EOF

    if [ ! -f "$local_dir/$filename" ]; then
        echo "ERROR: Failed to download $filename from $remote_dir"
        exit 1
    fi

    echo "OK: Downloaded $filename"
}

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

BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/fasta_fluseq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt

SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/fasta/results"
SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/fasta/results/report"

if [ -n "$VALIDATION_FLAG" ]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/4-Validering/1-fluseq-validering/Run"
    SKIP_RESULTS_MOVE=true
else
    SKIP_RESULTS_MOVE=false
fi

current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/12-Export/${YEAR}"
elif [ "$YEAR" -lt "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/12-Export/${YEAR}"
else
    echo "ERROR: Year cannot be larger than $current_year"
    exit 1
fi

mkdir -p "$TMP_DIR"
rm -rf "$TMP_DIR/$RUN"

echo "Copying run folder from the N drive"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget $RUN
EOF

SAMPLEDIR="$TMP_DIR/$RUN"
SAMPLESHEET=/mnt/tempdata/influensa_db/flu_seq_db/samplesheet.csv
FLU_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db
HA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_HA.fasta
NA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_NA.fasta
MAMMALIAN_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Mammalian_Mutations_of_Intrest_2324.xlsx
INHIBTION_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Inhibtion_Mutations_of_Intrest_2324.xlsx
REASSORTMENT_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/reassortment_database.fasta
GENOTYPE_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/H5_genotype_database.fasta
SEQUENCE_REFERENCES=/mnt/tempdata/influensa_db/flu_seq_db/sequence_references
NEXTCLADE_DATASET=/mnt/tempdata/influensa_db/flu_seq_db/nextclade_datasets

MUTATION_LISTS_REMOTE="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/Mutation_lists"
REFERENCE_DIR_REMOTE="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/references"
HUMAN_REFERENCES_REMOTE="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/references/human"
HUMAN_VACCINE_REFERENCES_REMOTE="$REFERENCE_DIR_REMOTE/human_vaccine"
REASSORTMENT_REMOTE_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}"
GENOTYPE_REMOTE_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}"
REFERENCE_TABLE_LOCAL_FILE="$FLU_DATABASE/reference_table.csv"

if [ ! -d "$SAMPLEDIR" ]; then
    echo "ERROR: Could not find downloaded run directory: $SAMPLEDIR"
    exit 1
fi

echo "Updating mutation lists"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$MUTATION_LISTS_REMOTE" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE
mget *
EOF

echo "Updating reassortment database"
download_single_file_from_smb "$REASSORTMENT_REMOTE_DIR" "$FLU_DATABASE" "reassortment_database.fasta"

echo "Updating H5 genotype database"
download_single_file_from_smb "$GENOTYPE_REMOTE_DIR" "$FLU_DATABASE" "H5_genotype_database.fasta"

echo "Updating human references"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$HUMAN_REFERENCES_REMOTE" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE/sequence_references/human
mget *
EOF

echo "Updating human vaccine references"
mkdir -p "$SEQUENCE_REFERENCES/human_vaccine"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$HUMAN_VACCINE_REFERENCES_REMOTE" <<EOF
prompt OFF
recurse ON
lcd $SEQUENCE_REFERENCES/human_vaccine
mget *
EOF

echo "Updating reference table"
download_single_file_from_smb "$REFERENCE_DIR_REMOTE" "$FLU_DATABASE" "reference_table.csv"

echo "Using reference table: $REFERENCE_TABLE_LOCAL_FILE"
echo "Checking that downloaded references match reference_table.csv"
validate_reference_type "$SEQUENCE_REFERENCES/human" "human" "$REFERENCE_TABLE_LOCAL_FILE"
validate_reference_type "$SEQUENCE_REFERENCES/human_vaccine" "human_vaccine" "$REFERENCE_TABLE_LOCAL_FILE"

echo "Preparing FASTA input"
cd "$SAMPLEDIR"

input_fastas=( *.fasta )
if [ ${#input_fastas[@]} -eq 0 ]; then
    echo "ERROR: No .fasta files found in $SAMPLEDIR"
    exit 1
fi

rm -f ./*dedup*.fasta "./${RUN}.fasta"

python3 "$HOME/ngs_scripts/fluseq/dedup_rename_fasta_avianseq.py" "${input_fastas[@]}"

dedup_fastas=( *dedup*.fasta )
if [ ${#dedup_fastas[@]} -eq 0 ]; then
    echo "ERROR: dedup_rename_fasta_avianseq.py did not create any *dedup*.fasta files"
    exit 1
fi

cat "${dedup_fastas[@]}" > "${RUN}.fasta"

if [ ! -s "${RUN}.fasta" ]; then
    echo "ERROR: Combined FASTA file was not created correctly: $SAMPLEDIR/${RUN}.fasta"
    exit 1
fi

for required_file in "$SAMPLEDIR/$RUN.fasta" "$HA_DATABASE" "$NA_DATABASE" "$GENOTYPE_DATABASE" "$INHIBTION_MUTATION_DATABASE" "$REASSORTMENT_DATABASE"; do
    if [ ! -f "$required_file" ]; then
        echo "ERROR: Required pipeline input is missing: $required_file"
        exit 1
    fi
done
for required_dir in "$SEQUENCE_REFERENCES" "$NEXTCLADE_DATASET"; do
    if [ ! -d "$required_dir" ]; then
        echo "ERROR: Required pipeline directory is missing: $required_dir"
        exit 1
    fi
done

cd "$HOME"

set +u
conda activate NEXTFLOW
set -u

echo "Analysing consensus sequences"
nextflow pull RasmusKoRiis/nf-core-fluseq -r "$PIPELINE_BRANCH"
nextflow run RasmusKoRiis/nf-core-fluseq/main.nf \
  -r "$PIPELINE_BRANCH" \
  -profile docker,server \
  --file human-fasta \
  --input "$SAMPLESHEET" \
  --genotype_database "$GENOTYPE_DATABASE" \
  --fasta "$SAMPLEDIR/$RUN.fasta" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --ha_database "$HA_DATABASE" \
  --na_database "$NA_DATABASE" \
  --mamalian_mutation_db "$MAMMALIAN_MUTATION_DATABASE" \
  --inhibtion_mutation_db "$INHIBTION_MUTATION_DATABASE" \
  --sequence_references "$SEQUENCE_REFERENCES" \
  --nextclade_dataset "$NEXTCLADE_DATASET" \
  --reassortment_database "$REASSORTMENT_DATABASE" \
  --runid "$RUN" \
  --primer_check "$PRIMER_CHECK_ENABLED" \
  --primer_check_pcr "$PRIMER_CHECK_PCR" \
  --primer_check_container "$PRIMER_CHECK_CONTAINER" \
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
lcd $HOME/out_fluseq
mput *
EOF
fi

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd $HOME/out_fluseq/${RUN}/reporthuman
mput *.csv
EOF

# Merge only the completed run report, after successful result uploads.
QC_REMOTE_DIR="$SMB_DIR_ANALYSIS"
if [ "$SKIP_RESULTS_MOVE" = false ]; then
    QC_REMOTE_DIR="$SMB_DIR/$RUN/reporthuman"
fi
python3 "$MASTER_CSV_TOOLS/bin/update_master_csv.py" \
    --workflow fasta --validation "$VALIDATION_FLAG" \
    --report "$HOME/out_fluseq/${RUN}/reporthuman/${RUN}.csv" \
    --fasta "$HOME/out_fluseq/${RUN}/reporthuman/${RUN}.fasta" \
    --qc-output "$HOME/out_fluseq/${RUN}/reporthuman/${RUN}_qc.html" \
    --qc-coverage-threshold "${FLUSEQ_QC_COVERAGE_THRESHOLD:-80}" \
    --qc-smb-share "$SMB_HOST" --qc-smb-dir "$QC_REMOTE_DIR" --qc-smb-auth "$SMB_AUTH"

## Clean up
# nextflow clean -f
# rm -rf "$HOME/out_fluseq"
# rm -rf "$TMP_DIR"
