#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#  Nextstrain H5N1 whole‑genome wrapper – FHI custom version
# -----------------------------------------------------------------------------
#  • Downloads metadata & FASTA from the N‑drive
#  • Converts / cleans metadata + splits FASTA by segment
#  • Runs the customised Nextstrain avian‑flu build
#  • Uploads the resulting Auspice JSONs back to the N‑drive
# -----------------------------------------------------------------------------
#  Usage (manual metadata / FASTA):
#     ./nextstrain_avian_whole_genome_wrapper.sh metadata.xls sequences.fasta
#  If the two arguments are omitted, the script will try to autodetect the files
#  in the SMB download directory.
# -----------------------------------------------------------------------------
set -Eeuo pipefail
IFS=$'\n\t'

# ──────────────────── General settings ────────────────────
DATE=$(date +%F)                            # e.g. 2025‑04‑25
BASE_DIR="/mnt/tempdata"                  # Base scratch area
WORK_DIR="${BASE_DIR}/avianflu_nextstrain" # Holds raw input data
OUT_DIR="${BASE_DIR}/avianflu_nextstrain_out/${DATE}" # Holds final Auspice JSONs

# SMB share (adjust if moved)
SMB_HOST="//Pos1-fhi-svm01/styrt"
SMB_AUTH="$HOME/.smbcreds"                # username/password file
SMB_SOURCE="Virologi/NGS/tmp/avianflu_nextstrain"
SMB_TARGET="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain/${DATE}_Nextstrain_Build"

# Git repos
NGS_SCRIPTS="$HOME/ngs_scripts"           # FHI helper scripts
AVIAN_REPO="${BASE_DIR}/avian-flu"        # Nextstrain avian influenza repo

# Conda env
CONDA_ENV="SNAKEMAKE"                     # Name of the conda env with Snakemake

# ──────────────────── Helper functions ────────────────────
require()     { command -v "$1" &>/dev/null || { echo "❌ '$1' not found" >&2; exit 1; }; }
clone_update() {
    local repo="$1" dest="$2" branch="${3:-main}"
    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" fetch origin "$branch"
        git -C "$dest" pull --ff-only origin "$branch"
    else
        git clone --branch "$branch" --depth 1 "$repo" "$dest"
    fi
}

# ──────────────────── Pre‑flight checks ───────────────────
REQUIRED_CMDS=(git smbclient conda python3)
for c in "${REQUIRED_CMDS[@]}"; do require "$c"; done
mkdir -p "$WORK_DIR" "$OUT_DIR"

# ──────────────────── Activate conda ──────────────────────
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate "$CONDA_ENV"
require snakemake            # Now snakemake must be available via the env

# ──────────────────── Get code ────────────────────────────
clone_update "https://github.com/folkehelseinstituttet/ngs_scripts.git" "$NGS_SCRIPTS" "main"
clone_update "https://github.com/nextstrain/avian-flu.git" "$AVIAN_REPO" "master"

# ──────────────────── Download data ───────────────────────
echo "🗄️  Fetching metadata & FASTA from SMB share …"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SOURCE" <<EOF
prompt OFF
recurse ON
lcd $WORK_DIR
mget *
EOF

# ──────────────────── Resolve input paths ─────────────────
if [[ $# -eq 2 ]]; then
    META_XLS="$1"
    SEQ_FASTA="$2"
else
    META_XLS="$(find "$WORK_DIR" -maxdepth 1 -iname '*.xls'   | head -n1)"
    SEQ_FASTA="$(find "$WORK_DIR" -maxdepth 1 -iname '*.fasta' | head -n1)"
fi

[[ -f "$META_XLS" && -f "$SEQ_FASTA" ]] || { echo "❌ Could not locate metadata/Fasta files" >&2; exit 1; }

# ──────────────────── Copy FHI build overlay ──────────────
echo "⚙️  Preparing customised Nextstrain build files …"
cp -R "${NGS_SCRIPTS}/nextstrain/influenza/avian_flu/." "$AVIAN_REPO/"

# ──────────────────── Prepare local data ──────────────────
SCRIPT_DIR="${NGS_SCRIPTS}/nextstrain/avian_flu"
OUTDATA_DIR="${AVIAN_REPO}/local_data"
mkdir -p "$OUTDATA_DIR"

"$SCRIPT_DIR/convert_xls_to_tsv.sh" "$META_XLS"
python3 "$SCRIPT_DIR/process_metadata.py" output.tsv "$OUTDATA_DIR/metadata.tsv"
python3 "$SCRIPT_DIR/split_fasta_by_segment.py" "$SEQ_FASTA" --output-dir "$OUTDATA_DIR"

# ──────────────────── Run Snakemake build ─────────────────
pushd "$AVIAN_REPO" >/dev/null
CORES="$(nproc --ignore 1 || echo 1)"
echo "🚀 Launching Snakemake with $CORES CPU(s) …"
snakemake --cores "$CORES" -s genome-focused/Snakefile --printshellcmds --rerun-incomplete
popd >/dev/null

# ──────────────────── Collect & version outputs ───────────
echo "📦 Collecting Auspice JSON files …"
AUSPICE_DIR="$AVIAN_REPO/auspice"
for f in "$AUSPICE_DIR"/*.json; do
    base="$(basename "$f" .json)"
    cp "$f" "${OUT_DIR}/${base}_${DATE}.json"
    ln -sf "${OUT_DIR}/${base}_${DATE}.json" "${OUT_DIR}/${base}_latest.json"
done

# ──────────────────── Upload back to SMB ──────────────────
echo "📤 Uploading results to SMB share …"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_TARGET" <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

echo "🧹 Cleaning up …"
rm -rf "$WORK_DIR"

echo "✅ Pipeline finished – results in $OUT_DIR"
