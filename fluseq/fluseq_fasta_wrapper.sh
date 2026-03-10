#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

# Activate conda safely
export JAVA_HOME="${JAVA_HOME:-}"
source ~/miniconda3/etc/profile.d/conda.sh

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r RUN             Specify the run name (e.g., INF077)"
    echo "  -a AGENS           Specify agens (e.g., influensa and avian)"
    echo "  -s SEASON          Specify the season directory (e.g., Ses2526)"
    echo "  -y YEAR            Specify the year directory of the fasta export"
    echo "  -v VALIDATION      Specify validation flag (e.g., VER)"
    exit 1
}

RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""

while getopts "hr:a:s:y:v:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        ?) usage ;;
    esac
done

[ -z "$RUN" ] && { echo "ERROR: -r RUN is required"; usage; }
[ -z "$SEASON" ] && { echo "ERROR: -s SEASON is required"; usage; }
[ -z "$YEAR" ] && { echo "ERROR: -y YEAR is required"; usage; }

clean_field() {
    printf '%s' "$1" | sed 's/\r//g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

normalize_reference_name() {
    printf '%s' "$1" \
        | sed 's/\r//g; s/^[[:space:]]*//; s/[[:space:]]*$//' \
        | sed 's#/#_#g; s#[[:space:]]#_#g; s/[^A-Za-z0-9._-]/_/g; s/__\+/_/g'
}

extract_reference_from_fasta_header() {
    local fasta_file="$1"
    local header

    header=$(grep -m1 '^>' "$fasta_file" | sed 's/^>//')

    if [ -z "$header" ]; then
        echo "ERROR: No FASTA header found in $fasta_file"
        exit 1
    fi

    # Remove only the final segment suffix
    # Example:
    # A_Victoria_2570_2019_HA1 -> A_Victoria_2570_2019
    # A_Darwin_9_2021_PB2      -> A_Darwin_9_2021
    header="${header%_*}"

    normalize_reference_name "$header"
}

validate_reference_type() {
    local ref_root="$1"
    local ref_type="$2"
    local table_file="$3"

    echo "Validating references for type: $ref_type"

    if [ ! -d "$ref_root" ]; then
        echo "ERROR: Reference directory not found: $ref_root"
        exit 1
    fi

    if [ ! -f "$table_file" ]; then
        echo "ERROR: Reference table not found: $table_file"
        exit 1
    fi

    local found_any=false

    while IFS=';' read -r subtype reference type gisaid; do
        subtype=$(clean_field "$subtype")
        reference=$(clean_field "$reference")
        type=$(clean_field "$type")
        gisaid=$(clean_field "${gisaid:-}")

        [ -z "$subtype" ] && continue
        [ "$subtype" = "Subtype" ] && continue
        [ "$type" != "$ref_type" ] && continue

        found_any=true

        local subtype_dir="$ref_root/$subtype"
        if [ ! -d "$subtype_dir" ]; then
            echo "ERROR: Missing subtype directory for $ref_type/$subtype"
            echo "       Expected directory: $subtype_dir"
            exit 1
        fi

        local expected_norm
        expected_norm=$(normalize_reference_name "$reference")

        local actual_refs=()
        local fasta

        for fasta in "$subtype_dir"/*.fasta; do
            actual_refs+=("$(extract_reference_from_fasta_header "$fasta")")
        done

        if [ ${#actual_refs[@]} -eq 0 ]; then
            echo "ERROR: No FASTA files found in $subtype_dir"
            exit 1
        fi

        mapfile -t unique_actual_refs < <(printf '%s\n' "${actual_refs[@]}" | sort -u)

        if [ ${#unique_actual_refs[@]} -ne 1 ]; then
            echo "ERROR: Multiple different references found inside $subtype_dir"
            echo "       Found:"
            printf '       - %s\n' "${unique_actual_refs[@]}"
            echo "       Expected: $reference"
            exit 1
        fi

        local actual_norm="${unique_actual_refs[0]}"

        if [ "$actual_norm" != "$expected_norm" ]; then
            echo "ERROR: Wrong reference used for subtype '$subtype' [$ref_type]"
            echo "       Correct reference: $reference"
            echo "       Used reference:    $actual_norm"
            echo "       Directory:         $subtype_dir"
            echo "       FASTA files checked:"
            printf '       - %s\n' "$subtype_dir"/*.fasta
            exit 1
        fi

        echo "OK: $ref_type / $subtype -> $reference"
    done < "$table_file"

    if [ "$found_any" = false ]; then
        echo "ERROR: No entries found in $table_file for Type=$ref_type"
        exit 1
    fi
}

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

rm -rf "$HOME/fluseq"

export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
export TOWER_WORKSPACE_ID=150755685543204

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

mkdir -p "$HOME/$RUN"
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

echo "Updating reference table"
download_single_file_from_smb "$REFERENCE_DIR_REMOTE" "$FLU_DATABASE" "reference_table.csv"

echo "Using reference table: $REFERENCE_TABLE_LOCAL_FILE"
echo "Checking that downloaded references match reference_table.csv"
validate_reference_type "$SEQUENCE_REFERENCES/human" "human" "$REFERENCE_TABLE_LOCAL_FILE"

# Easy extension later:
# validate_reference_type "$SEQUENCE_REFERENCES/human_vaccine" "human_vaccine" "$REFERENCE_TABLE_LOCAL_FILE"

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

cd "$HOME"

set +u
conda activate NEXTFLOW
set -u

echo "Analysing consensus sequences"
nextflow pull RasmusKoRiis/nf-core-fluseq
nextflow run RasmusKoRiis/nf-core-fluseq/main.nf \
  -r master \
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
  --release_version "v1.0.2"

echo "Moving results to the N: drive"
mkdir -p "$HOME/out_fluseq"
rm -rf "$HOME/out_fluseq/$RUN"
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

## Clean up
# nextflow clean -f
# rm -rf "$HOME/out_fluseq"
# rm -rf "$TMP_DIR"
