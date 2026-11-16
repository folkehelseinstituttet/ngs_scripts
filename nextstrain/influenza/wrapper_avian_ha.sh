#!/usr/bin/env bash
# HA-only Nextstrain build for an already prepared GISAID TSV and HA FASTA.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$HOME/Coding/CODEX-projects/nextstrain_avian}"
AVIAN_REPO="${AVIAN_REPO:-$PROJECT_DIR/avian-flu}"
RUN_ROOT="${RUN_ROOT:-$HOME/avianflu_ha_runs}"
CONDA_ENV="${CONDA_ENV-SNAKEMAKE}"
CORES="${CORES:-$(nproc)}"
SMB_HOST="${SMB_HOST:-//pos1-fhi-svm01.fhi.no/styrt}"
SMB_AUTH="${SMB_AUTH:-$HOME/.smbcreds}"
SMB_SOURCE="${SMB_SOURCE:-Virologi/NGS/tmp/avianflu_nextstrain}"
SMB_PARENT="${SMB_PARENT:-Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain}"
MODE=build
USE_SMB=false
UPLOAD=false
INPUTS=()

usage() {
    cat <<'EOF'
Usage: wrapper_avian_ha.sh [options] [metadata.tsv sequences_ha.fasta]

With no paths, use ~/Coding/CODEX-projects/nextstrain_avian/data/gisaid/.
Only H5N1 HA is built; the existing minimum date of 2024 is retained.

  --prepare-only  Validate and prepare inputs without needing Nextstrain
  --dry-run       Prepare a separate run and check the Snakemake job graph
  --smb           Download metadata.tsv and sequences_ha.fasta from SMB
  --upload        Upload only the completed HA JSON to a new SMB run folder
  -h, --help      Show this help

Environment: PROJECT_DIR, AVIAN_REPO, RUN_ROOT, CONDA_ENV, CORES,
             SMB_HOST, SMB_AUTH, SMB_SOURCE, SMB_PARENT.
Set CONDA_ENV='' to use tools already on PATH.
Each invocation creates a new directory under RUN_ROOT (~/avianflu_ha_runs).
Source files and the source avian-flu checkout are never modified.
EOF
}
die() { echo "Error: $*" >&2; exit 1; }
require() { command -v "$1" >/dev/null || die "Required command not found: $1"; }

while (($#)); do
    case "$1" in
        --prepare-only) MODE=prepare ;;
        --dry-run) MODE=dry-run ;;
        --smb) USE_SMB=true ;;
        --upload) UPLOAD=true ;;
        -h|--help) usage; exit 0 ;;
        --*) die "Unknown option: $1" ;;
        *) INPUTS+=("$1") ;;
    esac
    shift
done
[[ ${#INPUTS[@]} == 0 || ${#INPUTS[@]} == 2 ]] || die "Supply both metadata.tsv and sequences_ha.fasta."
if $USE_SMB && ((${#INPUTS[@]})); then die "Use either local paths or --smb."; fi
[[ "$CORES" =~ ^[1-9][0-9]*$ ]] || die "CORES must be a positive integer."
require python3

mkdir -p "$RUN_ROOT"
RUN_DIR="$(mktemp -d "$RUN_ROOT/$(date +%F_%H%M%S)_XXXXXX")"
echo "Run directory: $RUN_DIR"
trap 'echo "Run failed; files and logs are retained in $RUN_DIR" >&2' ERR

if $USE_SMB; then
    require smbclient
    mkdir "$RUN_DIR/downloads"
    # Download precisely the two expected inputs, without recursive wildcards.
    (
        cd "$RUN_DIR/downloads"
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SOURCE" \
            -c 'get metadata.tsv; get sequences_ha.fasta'
    )
    META="$RUN_DIR/downloads/metadata.tsv"
    FASTA="$RUN_DIR/downloads/sequences_ha.fasta"
elif ((${#INPUTS[@]})); then
    META="${INPUTS[0]}"
    FASTA="${INPUTS[1]}"
else
    META="$PROJECT_DIR/data/gisaid/metadata.tsv"
    FASTA="$PROJECT_DIR/data/gisaid/sequences_ha.fasta"
fi
[[ -s "$META" ]] || die "Metadata missing or empty: $META"
[[ -s "$FASTA" ]] || die "HA FASTA missing or empty: $FASTA"
python3 "$SCRIPT_DIR/avian_flu/prepare_ha_inputs.py" "$META" "$FASTA" "$RUN_DIR/local_data"
if [[ "$MODE" == prepare ]]; then
    echo "Inputs prepared: $RUN_DIR/local_data"
    exit 0
fi

if [[ -n "$CONDA_ENV" ]]; then
    CONDA_SH="${CONDA_SH:-$HOME/miniconda3/etc/profile.d/conda.sh}"
    [[ -f "$CONDA_SH" ]] || die "Cannot find $CONDA_SH; activate your environment and set CONDA_ENV=''."
    source "$CONDA_SH"
    conda activate "$CONDA_ENV"
fi
require snakemake
require augur
[[ -f "$AVIAN_REPO/rules/config.smk" ]] || die "Set AVIAN_REPO to a complete Nextstrain avian-flu checkout."

# Copy workflow resources only; do not reset/update the source repository or
# reuse outputs from previous analyses. Use upstream rules, not the older
# whole-genome overlay, which uses a different config-path API.
for directory in rules shared scripts config clade-labeling; do
    [[ -d "$AVIAN_REPO/$directory" ]] || die "Missing workflow directory: $AVIAN_REPO/$directory"
    cp -R "$AVIAN_REPO/$directory" "$RUN_DIR/"
done
if [[ -f "$AVIAN_REPO/nextstrain-pathogen.yaml" ]]; then
    cp "$AVIAN_REPO/nextstrain-pathogen.yaml" "$RUN_DIR/"
fi
cp -R "$SCRIPT_DIR/avian_flu/ha-focused" "$RUN_DIR/"
mkdir -p "$RUN_DIR/config/local-ha"
# An empty list prevents force-inclusion of unrelated reference strains.
: > "$RUN_DIR/config/local-ha/empty.txt"

TARGET="auspice/avian-flu_h5n1_ha_local.json"
ARGS=(--cores "$CORES" -s ha-focused/Snakefile --printshellcmds --rerun-incomplete)
if [[ "$MODE" == dry-run ]]; then ARGS+=(--dry-run); fi
(
    cd "$RUN_DIR"
    snakemake "${ARGS[@]}" "$TARGET" 2>&1 | tee snakemake.log
)
if [[ "$MODE" == dry-run ]]; then
    echo "Dry run passed. No tree was built or uploaded."
    exit 0
fi
[[ -s "$RUN_DIR/$TARGET" ]] || die "Build did not produce $TARGET"

if $UPLOAD; then
    require smbclient
    SMB_LEAF="$(basename "$RUN_DIR")_Nextstrain_HA"
    (
        cd "$RUN_DIR/auspice"
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_PARENT" \
            -c "mkdir $SMB_LEAF; cd $SMB_LEAF; put avian-flu_h5n1_ha_local.json"
    )
fi
echo "HA build complete: $RUN_DIR/$TARGET"
