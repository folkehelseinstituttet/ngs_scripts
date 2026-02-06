#!/usr/bin/env bash
set -euo pipefail

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r <run>           Specify the run name (e.g., INF077) (required)"
    echo "  -p <primer>        Specify the primer version (e.g., V5.4.2)"
    echo "  -a <agens>         Specify agens (e.g., sars) (required)"
    echo "  -s <season>        Specify the season directory of the fastq files on the N-drive (e.g., Ses2425)"
    echo "  -y <year>          Specify the year directory of the fastq files on the N-drive (required)"
    echo "  -v <validation>    Specify validation flag (e.g., VER)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
PRIMER=""
VALIDATION_FLAG=""

# Parse options
while getopts "hr:p:a:s:y:v:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        p) PRIMER="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        ?) usage ;;
    esac
done

# Basic validation
if [ -z "${RUN}" ] || [ -z "${AGENS}" ] || [ -z "${YEAR}" ]; then
  echo "ERROR: -r <run>, -a <agens>, and -y <year> are required."
  usage
fi

echo "Run: $RUN"
echo "Primer: ${PRIMER:-}"
echo "Agens: $AGENS"
echo "Season: ${SEASON:-}"
echo "Year: $YEAR"
echo "Validation Flag: ${VALIDATION_FLAG:-}"

################################################################################
# Repo sync
################################################################################
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

# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
rm -rf "$HOME/sarsseq"

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

################################################################################
# Environment / SMB
################################################################################
BASE_DIR="/mnt/tempdata"
TMP_DIR="/mnt/tempdata/fastq"
SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"

# Where to put results on storage (default)
SMB_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/${YEAR}"

# If validation flag is set, update analysis dir and skip full results move step
if [ -n "${VALIDATION_FLAG}" ]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-Validering/1-sarsseq-validering/Run"
    SKIP_RESULTS_MOVE=true
else
    SKIP_RESULTS_MOVE=false
fi

# Input fastq dir on storage
current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
elif [ "$YEAR" -lt "$current_year" ]; then
    SMB_INPUT="Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}"
else
    echo "Error: Year cannot be larger than $current_year"
    exit 1
fi

################################################################################
# Helper functions
################################################################################
SARS_DATABASE="/mnt/tempdata/sars_db/assets"
mkdir -p "$SARS_DATABASE"

download_db() {
  local remote_path="$1"
  local local_dir="$2"
  local base
  base="$(basename "$remote_path")"

  echo "Downloading DB: $remote_path -> $local_dir/$base"
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$(dirname "$remote_path")" <<EOF
prompt OFF
lcd "$local_dir"
mget "$base"
EOF
}

upload_db() {
  local local_file="$1"
  local remote_path="$2"
  local base
  base="$(basename "$remote_path")"

  echo "Uploading DB: $local_file -> $remote_path"
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$(dirname "$remote_path")" <<EOF
prompt OFF
lcd "$(dirname "$local_file")"
mput "$base"
EOF
}

# Concatenate many CSVs into one, keeping header only once
cat_csv_keep_header() {
  local out="$1"; shift
  local files=("$@")

  if [ "${#files[@]}" -eq 0 ]; then
    echo "No files provided to cat_csv_keep_header for $out"
    return 0
  fi

  head -n 1 "${files[0]}" > "$out"
  for f in "${files[@]}"; do
    tail -n +2 "$f" >> "$out" || true
  done
}

# Append NEW rows into MASTER, keep master's header, dedup by exact line
append_dedup() {
  local master="$1"
  local newfile="$2"

  if [ ! -s "$newfile" ]; then
    echo "No new data in $newfile"
    return 0
  fi

  if [ ! -f "$master" ] || [ ! -s "$master" ]; then
    echo "Master missing/empty -> using newfile as master: $master"
    cp "$newfile" "$master"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  head -n 1 "$master" > "$tmp"
  {
    tail -n +2 "$master" || true
    tail -n +2 "$newfile" || true
  } | awk '!seen[$0]++' >> "$tmp"

  mv "$tmp" "$master"
}

################################################################################
# DB locations (FIXED: primer_mismatches vs depth_by_position)
################################################################################
# Storage (N-drive via SMB)
PRIMERDB="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/6-SARS-CoV-2_NGS_Dashboard_DB/Primer_overview/primer_mismatches.csv"
AMPLICONDB="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/6-SARS-CoV-2_NGS_Dashboard_DB/Amplikon_overview/depth_by_position.csv"

# Server cache
PRIMER_DATABASE_SERVER="$SARS_DATABASE/primer_mismatches.csv"
AMPLICON_DATABASE_SERVER="$SARS_DATABASE/depth_by_position.csv"

################################################################################
# Prepare run dirs
################################################################################
mkdir -p "$HOME/$RUN"
mkdir -p "$TMP_DIR"

# Clean TMP on exit
cleanup() {
  echo "Cleaning up temporary data..."
  nextflow clean -f >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

################################################################################
# Copy fastq files from storage
################################################################################
echo "Copying fastq files from the N drive"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd "$TMP_DIR"
mget *
EOF

################################################################################
# Locate sample dir & samplesheet
################################################################################
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit 2>/dev/null || true)
SAMPLESHEET="/mnt/tempdata/fastq/${RUN}.csv"

if [ -z "${SAMPLEDIR}" ]; then
  echo "WARNING: Could not find fastq_pass directory under $TMP_DIR/$RUN"
  echo "         SAMPLEDIR is empty; pipeline may fail unless this is expected."
fi

################################################################################
# Update DB cache from storage (download)
################################################################################
echo "Updating DB cache from storage"
download_db "$PRIMERDB"   "$SARS_DATABASE"
download_db "$AMPLICONDB" "$SARS_DATABASE"

################################################################################
# TODO: Create samplesheet (your existing plan)
################################################################################
# Create a samplesheet by running the supplied Rscript in a docker container.
# ADD CODE FOR HANDLING OF SAMPLESHEET

################################################################################
# Run Nextflow pipeline
################################################################################
conda activate NEXTFLOW

echo "Map to references and create consensus sequences"
nextflow pull RasmusKoRiis/nf-core-sars

nextflow run RasmusKoRiis/nf-core-sars/main.nf \
  -r master \
  -profile docker,server \
  --input "$SAMPLESHEET" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --primerdir "$SARS_DATABASE/$PRIMER" \
  --reference  "$SARS_DATABASE/primer_schemes/ncov-2019_midnight/v3.0.0/ncov-2019_midnight.reference.fasta" \
  --primer_bed "$SARS_DATABASE/primer_schemes/ncov-2019_midnight/v3.0.0/ncov-2019_midnight.scheme.bed" \
  --runid "$RUN" \
  --spike "$SARS_DATABASE/Spike_mAbs_inhibitors.csv" \
  --rdrp "$SARS_DATABASE/RdRP_inhibitors.csv" \
  --clpro "$SARS_DATABASE/3CLpro_inhibitors.csv" \
  --release_version "v1.0.0"

################################################################################
# Move results locally into out_sarsseq
################################################################################
echo "Staging results locally in $HOME/out_sarsseq"
mkdir -p "$HOME/out_sarsseq"

# Your pipeline writes to $HOME/$RUN as outdir. Keep your existing behavior:
# Move the run dir into out_sarsseq.
# If it already exists, fail loudly to avoid mixing runs.
if [ -e "$HOME/out_sarsseq/$RUN" ]; then
  echo "ERROR: $HOME/out_sarsseq/$RUN already exists. Remove it or choose a different run id."
  exit 1
fi

mv "$HOME/$RUN" "$HOME/out_sarsseq/"

RUN_OUT="$HOME/out_sarsseq/$RUN"

################################################################################
# Merge per-run primer+amplicon outputs into cached DBs, then upload back to storage
################################################################################

# --- Primer mismatches: merge per-run CSVs -> append into master -> upload ---
primer_files=()
while IFS= read -r -d '' f; do primer_files+=("$f"); done < <(
  find "$RUN_OUT/primer_metrics" -maxdepth 1 -type f -name "*SC2_primer_mismatches.csv" -print0 2>/dev/null || true
)

if [ "${#primer_files[@]}" -gt 0 ]; then
  primer_run_merged="$SARS_DATABASE/${RUN}_primer_mismatches_merged.csv"
  echo "Merging primer mismatch CSVs for run: $RUN"
  cat_csv_keep_header "$primer_run_merged" "${primer_files[@]}"

  echo "Appending run primer mismatches into master DB: $PRIMER_DATABASE_SERVER"
  append_dedup "$PRIMER_DATABASE_SERVER" "$primer_run_merged"

  echo "Uploading updated primer mismatch DB back to storage"
  upload_db "$PRIMER_DATABASE_SERVER" "$PRIMERDB"
else
  echo "No primer mismatch CSVs found in $RUN_OUT/primer_metrics"
fi

# --- Depth by position / amplicon DB: locate run outputs -> merge -> append -> upload ---
# Adjust this pattern if your pipeline uses a different filename.
depth_files=()
while IFS= read -r -d '' f; do depth_files+=("$f"); done < <(
  find "$RUN_OUT/depth" -maxdepth 1 -type f -name "*depth_by_position*.csv" -print0 2>/dev/null || true
)

if [ "${#depth_files[@]}" -gt 0 ]; then
  depth_run_merged="$SARS_DATABASE/${RUN}_depth_by_position_merged.csv"
  echo "Merging depth-by-position CSVs for run: $RUN"
  cat_csv_keep_header "$depth_run_merged" "${depth_files[@]}"

  echo "Appending run depth-by-position into master DB: $AMPLICON_DATABASE_SERVER"
  append_dedup "$AMPLICON_DATABASE_SERVER" "$depth_run_merged"

  echo "Uploading updated depth-by-position DB back to storage"
  upload_db "$AMPLICON_DATABASE_SERVER" "$AMPLICONDB"
else
  echo "No depth-by-position CSVs found in $RUN_OUT/depth (pattern: *depth_by_position*.csv)"
  echo "If your pipeline uses a different name/location, update the find() pattern."
fi

################################################################################
# Move results to storage (full run) OR validation CSV-only
################################################################################
echo "Moving results to the N: drive"

if [ "$SKIP_RESULTS_MOVE" = false ]; then
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd "$HOME/out_sarsseq/"
mput *
EOF
fi

if [ "$SKIP_RESULTS_MOVE" = true ]; then
  smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
lcd "$HOME/out_sarsseq/$RUN/report/"
cd ${SMB_DIR_ANALYSIS}
mput *.csv
EOF
fi

echo "Done."
