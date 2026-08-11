#!/usr/bin/env bash
# Routine influenza IQ-TREE/TreeTime analysis using the production SMB wrapper pattern.

set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# --- Conda ---
CONDA_SH="${HOME}/miniconda3/etc/profile.d/conda.sh"
[[ -f "$CONDA_SH" ]] || die "Conda initialization script not found: $CONDA_SH"
# shellcheck disable=SC1090
source "$CONDA_SH"

# --- Date ---
DATE="$(date +%Y-%m-%d)"
RUN_NAME="${DATE}_IQtree_Build"

# --- Paths / SMB ---
BASE_DIR="/mnt/tempdata"
TMP_DIR="${BASE_DIR}/flu_iqtree"
OUT_DIR="${BASE_DIR}/flu_iqtree_out"
PREPARED_METADATA_DIR="${TMP_DIR}/prepared_metadata"

SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"
SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/13-IQtree"
SMB_DIR_ANALYSIS="${SMB_DIR}/${RUN_NAME}"

# --- Repos / analysis ---
NGS_SCRIPTS_DIR="${HOME}/ngs_scripts"
NGS_SCRIPTS_REMOTE="https://github.com/folkehelseinstituttet/ngs_scripts.git"
IQTREE_ANALYSIS_DIR="${NGS_SCRIPTS_DIR}/respiratory-virus-surveillance/IQ-tree-analysis"
IQTREE_RUNNER="${IQTREE_ANALYSIS_DIR}/scripts/run_alignments_and_phylo.sh"
XLS_TO_CSV="${NGS_SCRIPTS_DIR}/nextstrain/influenza/global/xls2csv.py"
CONDA_ENV="viral-phylo-iqtree-treetime"

# The SMB input directory follows the existing influenza wrapper layout:
#   13-IQtree/H1/{metadata.*,*.fasta}
#   13-IQtree/H3/{metadata.*,*.fasta}
#   13-IQtree/VIC/{metadata.*,*.fasta}
INPUT_GROUPS=(H1 H3 VIC)
declare -a PROCESSED_INPUTS=()

# --- Ensure clean local working directories exist ---
# These are dedicated scratch paths. Clearing them prevents a failed or older run
# from being mixed into the current analysis and upload.
rm -rf -- "$TMP_DIR" "$OUT_DIR"
mkdir -p "$TMP_DIR" "$OUT_DIR" "$PREPARED_METADATA_DIR" "$BASE_DIR"

require_command git
require_command smbclient

# --- Pull/update the helper repository containing the IQ-TREE workflow ---
if [[ -d "$NGS_SCRIPTS_DIR/.git" ]]; then
  git -C "$NGS_SCRIPTS_DIR" pull --ff-only origin main
else
  git clone "$NGS_SCRIPTS_REMOTE" "$NGS_SCRIPTS_DIR"
fi

[[ -f "$IQTREE_RUNNER" ]] || die "IQ-TREE workflow runner not found: $IQTREE_RUNNER"

# --- Pull input files from SMB to TMP_DIR ---
log "Fetching inputs from ${SMB_HOST}/${SMB_DIR}"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget H1
mget H3
mget VIC
EOF

# --- Activate analysis environment ---
conda activate "$CONDA_ENV"
require_command python3

find_metadata_file() {
  local input_dir=$1
  local candidate=""
  local extension

  for extension in csv tsv txt xlsx xls; do
    candidate=$(find "$input_dir" -maxdepth 1 -type f -iname "metadata.${extension}" -print -quit)
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

prepare_metadata() {
  local input_dir=$1
  local group=$2
  local metadata=""
  local converted_metadata="${PREPARED_METADATA_DIR}/${group}.metadata.csv"

  metadata=$(find_metadata_file "$input_dir") || \
    die "$group is missing metadata.csv, metadata.tsv, metadata.txt, metadata.xlsx, or metadata.xls in $input_dir"

  case "${metadata,,}" in
    *.xlsx|*.xls)
      [[ -f "$XLS_TO_CSV" ]] || die "Excel metadata converter not found: $XLS_TO_CSV"
      log "Converting $group metadata to CSV: $metadata"
      python3 "$XLS_TO_CSV" --xls "$metadata" --output "$converted_metadata"
      printf '%s\n' "$converted_metadata"
      ;;
    *)
      printf '%s\n' "$metadata"
      ;;
  esac
}

# --- Run the IQ-TREE analysis for each influenza lineage ---
cd "$IQTREE_ANALYSIS_DIR"

for group in "${INPUT_GROUPS[@]}"; do
  input_dir="${TMP_DIR}/${group}"
  [[ -d "$input_dir" ]] || die "Expected input directory was not downloaded: $input_dir"

  mapfile -t fasta_files < <(
    find "$input_dir" -maxdepth 1 -type f \
      \( -iname '*.fa' -o -iname '*.fasta' -o -iname '*.fna' -o -iname '*.fas' \) \
      | sort
  )
  [[ "${#fasta_files[@]}" -gt 0 ]] || die "No FASTA files found for $group in $input_dir"

  source_metadata=$(find_metadata_file "$input_dir") || die "Could not identify source metadata for $group"
  metadata=$(prepare_metadata "$input_dir" "$group")
  group_outdir="${OUT_DIR}/${group}"

  # Keep an exact copy of every input used by this group in the dated result.
  input_archive_dir="${OUT_DIR}/input_data/${group}"
  mkdir -p "$input_archive_dir"
  cp "$source_metadata" "$input_archive_dir/"
  source_metadata_name=$(basename "$source_metadata")
  [[ "$source_metadata_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "Unsupported metadata filename for safe SMB deletion: $source_metadata_name"
  PROCESSED_INPUTS+=("${group}:${source_metadata_name}")
  for fasta in "${fasta_files[@]}"; do
    fasta_name=$(basename "$fasta")
    [[ "$fasta_name" =~ ^[A-Za-z0-9._-]+$ ]] || die "Unsupported FASTA filename for safe SMB deletion: $fasta_name"
    cp "$fasta" "$input_archive_dir/"
    PROCESSED_INPUTS+=("${group}:${fasta_name}")
  done

  log "Running IQ-TREE workflow for $group (${#fasta_files[@]} FASTA file(s))"
  bash "$IQTREE_RUNNER" \
    --fasta-dir "$input_dir" \
    --metadata "$metadata" \
    --metadata-format default \
    --outdir "$group_outdir" \
    --alignment-method mafft \
    --display-columns auto
done

NGS_SCRIPTS_COMMIT=$(git -C "$NGS_SCRIPTS_DIR" rev-parse HEAD)
{
  printf 'field\tvalue\n'
  printf 'run_name\t%s\n' "$RUN_NAME"
  printf 'run_date\t%s\n' "$DATE"
  printf 'source\t%s/%s\n' "$SMB_HOST" "$SMB_DIR"
  printf 'destination\t%s/%s\n' "$SMB_HOST" "$SMB_DIR_ANALYSIS"
  printf 'ngs_scripts_commit\t%s\n' "$NGS_SCRIPTS_COMMIT"
  printf 'conda_environment\t%s\n' "$CONDA_ENV"
} >"${OUT_DIR}/run_manifest.tsv"

# --- Create the dated SMB result directory and upload all results ---
if smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" -c 'pwd' >/dev/null 2>&1; then
  log "Using existing SMB result directory: ${SMB_DIR_ANALYSIS}"
else
  log "Creating SMB result directory: ${SMB_DIR_ANALYSIS}"
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
mkdir $RUN_NAME
EOF
fi

log "Uploading results to ${SMB_HOST}/${SMB_DIR_ANALYSIS}"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

# Delete only the files copied into input_data above, and only after the upload
# completed successfully. Empty lineage directories are removed afterwards.
delete_commands="prompt OFF; recurse OFF;"
for processed_input in "${PROCESSED_INPUTS[@]}"; do
  IFS=: read -r processed_group processed_name <<<"$processed_input"
  delete_commands+=" cd ${processed_group}; rm ${processed_name}; cd ..;"
done
for group in "${INPUT_GROUPS[@]}"; do
  delete_commands+=" rmdir ${group};"
done
log "Removing successfully transferred source inputs from ${SMB_HOST}/${SMB_DIR}"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" -c "$delete_commands"

# --- Clean up downloaded inputs; keep OUT_DIR for local inspection ---
rm -rf -- "$TMP_DIR"

log "Done. Local results remain in $OUT_DIR"
