#!/usr/bin/env bash
set -euo pipefail

# Activate conda base functions
CONDA_PROFILE="${CONDA_PROFILE:-$HOME/miniconda3/etc/profile.d/conda.sh}"
if [ -f "$CONDA_PROFILE" ]; then
    source "$CONDA_PROFILE"
elif command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
else
    echo "ERROR: Could not initialize conda."
    echo "Set CONDA_PROFILE=/path/to/conda.sh or make conda available in PATH."
    exit 1
fi

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "  -b <branch>        Pipeline branch/tag to use (default: master)"
    echo "  -o                 Run in offline mode using local cached pipeline/resources"
    echo "  --local-fastq-dir <dir>"
    echo "                     Use a local FASTQ samples directory instead of copying from the N-drive"
    echo "  --local-samplesheet <csv>"
    echo "                     Use a local samplesheet instead of /mnt/tempdata/fastq/<RUN>.csv"
    echo "  --local-fasta <path-or-glob>"
    echo "                     Run the FASTA workflow on local FASTA input instead of the FASTQ workflow"
    echo "  --outdir <dir>     Write this run's pipeline output to an explicit local directory"
    echo ""
    echo "Offline environment overrides:"
    echo "  BASE_DIR                     Local base directory for temp/cache paths (default: /mnt/tempdata)"
    echo "  TMP_DIR                      Local temporary FASTQ directory (default: BASE_DIR/fastq)"
    echo "  SARS_DATABASE                Local DB/resource cache root (default: BASE_DIR/sars_db/assets)"
    echo "  OFFLINE_OUTDIR_BASE          Default offline output base if --outdir is not provided"
    echo "  PIPELINE_DIR                 Local pipeline checkout (default: \$HOME/.nextflow/assets/RasmusKoRiis/nf-core-sars)"
    echo "  OFFLINE_NEXTCLADE_DATASET    Local Nextclade dataset directory"
    echo "  OFFLINE_ARTIC_MODEL_DIR      Local ARTIC/Clair3 model directory"
    echo "  PIPELINE_ASSETS_DIR          Local assets fallback (default: PIPELINE_DIR/assets, then wrapper assets)"
    echo "  CONDA_PROFILE                Conda profile script if not \$HOME/miniconda3/etc/profile.d/conda.sh"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
PRIMER=""
VALIDATION_FLAG=""
PIPELINE_BRANCH="master"
OFFLINE_MODE=false
PIPELINE_DIR="${PIPELINE_DIR:-$HOME/.nextflow/assets/RasmusKoRiis/nf-core-sars}"
LOCAL_FASTQ_DIR="${LOCAL_FASTQ_DIR:-}"
LOCAL_SAMPLESHEET="${LOCAL_SAMPLESHEET:-}"
LOCAL_FASTA="${LOCAL_FASTA:-}"
OUTPUT_DIR="${OUTPUT_DIR:-}"

# Parse options
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        -r|--run) RUN="${2:?Missing value for $1}"; shift 2 ;;
        -p|--primer) PRIMER="${2:?Missing value for $1}"; shift 2 ;;
        -a|--agens) AGENS="${2:?Missing value for $1}"; shift 2 ;;
        -s|--season) SEASON="${2:?Missing value for $1}"; shift 2 ;;
        -y|--year) YEAR="${2:?Missing value for $1}"; shift 2 ;;
        -v|--validation) VALIDATION_FLAG="${2:?Missing value for $1}"; shift 2 ;;
        -b|--branch) PIPELINE_BRANCH="${2:?Missing value for $1}"; shift 2 ;;
        -o|--offline) OFFLINE_MODE=true; shift ;;
        --local-fastq-dir) LOCAL_FASTQ_DIR="${2:?Missing value for $1}"; shift 2 ;;
        --local-samplesheet) LOCAL_SAMPLESHEET="${2:?Missing value for $1}"; shift 2 ;;
        --local-fasta) LOCAL_FASTA="${2:?Missing value for $1}"; shift 2 ;;
        --outdir) OUTPUT_DIR="${2:?Missing value for $1}"; shift 2 ;;
        --) shift; break ;;
        *) echo "ERROR: Unknown option: $1"; usage ;;
    esac
done

if [ -n "$LOCAL_FASTA" ] && { [ -n "$LOCAL_FASTQ_DIR" ] || [ -n "$LOCAL_SAMPLESHEET" ]; }; then
    echo "ERROR: --local-fasta cannot be combined with --local-fastq-dir or --local-samplesheet."
    exit 1
fi

PIPELINE_FILE="fastq-workflow"
if [ -n "$LOCAL_FASTA" ]; then
    PIPELINE_FILE="fasta-workflow"
fi

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
echo "Pipeline branch: ${PIPELINE_BRANCH}"
echo "Offline mode: $OFFLINE_MODE"
echo "Workflow mode: $PIPELINE_FILE"
echo "Local FASTQ dir: ${LOCAL_FASTQ_DIR:-}"
echo "Local samplesheet: ${LOCAL_SAMPLESHEET:-}"
echo "Local FASTA: ${LOCAL_FASTA:-}"
echo "Output dir: ${OUTPUT_DIR:-}"

################################################################################
# Repo sync
################################################################################
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

if [ "$OFFLINE_MODE" = true ]; then
    echo "Offline mode enabled: skipping ngs_scripts git sync."
else
    if [ -d "$REPO" ]; then
        echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
        cd "$REPO"
        git pull
    else
        echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
        git clone "$REPO_URL" "$REPO"
    fi
fi
cd "$HOME"

# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
if [ "$OFFLINE_MODE" = false ]; then
    rm -rf "$HOME/sarsseq"
fi

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

################################################################################
# Environment / SMB
################################################################################
BASE_DIR="${BASE_DIR:-/mnt/tempdata}"
TMP_DIR="${TMP_DIR:-$BASE_DIR/fastq}"
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
SARS_DATABASE="${SARS_DATABASE:-$BASE_DIR/sars_db/assets}"
mkdir -p "$SARS_DATABASE"
if [ -z "${PIPELINE_ASSETS_DIR:-}" ]; then
    if [ -d "$PIPELINE_DIR/assets" ]; then
        PIPELINE_ASSETS_DIR="$PIPELINE_DIR/assets"
    else
        PIPELINE_ASSETS_DIR="$SCRIPT_DIR/assets"
    fi
fi
OFFLINE_BASE="${OFFLINE_BASE:-$SARS_DATABASE/offline}"
OFFLINE_NEXTCLADE_DATASET="${OFFLINE_NEXTCLADE_DATASET:-$OFFLINE_BASE/nextclade/sars-cov-2-wuhan-hu-1-orfs}"
OFFLINE_ARTIC_MODEL_DIR="${OFFLINE_ARTIC_MODEL_DIR:-$OFFLINE_BASE/artic_models}"

REQUIRED_DOCKER_IMAGES_FASTA=(
    "docker.io/rasmuskriis/nextclade-python"
    "docker.io/nextstrain/nextclade:latest"
    "docker.io/rasmuskriis/blast_python_pandas:amd64"
)

REQUIRED_DOCKER_IMAGES_FASTQ=(
    "quay.io/nf-core/ubuntu:20.04"
    "quay.io/biocontainers/chopper:0.9.0--hdcf5f25_0"
    "quay.io/artic/fieldbioinformatics:1.6.0"
    "community.wave.seqera.io/library/artic:1.6.2--d4956cdc155b8612"
    "${REQUIRED_DOCKER_IMAGES_FASTA[@]}"
)

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

# Resolve the first existing file from explicit candidates, then from glob patterns.
resolve_first_file() {
    local dir="$1"
    shift
    local candidates=("$@")
    local c

    for c in "${candidates[@]}"; do
        if [ -f "$dir/$c" ]; then
            echo "$dir/$c"
            return 0
        fi
    done

    # Pattern fallbacks (candidate values that include *)
    for c in "${candidates[@]}"; do
        if [[ "$c" == *"*"* ]]; then
            local found
            found="$(find "$dir" -maxdepth 1 -type f -name "$c" | sort | head -n 1 || true)"
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
    done

    return 1
}

require_file() {
    local path="$1"
    local label="$2"
    if [ ! -f "$path" ]; then
        echo "ERROR: $label not found: $path"
        exit 1
    fi
}

require_dir() {
    local path="$1"
    local label="$2"
    if [ ! -d "$path" ]; then
        echo "ERROR: $label not found: $path"
        exit 1
    fi
}

require_nonempty_dir() {
    local path="$1"
    local label="$2"
    require_dir "$path" "$label"
    if [ "$(find "$path" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ]; then
        echo "ERROR: $label is empty: $path"
        exit 1
    fi
}

require_path_or_glob() {
    local pattern="$1"
    local label="$2"
    if [ -e "$pattern" ]; then
        return 0
    fi
    if compgen -G "$pattern" >/dev/null; then
        return 0
    fi
    echo "ERROR: $label not found: $pattern"
    exit 1
}

resolve_asset_file() {
    local relative_path="$1"
    local label="$2"
    local server_path="$SARS_DATABASE/$relative_path"
    local repo_path="$PIPELINE_ASSETS_DIR/$relative_path"

    if [ -f "$server_path" ]; then
        echo "$server_path"
        return 0
    fi
    if [ -f "$repo_path" ]; then
        echo "$repo_path"
        return 0
    fi

    echo "ERROR: $label not found in server cache or repo assets:" >&2
    echo "  - $server_path" >&2
    echo "  - $repo_path" >&2
    exit 1
}

resolve_asset_dir() {
    local relative_path="$1"
    local label="$2"
    local server_path="$SARS_DATABASE/$relative_path"
    local repo_path="$PIPELINE_ASSETS_DIR/$relative_path"

    if [ -d "$server_path" ]; then
        echo "$server_path"
        return 0
    fi
    if [ -d "$repo_path" ]; then
        echo "$repo_path"
        return 0
    fi

    echo "ERROR: $label not found in server cache or repo assets:" >&2
    echo "  - $server_path" >&2
    echo "  - $repo_path" >&2
    exit 1
}

SPIKE_TABLE="$(resolve_asset_file "Spike_mAbs_inhibitors.csv" "Spike lookup table")"
RDRP_TABLE="$(resolve_asset_file "RdRP_inhibitors.csv" "RdRP lookup table")"
CLPRO_TABLE="$(resolve_asset_file "3CLpro_inhibitors.csv" "3CLpro lookup table")"

preflight_offline_mode() {
    echo "Running offline preflight checks"

    require_file "$PIPELINE_DIR/main.nf" "Local pipeline main.nf"
    if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then
        require_path_or_glob "$LOCAL_FASTA" "Local FASTA input"
    else
        require_file "$SAMPLESHEET" "Samplesheet"
        if [ -z "$SAMPLEDIR" ]; then
            echo "ERROR: Sample FASTQ directory could not be resolved for offline mode."
            exit 1
        fi
        require_dir "$SAMPLEDIR" "Sample FASTQ directory"
        require_nonempty_dir "$OFFLINE_ARTIC_MODEL_DIR" "Offline ARTIC model directory"
    fi
    require_nonempty_dir "$OFFLINE_NEXTCLADE_DATASET" "Offline Nextclade dataset directory"
    require_file "$SPIKE_TABLE" "Spike lookup table"
    require_file "$RDRP_TABLE" "RdRP lookup table"
    require_file "$CLPRO_TABLE" "3CLpro lookup table"

    local nextflow_plugin_dir="${NXF_HOME:-$HOME/.nextflow}/plugins"
    if ! find "$nextflow_plugin_dir" -maxdepth 4 -iname '*nf-schema*2.5.1*' 2>/dev/null | grep -q .; then
        echo "ERROR: nf-schema@2.5.1 was not found in the local Nextflow plugin cache."
        echo "Checked: $nextflow_plugin_dir"
        echo "Run the pipeline once online, or install/cache nf-schema@2.5.1 before offline use."
        exit 1
    fi

    local missing_images=()
    local required_images=()
    local image
    if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then
        required_images=("${REQUIRED_DOCKER_IMAGES_FASTA[@]}")
    else
        required_images=("${REQUIRED_DOCKER_IMAGES_FASTQ[@]}")
    fi
    for image in "${required_images[@]}"; do
        if ! docker image inspect "$image" >/dev/null 2>&1; then
            missing_images+=("$image")
        fi
    done

    if [ "${#missing_images[@]}" -gt 0 ]; then
        echo "ERROR: Missing Docker images required for offline mode:"
        printf '  - %s\n' "${missing_images[@]}"
        echo "Pull these images while online before running with -o."
        exit 1
    fi
}

################################################################################
# DB locations
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
if [ -z "$OUTPUT_DIR" ] && [ "$OFFLINE_MODE" = true ] && [ -n "${OFFLINE_OUTDIR_BASE:-}" ]; then
    OUTPUT_DIR="$OFFLINE_OUTDIR_BASE/$RUN"
fi

NEXTFLOW_OUTDIR="${OUTPUT_DIR:-$HOME/$RUN}"

mkdir -p "$NEXTFLOW_OUTDIR"
mkdir -p "$TMP_DIR"
CLEAN_TMP=true
if [ "$PIPELINE_FILE" = "fasta-workflow" ] || [ -n "$LOCAL_FASTQ_DIR" ]; then
    CLEAN_TMP=false
fi

# Clean TMP on exit
cleanup() {
    echo "Cleaning up temporary data..."
    nextflow clean -f >/dev/null 2>&1 || true
    if [ "$CLEAN_TMP" = true ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

################################################################################
# Copy fastq files from storage
################################################################################
if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then
    echo "Local FASTA input provided; skipping FASTQ copy from the N drive."
elif [ -n "$LOCAL_FASTQ_DIR" ]; then
    echo "Local FASTQ directory provided; skipping FASTQ copy from the N drive."
else
    echo "Copying fastq files from the N drive"
    smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" <<EOF
prompt OFF
recurse ON
lcd "$TMP_DIR"
mget *
EOF
fi

################################################################################
# Locate sample dir & samplesheet
################################################################################
if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then
    SAMPLEDIR=""
    SAMPLESHEET=""
elif [ -n "$LOCAL_FASTQ_DIR" ]; then
    SAMPLEDIR="$LOCAL_FASTQ_DIR"
    SAMPLESHEET="${LOCAL_SAMPLESHEET:-/mnt/tempdata/fastq/${RUN}.csv}"
else
    SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit 2>/dev/null || true)
    SAMPLESHEET="${LOCAL_SAMPLESHEET:-/mnt/tempdata/fastq/${RUN}.csv}"
fi

if [ "$PIPELINE_FILE" = "fastq-workflow" ] && [ -z "${SAMPLEDIR}" ]; then
    echo "WARNING: Could not find fastq_pass directory under $TMP_DIR/$RUN"
    echo "         SAMPLEDIR is empty; pipeline may fail unless this is expected."
fi

echo "Pipeline input FASTQ dir : ${SAMPLEDIR:-}"
echo "Pipeline input samplesheet: ${SAMPLESHEET:-}"
echo "Pipeline input FASTA     : ${LOCAL_FASTA:-}"
echo "Spike lookup table       : $SPIKE_TABLE"
echo "RdRP lookup table        : $RDRP_TABLE"
echo "3CLpro lookup table      : $CLPRO_TABLE"

################################################################################
# Update DB cache from storage (download)
################################################################################
if [ "$OFFLINE_MODE" = true ]; then
    echo "Offline mode enabled: skipping DB cache download from storage."
else
    echo "Updating DB cache from storage"
    download_db "$PRIMERDB"   "$SARS_DATABASE"
    download_db "$AMPLICONDB" "$SARS_DATABASE"
fi

################################################################################
# TODO: Create samplesheet
################################################################################
# Create a samplesheet by running the supplied Rscript in a docker container.
# ADD CODE FOR HANDLING OF SAMPLESHEET

################################################################################
# Validate primer dir and resolve files before pipeline run
################################################################################
PRIMER_DIR=""
BED_LOCAL=""
REF_LOCAL=""

if [ "$PIPELINE_FILE" = "fastq-workflow" ] && [ -z "${PRIMER}" ]; then
    echo "ERROR: -p <primer> is required for this pipeline."
    exit 1
fi

if [ "$PIPELINE_FILE" = "fastq-workflow" ]; then
    PRIMER_DIR="$(resolve_asset_dir "$PRIMER" "Primer directory")"

    # Prefer canonical names, then fallback globs.
    BED_LOCAL="$(resolve_first_file "$PRIMER_DIR" \
        "SARS-CoV-2.scheme.bed" \
        "ncov-2019_midnight.scheme.bed" \
        "*.scheme.bed" \
        "*.bed" || true)"

    REF_LOCAL="$(resolve_first_file "$PRIMER_DIR" \
        "SARS-CoV-2.reference.fasta" \
        "ncov-2019_midnight.reference.fasta" \
        "*.reference.fasta" || true)"

    if [ -z "$BED_LOCAL" ] || [ ! -f "$BED_LOCAL" ]; then
        echo "ERROR: Could not resolve primer BED file in $PRIMER_DIR"
        echo "Expected one of: SARS-CoV-2.scheme.bed, *.scheme.bed, or *.bed"
        exit 1
    fi

    if [ -z "$REF_LOCAL" ] || [ ! -f "$REF_LOCAL" ]; then
        echo "ERROR: Could not resolve reference FASTA in $PRIMER_DIR"
        echo "Expected one of: SARS-CoV-2.reference.fasta or *.reference.fasta"
        exit 1
    fi

    echo "Using primer dir : $PRIMER_DIR"
    echo "Using primer bed : $BED_LOCAL"
    echo "Using reference  : $REF_LOCAL"
else
    require_path_or_glob "$LOCAL_FASTA" "Local FASTA input"
fi

if [ "$OFFLINE_MODE" = true ]; then
    preflight_offline_mode
fi

################################################################################
# Run Nextflow pipeline
################################################################################
# Fix for conda activation scripts that reference JAVA_HOME while set -u is active
export JAVA_HOME="${JAVA_HOME:-}"

# Temporarily disable nounset because some conda activate scripts break on unset vars
set +u
conda activate NEXTFLOW
set -u

echo "Map to references and create consensus sequences"
NEXTFLOW_SOURCE="RasmusKoRiis/nf-core-sars/main.nf"
NEXTFLOW_REV_ARGS=(-r "$PIPELINE_BRANCH")
NEXTFLOW_OFFLINE_ARGS=()
NEXTFLOW_INPUT_ARGS=(
    --file "$PIPELINE_FILE"
)

if [ "$PIPELINE_FILE" = "fasta-workflow" ]; then
    NEXTFLOW_INPUT_ARGS+=(
        --fasta "$LOCAL_FASTA"
    )
else
    NEXTFLOW_INPUT_ARGS+=(
        --input "$SAMPLESHEET"
        --samplesDir "$SAMPLEDIR"
        --primerdir "$PRIMER_DIR"
        --reference "$REF_LOCAL"
        --primer_bed "$BED_LOCAL"
    )
fi

if [ "$OFFLINE_MODE" = true ]; then
    export NXF_OFFLINE=true
    NEXTFLOW_SOURCE="$PIPELINE_DIR/main.nf"
    NEXTFLOW_REV_ARGS=()
    NEXTFLOW_OFFLINE_ARGS=(
        --offline
        --igenomes_ignore
        --nextclade_dataset "$OFFLINE_NEXTCLADE_DATASET"
        --artic_model_dir "$OFFLINE_ARTIC_MODEL_DIR"
    )
    echo "Offline mode enabled: skipping nextflow pull."
    echo "Using local pipeline: $NEXTFLOW_SOURCE"
else
    nextflow pull RasmusKoRiis/nf-core-sars -r "$PIPELINE_BRANCH"
fi

nextflow run "$NEXTFLOW_SOURCE" \
    "${NEXTFLOW_REV_ARGS[@]}" \
    -profile docker,server \
    "${NEXTFLOW_INPUT_ARGS[@]}" \
    --outdir "$NEXTFLOW_OUTDIR" \
    --runid "$RUN" \
    --spike "$SPIKE_TABLE" \
    --rdrp "$RDRP_TABLE" \
    --clpro "$CLPRO_TABLE" \
    --release_version "v1.0.0" \
    "${NEXTFLOW_OFFLINE_ARGS[@]}"

################################################################################
# Move results locally into out_sarsseq
################################################################################
if [ -n "$OUTPUT_DIR" ]; then
    RUN_OUT="$OUTPUT_DIR"
    echo "Results written to explicit output directory: $RUN_OUT"
else
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
fi

################################################################################
# Merge per-run primer+amplicon outputs into cached DBs, then upload back to storage
################################################################################
if [ "$OFFLINE_MODE" = true ]; then
    echo "Offline mode enabled: skipping dashboard DB merge/upload and N-drive result upload."
    echo "Done. Results are in: $RUN_OUT"
    exit 0
fi

# --- Primer mismatches: merge per-run CSVs -> append into master -> upload ---
primer_files=()
while IFS= read -r -d '' f; do
    primer_files+=("$f")
done < <(
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
depth_files=()
while IFS= read -r -d '' f; do
    depth_files+=("$f")
done < <(
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
