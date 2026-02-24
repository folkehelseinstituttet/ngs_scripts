#!/usr/bin/env bash
set -euo pipefail

# Wrapper for running the primer-only workflow on consensus FASTA files.
# Downloads FASTA / primer resources from the N-drive via smbclient and runs
# `nextflow run main.nf --file primercheck-workflow ...`

source "${HOME}/miniconda3/etc/profile.d/conda.sh"

SCRIPT_NAME="$(basename "$0")"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"
SMB_CRED="${HOME}/.smbcreds"
NDRIVE_FASTA_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/7-Export"
NDRIVE_PRIMER_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/Primer-bed-files"
INSILISCO_DIR="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/6-SARS-CoV-2_NGS_Dashboard_DB/Insilisco_primer_experiements"
WORK_BASE="/mnt/tempdata/primercheck"
mkdir -p "${WORK_BASE}"

PIPELINE_DIR_DEFAULT="${HOME}/nf-core-sars"
PIPELINE_DIR="${PIPELINE_DIR:-${PIPELINE_DIR_DEFAULT}}"
PIPELINE_REPO_URL="${PIPELINE_REPO_URL:-https://github.com/RasmusKoRiis/nf-core-sars.git}"

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} -f <fasta_filename> -b <bed_filename> [options]

Required arguments:
  -f <file>     Name of the multi-FASTA file to download from the export folder
  -b <file>     Name of the BED file (primer scheme) to download

Optional arguments:
  -P <file>     Name of the primer FASTA file in the primer folder (default: try to match the BED name)
  -n <name>     Primer set name to tag outputs (default: derived from BED filename)
  -o <dir>      Output directory (default: ./primercheck-results-<timestamp>)
  -p <profile>  Nextflow profile (default: docker)
  -r <runid>    Run identifier stored in the output CSV (default: derived from FASTA filename)
  -W <dir>      Path to the nf-core-sars pipeline directory (default: ${PIPELINE_DIR})
  -U <url>      Git repository URL for nf-core-sars (default: ${PIPELINE_REPO_URL})
  -h            Show this help message
EOF
    exit 0
}

FASTA_NAME=""
BED_NAME=""
PRIMER_FASTA_NAME=""
PRIMER_SET_NAME=""
OUTDIR=""
NF_PROFILE="docker"
RUN_ID=""

while getopts ":hf:b:P:n:o:p:r:W:U:" opt; do
    case "$opt" in
        h) usage ;;
        f) FASTA_NAME="$OPTARG" ;;
        b) BED_NAME="$OPTARG" ;;
        P) PRIMER_FASTA_NAME="$OPTARG" ;;
        n) PRIMER_SET_NAME="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        p) NF_PROFILE="$OPTARG" ;;
        r) RUN_ID="$OPTARG" ;;
        W) PIPELINE_DIR="$OPTARG" ;;
        U) PIPELINE_REPO_URL="$OPTARG" ;;
        :) echo "Option -$OPTARG requires an argument."; usage ;;
        \?) echo "Unknown option -$OPTARG"; usage ;;
    esac
done

if [[ -z "${FASTA_NAME}" || -z "${BED_NAME}" ]]; then
    echo "ERROR: -f <fasta_filename> and -b <bed_filename> are required."
    usage
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${WORK_BASE}/${timestamp}"
mkdir -p "${RUN_DIR}"

OUTDIR="${OUTDIR:-${PWD}/primercheck-results-${timestamp}}"
mkdir -p "${OUTDIR}"

download_from_share() {
    local remote_path="$1"
    local filename="$2"
    local dest="$3"

    echo "Downloading ${filename} from ${remote_path}"
    smbclient "${SMB_HOST}" -A "${SMB_CRED}" -D "${remote_path}" <<EOF
prompt OFF
lcd "${dest}"
    mget "${filename}"
EOF
}

upload_to_share() {
    local remote_path="$1"
    local filepath="$2"
    smbclient "${SMB_HOST}" -A "${SMB_CRED}" -D "${remote_path}" <<EOF
prompt OFF
lcd "$(dirname "$filepath")"
mput "$(basename "$filepath")"
EOF
}

FASTA_LOCAL="${RUN_DIR}/${FASTA_NAME}"
BED_LOCAL="${RUN_DIR}/${BED_NAME}"

download_from_share "${NDRIVE_FASTA_DIR}" "${FASTA_NAME}" "${RUN_DIR}"
download_from_share "${NDRIVE_PRIMER_DIR}" "${BED_NAME}" "${RUN_DIR}"

if [[ -z "${PRIMER_FASTA_NAME}" ]]; then
    base="${BED_NAME%.*}"
    PRIMER_FASTA_NAME="${base}.primers.fasta"
fi
download_from_share "${NDRIVE_PRIMER_DIR}" "${PRIMER_FASTA_NAME}" "${RUN_DIR}"
PRIMER_FASTA_LOCAL="${RUN_DIR}/${PRIMER_FASTA_NAME}"

if [[ ! -s "${FASTA_LOCAL}" ]]; then
    echo "ERROR: FASTA file ${FASTA_LOCAL} not downloaded correctly."
    exit 2
fi
if [[ ! -s "${BED_LOCAL}" ]]; then
    echo "ERROR: BED file ${BED_LOCAL} not downloaded correctly."
    exit 2
fi
if [[ ! -s "${PRIMER_FASTA_LOCAL}" ]]; then
    echo "ERROR: Primer FASTA ${PRIMER_FASTA_LOCAL} not downloaded correctly."
    exit 2
fi

PRIMER_SET_NAME="${PRIMER_SET_NAME:-${BED_NAME%.*}}"
if [[ -z "${RUN_ID}" ]]; then
    RUN_ID="${FASTA_NAME%.*}"
fi

ensure_pipeline_repo() {
    local repo_dir="$1"
    local repo_url="$2"
    if [[ -d "${repo_dir}/.git" ]]; then
        echo "Updating nf-core-sars in ${repo_dir}"
        git -C "${repo_dir}" fetch --all --prune
        git -C "${repo_dir}" pull --ff-only || {
            echo "WARNING: git pull failed, continuing with existing checkout."
        }
    else
        echo "Cloning nf-core-sars into ${repo_dir}"
        mkdir -p "$(dirname "${repo_dir}")"
        git clone "${repo_url}" "${repo_dir}"
    fi
    if [[ ! -f "${repo_dir}/main.nf" ]]; then
        echo "ERROR: main.nf not found in ${repo_dir} after ensuring repository."
        exit 3
    fi
}

ensure_pipeline_repo "${PIPELINE_DIR}" "${PIPELINE_REPO_URL}"

pushd "${PIPELINE_DIR}" >/dev/null

nextflow run main.nf -profile "${NF_PROFILE}" \
    --file primercheck-workflow \
    --fasta "${FASTA_LOCAL}" \
    --primer_bed "${BED_LOCAL}" \
    --primer_fasta "${PRIMER_FASTA_LOCAL}" \
    --primer_set_name "${PRIMER_SET_NAME}" \
    --runid "${RUN_ID}" \
    --outdir "${OUTDIR}"

popd >/dev/null

echo "Primer check completed. Results in ${OUTDIR}"

# Merge mismatch CSVs with dashboard DB
mapfile -t CSV_FILES < <(find "${OUTDIR}/primer_metrics" -name "*primer_mismatches.csv" -print)
if [[ "${#CSV_FILES[@]}" -gt 0 ]]; then
    COMBINED_CSV="${RUN_DIR}/primer_mismatches_combined.csv"
    {
        head -n 1 "${CSV_FILES[0]}"
        for f in "${CSV_FILES[@]}"; do
            tail -n +2 "$f" || true
        done
    } > "${COMBINED_CSV}"

    DB_NAME="insilisco_primer_experiments.csv"
    download_from_share "${INSILISCO_DIR}" "${DB_NAME}" "${RUN_DIR}"
    DB_LOCAL="${RUN_DIR}/${DB_NAME}"
    if [[ ! -s "${DB_LOCAL}" ]]; then
        cp "${COMBINED_CSV}" "${DB_LOCAL}"
    else
        tail -n +2 "${COMBINED_CSV}" >> "${DB_LOCAL}"
    fi

    upload_to_share "${INSILISCO_DIR}" "${DB_LOCAL}"
    cp "${DB_LOCAL}" "${OUTDIR}/primer_metrics/${DB_NAME}"
    echo "Merged primer mismatches into ${DB_NAME} and uploaded to SMB share."
else
    echo "No primer mismatch CSV files found in ${OUTDIR}/primer_metrics"
fi
