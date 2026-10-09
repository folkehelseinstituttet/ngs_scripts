#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"

# Standalone reference validation runs before conda, downloads, or pipeline work.
# Header format: STRAIN|EPI_ISL_<digits>_<segment>
validate_reference_type() {
    python3 - "$@" <<'PY_REFERENCE_VALIDATOR'
"""Validate reference header names and EPI identifiers against a seasonal table."""

import csv
from pathlib import Path
import re
import sys


EPI_PATTERN = re.compile(r"EPI_ISL_[0-9]+")
REQUIRED_COLUMNS = {"Subtype", "Reference", "Type", "GISAID_EPI"}


def normalize_reference_name(value):
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9._-]", "_", value.strip()))


def load_reference_table(path, reference_type):
    rows = {}
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        reader.fieldnames = [name.strip() for name in (reader.fieldnames or [])]
        missing = REQUIRED_COLUMNS - set(reader.fieldnames)
        if missing:
            raise ValueError("Reference table is missing columns: " + ", ".join(sorted(missing)))
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise ValueError(f"Malformed reference-table row {line_number}")
            row = {key: value.strip() for key, value in row.items()}
            if row["Type"] != reference_type:
                continue
            if not all(row[column] for column in REQUIRED_COLUMNS):
                raise ValueError(f"Missing value in reference-table row {line_number}")
            subtype = row["Subtype"]
            if not re.fullmatch(r"[A-Za-z0-9._-]+", subtype) or subtype in {".", ".."}:
                raise ValueError(f"Invalid subtype in reference-table row {line_number}: {subtype!r}")
            if not EPI_PATTERN.fullmatch(row["GISAID_EPI"]):
                raise ValueError(f"Invalid GISAID_EPI for {reference_type}/{subtype}: {row['GISAID_EPI']!r}")
            if "|" in row["Reference"]:
                raise ValueError(f"Reference name contains a reserved pipe character: {row['Reference']!r}")
            if subtype in rows:
                raise ValueError(f"Duplicate reference-table entry for {reference_type}/{subtype}")
            rows[subtype] = row
    if not rows:
        raise ValueError(f"No reference-table entries for Type={reference_type}")
    return rows


def parse_reference_header(header, fasta_path, allow_legacy=False):
    name_and_epi, separator, segment = header.strip().rpartition("_")
    if not separator or not segment:
        raise ValueError(f"Missing terminal segment suffix in {fasta_path}: {header!r}")
    if "|" in name_and_epi:
        fields = name_and_epi.split("|")
        if len(fields) != 2 or not EPI_PATTERN.fullmatch(fields[1]):
            raise ValueError(f"Invalid EPI header in {fasta_path}: {header!r}")
        name, epi = fields
    elif allow_legacy:
        name, epi = name_and_epi, None
    else:
        raise ValueError(f"Missing EPI identifier in {fasta_path}; expected STRAIN|EPI_ISL_<digits>_<segment>")

    protein = Path(fasta_path).stem.upper()
    aliases = {
        "HA1": {"HA1", "HA"},
        "HA2": {"HA2", "HA"},
        "NS1": {"NS1", "NS"},
        "NS2": {"NS2", "NS"},
        "M1": {"M1", "M", "MP"},
        "M2": {"M2", "M", "MP"},
        "SIGPEP": {"SIGPEP", "SIG"},
    }
    if segment.upper() not in aliases.get(protein, {protein}):
        raise ValueError(f"Wrong segment suffix in {fasta_path}: {segment!r}")
    if not name.strip():
        raise ValueError(f"Empty reference name in {fasta_path}")
    return name.strip(), epi, segment


def check_reference_header(header, fasta_path, expected, allow_legacy=False):
    name, epi, segment = parse_reference_header(header, fasta_path, allow_legacy=allow_legacy)
    if normalize_reference_name(name) != normalize_reference_name(expected["Reference"]):
        raise ValueError(
            f"Wrong reference in {fasta_path}: expected {expected['Reference']!r}, found {name!r}"
        )
    if epi is not None and epi != expected["GISAID_EPI"]:
        raise ValueError(
            f"Wrong EPI in {fasta_path}: expected {expected['GISAID_EPI']}, found {epi}"
        )
    return segment


def validate_reference_type(reference_root, reference_type, table_path):
    root = Path(reference_root)
    if not root.is_dir():
        raise ValueError(f"Reference directory not found: {root}")
    expected_rows = load_reference_table(table_path, reference_type)
    total_files = 0
    for subtype, expected in expected_rows.items():
        subtype_dir = root / subtype
        if not subtype_dir.is_dir():
            raise ValueError(f"Missing subtype directory: {subtype_dir}")
        fasta_files = sorted(subtype_dir.glob("*.fasta"))
        if not fasta_files:
            raise ValueError(f"No FASTA files found in {subtype_dir}")
        records = 0
        for fasta in fasta_files:
            header = None
            has_sequence = False
            with fasta.open(encoding="utf-8-sig") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith(">"):
                        if header is not None and not has_sequence:
                            raise ValueError(f"Empty FASTA record in {fasta}: {header!r}")
                        header = line[1:]
                        check_reference_header(header, fasta, expected)
                        has_sequence = False
                        records += 1
                    else:
                        if header is None:
                            raise ValueError(f"Sequence appears before a FASTA header in {fasta}")
                        has_sequence = True
            if header is None or not has_sequence:
                raise ValueError(f"Missing header or empty FASTA record in {fasta}")
        total_files += len(fasta_files)
        print(
            f"OK: {reference_type}/{subtype} -> {expected['Reference']} | "
            f"{expected['GISAID_EPI']} ({len(fasta_files)} FASTA files, {records} records)"
        )
    print(f"Validated {total_files} {reference_type} FASTA files against {table_path}")
    print("Validation checks reference headers, not sequence identity or segment completeness.")


def main():
    if len(sys.argv) != 4:
        print("Usage: validator REFERENCE_TYPE_DIRECTORY TYPE REFERENCE_TABLE", file=sys.stderr)
        return 2
    try:
        validate_reference_type(*sys.argv[1:])
    except (OSError, ValueError, csv.Error, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY_REFERENCE_VALIDATOR
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

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "       $SCRIPT_NAME --check-references REFERENCE_ROOT REFERENCE_TABLE [human|human_vaccine]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r RUN             Specify the run name (e.g., INF077)"
    echo "  -a AGENS           Specify agens (e.g., influensa and avian)"
    echo "  -s SEASON          Specify the season directory (e.g., Ses2526)"
    echo "  -y YEAR            Specify the year directory of the fastq files on the N-drive"
    echo "  -v VALIDATION      Specify validation flag (e.g., VER)"
    echo "  -t                 Suppress Teams notifications for testing (pipeline still runs)"
    echo "  -b BRANCH          Pipeline branch/tag to use (default: master)"
    echo "  -P PATH            PCR JSON file or directory (default: /mnt/tempdata/influensa_db/flu_seq_db/pcr-primers)"
    exit "${1:-1}"
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
VALIDATION_FLAG=""
TEST_MODE=false
PIPELINE_BRANCH="master"
PRIMER_CHECK_PCR="${PRIMER_CHECK_PCR:-/mnt/tempdata/influensa_db/flu_seq_db/pcr-primers}"
PRIMER_CHECK_CONTAINER="${PRIMER_CHECK_CONTAINER:-ghcr.io/rasmuskoriis/primer-checker:latest}"
PRIMER_CHECK_ENABLED="${PRIMER_CHECK_ENABLED:-true}"

while getopts "htr:a:s:y:v:b:P:" opt; do
    case "$opt" in
        h) usage 0 ;;
        t) TEST_MODE=true ;;
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

# Start logging before validation, conda, downloads or repository updates.
# shellcheck source=../resp-virus-toolkit/wrapper_logging.sh
source "$SCRIPT_DIR/../resp-virus-toolkit/wrapper_logging.sh"
wrapper_logs_init fluseq "$RUN"

# Check required arguments
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

# Activate conda after logging is ready so setup failures are retained.
export JAVA_HOME="${JAVA_HOME:-}"
source "${CONDA_PROFILE:-$HOME/miniconda3/etc/profile.d/conda.sh}"

echo "Run: $RUN"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"
echo "Pipeline branch: $PIPELINE_BRANCH"

# -----------------------------
# Make sure the latest version of the ngs_scripts repo is present locally
# -----------------------------

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

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/results"
SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/powerBI"

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
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
elif [ "$YEAR" -lt "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
else
    echo "ERROR: Year cannot be larger than $current_year"
    exit 1
fi

# Create the temporary input root. Nextflow creates the output only after the
# preflight checks have passed.
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
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit || true)
SAMPLESHEET="$TMP_DIR/${RUN}.csv"
FLU_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db
HA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_HA.fasta
NA_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/human_NA.fasta
GENOTYPE_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/H5_genotype_database.fasta
MAMMALIAN_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Mammalian_Mutations_of_Intrest_2324.xlsx
INHIBTION_MUTATION_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/Inhibtion_Mutations_of_Intrest_2324.xlsx
REASSORTMENT_DATABASE=/mnt/tempdata/influensa_db/flu_seq_db/reassortment_database.fasta
SEQUENCE_REFERENCES=/mnt/tempdata/influensa_db/flu_seq_db/sequence_references
NEXTCLADE_DATASET=/mnt/tempdata/influensa_db/flu_seq_db/nextclade_datasets
MUTATION_LITS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/Mutation_lists"
REASSORTMENT_LITS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/"
GENOTYPE_H5_LITS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/"
HUMAN_REFERENCES="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/references/human"
REFERENCE_VALIDATION="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/${SEASON}/references"
HUMAN_VACCINE_REFERENCES="$REFERENCE_VALIDATION/human_vaccine"
REFERENCE_TABLE_LOCAL_FILE="$FLU_DATABASE/reference_table.csv"

if [ -z "$SAMPLEDIR" ]; then
    echo "ERROR: Could not find fastq_pass directory under $TMP_DIR/$RUN"
    exit 1
fi

echo "Updating mutation lists"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$MUTATION_LITS" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE
mget *
EOF

echo "Updating genotyping H5 lists"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$REASSORTMENT_LITS" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE
mget reassortment_database.fasta
EOF

echo "Updating reassortment lists"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$GENOTYPE_H5_LITS" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE
mget H5_genotype_database.fasta
EOF

echo "Updating human references"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$HUMAN_REFERENCES" <<EOF
prompt OFF
recurse ON
lcd $FLU_DATABASE/sequence_references/human
mget *
EOF

echo "Updating human vaccine references"
mkdir -p "$SEQUENCE_REFERENCES/human_vaccine"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$HUMAN_VACCINE_REFERENCES" <<EOF
prompt OFF
recurse ON
lcd $SEQUENCE_REFERENCES/human_vaccine
mget *
EOF

echo "Updating reference table"
rm -f "$REFERENCE_TABLE_LOCAL_FILE"

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$REFERENCE_VALIDATION" <<EOF
prompt OFF
lcd $FLU_DATABASE
mget reference_table.csv
EOF

if [ ! -f "$REFERENCE_TABLE_LOCAL_FILE" ]; then
    echo "ERROR: Could not find $REFERENCE_TABLE_LOCAL_FILE after download."
    exit 1
fi

echo "Using reference table: $REFERENCE_TABLE_LOCAL_FILE"
echo "Checking that downloaded references match reference_table.csv"

validate_reference_type "$SEQUENCE_REFERENCES/human" "human" "$REFERENCE_TABLE_LOCAL_FILE"
validate_reference_type "$SEQUENCE_REFERENCES/human_vaccine" "human_vaccine" "$REFERENCE_TABLE_LOCAL_FILE"

# Create a samplesheet by running the supplied Rscript in a docker container.
# ADD CODE FOR HANDLING OF SAMPLESHEET

for required_file in "$SAMPLESHEET" "$HA_DATABASE" "$NA_DATABASE" "$GENOTYPE_DATABASE" "$INHIBTION_MUTATION_DATABASE" "$REASSORTMENT_DATABASE"; do
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

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow -log "$NEXTFLOW_LOG" pull RasmusKoRiis/nf-core-fluseq -r "$PIPELINE_BRANCH"
wrapper_logs_nextflow_start
nextflow -log "$NEXTFLOW_LOG" -c "$SCRIPT_DIR/../resp-virus-toolkit/wrapper_cleanup.config" \
  run RasmusKoRiis/nf-core-fluseq/main.nf \
  -r "$PIPELINE_BRANCH" \
  -profile docker,server \
  --input "$SAMPLESHEET" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --ha_database "$HA_DATABASE" \
  --na_database "$NA_DATABASE" \
  --genotype_database "$GENOTYPE_DATABASE" \
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

WRAPPER_PHASE="Result preparation and uploads"
wrapper_logs_status "Nextflow finished; moving results to the N: drive"
mkdir -p "$HOME/out_fluseq"
if [ -e "$HOME/out_fluseq/$RUN" ]; then
    PREVIOUS_RESULTS="$HOME/out_fluseq/${RUN}.previous.$(date +%Y%m%dT%H%M%S)"
    echo "Archiving previous local results to $PREVIOUS_RESULTS"
    mv "$HOME/out_fluseq/$RUN" "$PREVIOUS_RESULTS"
fi
mv "$HOME/$RUN" "$HOME/out_fluseq/"

if [ "$SKIP_RESULTS_MOVE" = false ]; then
    wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd "$HOME/out_fluseq"
mput "$RUN"
EOF
fi

wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd "$HOME/out_fluseq/${RUN}/reporthuman"
mput *.csv
EOF

if [ -d "$HOME/out_fluseq/$RUN/primer_check" ]; then
    wrapper_smb_upload "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd "$HOME/out_fluseq/$RUN/primer_check"
mput *.csv
EOF
fi

wrapper_logs_status "Required result uploads completed"
if [ "$SKIP_RESULTS_MOVE" = true ]; then
    wrapper_logs_complete "$HOME/out_fluseq/$RUN" "$SMB_DIR_ANALYSIS" "$TMP_DIR/$RUN" "$SAMPLESHEET" 0
else
    wrapper_logs_complete "$HOME/out_fluseq/$RUN" "$SMB_DIR" "$TMP_DIR/$RUN" "$SAMPLESHEET" 1
fi

# The shared EXIT handler verifies logs and cleans only this run.
