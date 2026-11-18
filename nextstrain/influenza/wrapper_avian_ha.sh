#!/usr/bin/env bash
# HA-only Nextstrain build for an already prepared GISAID TSV and HA FASTA.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$HOME/avian_project}"
AVIAN_REPO="${AVIAN_REPO:-$PROJECT_DIR/avian-flu}"
RUN_ROOT="${RUN_ROOT:-$HOME/avianflu_ha_runs}"
CONDA_ENV="${CONDA_ENV-AVIAN_HA}"
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

With no paths, download metadata.tsv and sequences_ha.fasta from SMB_SOURCE
on SMB_HOST (the same share and folder as wrapper_avian_full_genome.sh).
Separate H5N1 and H5N5 HA trees are built; the minimum date of 2024 is retained.
Both subtypes must have matching HA records dated 2024 or later.

  --prepare-only  Validate and prepare inputs without needing Nextstrain
  --dry-run       Prepare a separate run and check the Snakemake job graph
  --smb           Explicitly select the default SMB download mode
  --upload        Upload both completed HA JSON files to a new SMB run folder
  -h, --help      Show this help

Environment: PROJECT_DIR, AVIAN_REPO, RUN_ROOT, CONDA_ENV, CONDA_SH, CORES,
             SMB_HOST, SMB_AUTH, SMB_SOURCE, SMB_PARENT.
Set CONDA_ENV='' to use tools already on PATH.
Each invocation creates a new directory under RUN_ROOT (~/avianflu_ha_runs).
PROJECT_DIR defaults to ~/avian_project; AVIAN_REPO to PROJECT_DIR/avian-flu.
A missing avian-flu checkout is cloned; existing checkouts are never updated.
Source input files are never modified.
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
if ((${#INPUTS[@]} == 0)); then USE_SMB=true; fi
[[ "$CORES" =~ ^[1-9][0-9]*$ ]] || die "CORES must be a positive integer."
require python3

mkdir -p "$RUN_ROOT"
RUN_DIR="$(mktemp -d "$RUN_ROOT/$(date +%F_%H%M%S)_XXXXXX")"
echo "Run directory: $RUN_DIR"
trap 'echo "Run failed; files and logs are retained in $RUN_DIR" >&2' ERR

if $USE_SMB; then
    require smbclient
    [[ -r "$SMB_AUTH" ]] || die "Cannot read SMB credentials: $SMB_AUTH"
    mkdir "$RUN_DIR/downloads"
    # Download precisely the two expected inputs, without recursive wildcards.
    (
        cd "$RUN_DIR/downloads"
        # Separate requests ensure failure of either download stops the run.
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SOURCE" -c 'get metadata.tsv'
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SOURCE" -c 'get sequences_ha.fasta'
    )
    META="$RUN_DIR/downloads/metadata.tsv"
    FASTA="$RUN_DIR/downloads/sequences_ha.fasta"
else
    META="${INPUTS[0]}"
    FASTA="${INPUTS[1]}"
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
python3 - <<'PY'
from importlib.metadata import version
from packaging.version import Version
installed = version("nextstrain-augur")
if Version(installed) < Version("34.1.2"):
    raise SystemExit(f"Augur {installed} is too old; this workflow requires >=34.1.2. Select a compatible CONDA_ENV.")
PY
if [[ ! -e "$AVIAN_REPO" ]]; then
    require git
    mkdir -p "$(dirname "$AVIAN_REPO")"
    git clone --depth 1 --branch master https://github.com/nextstrain/avian-flu.git "$AVIAN_REPO"
fi
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
if command -v git >/dev/null && [[ -d "$AVIAN_REPO/.git" ]]; then
    git -C "$AVIAN_REPO" rev-parse HEAD > "$RUN_DIR/upstream-revision.txt"
fi
mkdir -p "$RUN_DIR/config/local-ha"
# An empty list prevents force-inclusion of unrelated reference strains.
: > "$RUN_DIR/config/local-ha/empty.txt"

TARGETS=(auspice/avian-flu_h5n1_ha_local.json auspice/avian-flu_h5n5_ha_local.json)
ARGS=(--cores "$CORES" -s ha-focused/Snakefile --printshellcmds --rerun-incomplete)
if [[ "$MODE" == dry-run ]]; then ARGS+=(--dry-run); fi
(
    cd "$RUN_DIR"
    snakemake "${ARGS[@]}" "${TARGETS[@]}" 2>&1 | tee snakemake.log
)
if [[ "$MODE" == dry-run ]]; then
    echo "Dry run passed. No tree was built or uploaded."
    exit 0
fi
for target in "${TARGETS[@]}"; do
    [[ -s "$RUN_DIR/$target" ]] || die "Build did not produce $target"
done

if $UPLOAD; then
    require smbclient
    SMB_LEAF="$(basename "$RUN_DIR")_Nextstrain_HA"
    (
        cd "$RUN_DIR/auspice"
        smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_PARENT" \
            -c "mkdir $SMB_LEAF"
        for target in "${TARGETS[@]}"; do
            smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_PARENT/$SMB_LEAF" \
                -c "put $(basename "$target")"
        done
    )
fi
for target in "${TARGETS[@]}"; do
    echo "HA build complete: $RUN_DIR/$target"
done
