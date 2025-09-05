#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Config — adjust for your environment
############################################
CONDA_ENV="PRIMER_CHECK"

# Git repo for primer checker (always update/clone)
REPO_URL="https://github.com/RasmusKoRiis/primer-checker.git"
REPO_DIR="${HOME}/primer-checker"     # local checkout path
PRIMER_SCRIPT="${REPO_DIR}/primer_blast.py"

# N-drive primers location (your path, relative to the SMB share)
# N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\Sesongfiler\primercheck_db
SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//Pos1-fhi-svm01/styrt"
SMB_DIR_PRIMERS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/primercheck_db"

# Working dirs
BASE_DIR="/mnt/tempdata"
TMP_DIR="${BASE_DIR}/flu_toolkit"         # downloads / inputs
OUT_DIR="${BASE_DIR}/flu_toolkit_out"     # local reports
LOCAL_PRIMER_DIR="${BASE_DIR}/primercheck_db"   # where we stage primer.json locally
PRIMER_JSON="${LOCAL_PRIMER_DIR}/primer.json"   # we will fetch this from N every run

# SMB source (where FASTAs live) and where to return reports (same place)
SMB_DIR="Virologi/NGS/tmp/flu_toolkit"    # source of FASTAs
SMB_DIR_UPLOAD="${SMB_DIR}"               # upload reports next to inputs

DATE="$(date +%Y-%m-%d)"
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_SUBDIR="primer_check_${STAMP}"

############################################
# Helpers
############################################
log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }

update_repo() {
  local dir="$1" url="$2"
  if [ -d "${dir}/.git" ]; then
    git -C "${dir}" remote set-url origin "${url}" || true
    git -C "${dir}" fetch --tags --prune --quiet
    local defbranch
    defbranch="$(git -C "${dir}" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's@^origin/@@' || true)"
    [ -z "${defbranch:-}" ] && defbranch="main"
    git -C "${dir}" checkout -q "${defbranch}" || true
    git -C "${dir}" reset --hard "origin/${defbranch}"
  else
    git clone --depth 1 "${url}" "${dir}"
  fi
  git -C "${dir}" rev-parse --short HEAD
}

detect_flu_subtype() {
  local subtype="A"
  if grep -Ih -m 1 -E "^>" "$@" | grep -qiE "influenza[ _-]*b|(^|[^a-z])ibv([^a-z]|$)|\btype[ _-]*b\b"; then
    subtype="B"
  elif grep -Ih -m 1 -E "^>" "$@" | grep -qiE "\bH3\b|H3N|H3-"; then
    subtype="H3"
  elif grep -Ih -m 1 -E "^>" "$@" | grep -qiE "\bH1\b|H1N|H1-"; then
    subtype="H1"
  fi
  echo "${subtype}"
}

detect_rsv_subtype() {
  local guess="Unknown"
  for f in "$@"; do
    local base lc
    base="$(basename "$f")"; lc="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
    if echo "$lc" | grep -qE "rsv.?a(|[^a-z])|\brsv-a\b"; then guess="A"; break; fi
    if echo "$lc" | grep -qE "rsv.?b(|[^a-z])|\brsv-b\b"; then guess="B"; break; fi
    if grep -Ih -m 1 -E "^>" "$f" | grep -qiE "rsv[^a-z]*a|\brsv-a\b"; then guess="A"; break; fi
    if grep -Ih -m 1 -E "^>" "$f" | grep -qiE "rsv[^a-z]*b|\brsv-b\b"; then guess="B"; break; fi
  done
  echo "${guess}"
}

upload_reports() {
  log "Uploading reports to SMB: ${SMB_DIR_UPLOAD}/${REPORT_SUBDIR}"
  smbclient "${SMB_HOST}" -A "${SMB_AUTH}" <<EOF
prompt OFF
recurse ON
cd "${SMB_DIR_UPLOAD}"
mkdir "${REPORT_SUBDIR}"
cd "${REPORT_SUBDIR}"
mput ${OUT_DIR}/*.csv
mput ${OUT_DIR}/RUN_LOG_${STAMP}.txt
EOF
  log "Upload complete."
}

############################################
# Pre-flight
############################################
require smbclient
require git
require python3
require blastn

# Conda
if [ -f "${HOME}/miniconda3/etc/profile.d/conda.sh" ]; then
  # shellcheck disable=SC1091
  source "${HOME}/miniconda3/etc/profile.d/conda.sh"
fi
conda activate "${CONDA_ENV}" || { echo "Failed to conda activate ${CONDA_ENV}" >&2; exit 1; }

# Get/refresh primer-checker from GitHub (for the Python script)
mkdir -p "${REPO_DIR%/*}"
SHA="$(update_repo "${REPO_DIR}" "${REPO_URL}")"
log "primer-checker @ ${SHA}"

# Verify Python script exists
[ -f "${PRIMER_SCRIPT}" ] || { echo "Missing PRIMER_SCRIPT: ${PRIMER_SCRIPT}" >&2; exit 1; }

# Prepare dirs
mkdir -p "${TMP_DIR}" "${OUT_DIR}" "${LOCAL_PRIMER_DIR}"
: > "${OUT_DIR}/RUN_LOG_${STAMP}.txt"
echo "primer-checker commit: ${SHA}" >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

############################################
# Fetch primer.json from N (override repo copy)
############################################
log "Fetching primer.json from //${SMB_HOST}/${SMB_DIR_PRIMERS} → ${LOCAL_PRIMER_DIR}"
smbclient "${SMB_HOST}" -A "${SMB_AUTH}" -D "${SMB_DIR_PRIMERS}" <<EOF
prompt OFF
recurse ON
lcd ${LOCAL_PRIMER_DIR}
mget primer.json
EOF

if [ ! -f "${PRIMER_JSON}" ]; then
  echo "ERROR: primer.json not found after fetch from N (${SMB_DIR_PRIMERS})." >&2
  exit 1
fi

# Optional: capture checksum for provenance (if md5sum exists)
if command -v md5sum >/dev/null 2>&1; then
  md5sum "${PRIMER_JSON}" >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt" || true
fi

############################################
# Fetch FASTAs from SMB
############################################
log "Fetching input FASTAs from //${SMB_HOST}/${SMB_DIR} → ${TMP_DIR}"
smbclient "${SMB_HOST}" -A "${SMB_AUTH}" -D "${SMB_DIR}" <<EOF
prompt OFF
recurse ON
lcd ${TMP_DIR}
mget *
EOF

# Collect FASTAs
mapfile -t ALL_FASTAS < <(find "${TMP_DIR}" -type f \( -iname "*.fa" -o -iname "*.fasta" -o -iname "*.fna" \) | sort || true)

if [ "${#ALL_FASTAS[@]}" -eq 0 ]; then
  log "No FASTA files found in ${TMP_DIR}. Nothing to do. (mou5 man6 = take a rest)"
  exit 0
fi

############################################
# Classify by virus (filename + header heuristics)
############################################
declare -a INFLUENZA_FASTAS SARS_FASTAS RSV_FASTAS
for f in "${ALL_FASTAS[@]}"; do
  lc="$(echo "$(basename "$f")" | tr '[:upper:]' '[:lower:]')"
  if echo "$lc" | grep -qE "influenza|(^|[_-])iav([_-]|$)|(^|[_-])ibv([_-]|$)|\b(h1|h3|ha|na|pb1|pb2|pa|np|m|ns)\b"; then
    INFLUENZA_FASTAS+=("$f"); continue
  fi
  if echo "$lc" | grep -qE "sars|cov2|cov-2|sarscov2|ncov|hcov-19|sc2"; then
    SARS_FASTAS+=("$f"); continue
  fi
  if echo "$lc" | grep -qE "rsv|respiratory[_-]?syncytial"; then
    RSV_FASTAS+=("$f"); continue
  fi
  # backup: sniff headers
  if grep -Ih -m 1 -E "^>" "$f" | grep -qiE "influenza|iav|ibv|H[13]N|segment|HA|NA|PB1|PB2|PA|NP|M[12]?|NS[12]?"; then
    INFLUENZA_FASTAS+=("$f"); continue
  fi
  if grep -Ih -m 1 -E "^>" "$f" | grep -qiE "sars[- ]?cov[- ]?2|hcov-19|wuhan"; then
    SARS_FASTAS+=("$f"); continue
  fi
  if grep -Ih -m 1 -E "^>" "$f" | grep -qiE "respiratory[ _-]?syncytial|rsv"; then
    RSV_FASTAS+=("$f"); continue
  fi
done

############################################
# Run order: Influenza → SARS-CoV-2 → RSV
############################################

# 1) Influenza
if [ "${#INFLUENZA_FASTAS[@]}" -gt 0 ]; then
  FLU_SUBTYPE="$(detect_flu_subtype "${INFLUENZA_FASTAS[@]}")"
  OUT_FLU="${OUT_DIR}/${DATE}_Influenza-${FLU_SUBTYPE}_primer_report.csv"
  {
    echo "=== Influenza (${FLU_SUBTYPE}) ==="
    printf "%s\n" "${INFLUENZA_FASTAS[@]}"
  } >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

  python3 "${PRIMER_SCRIPT}" \
    --primers "${PRIMER_JSON}" \
    --virus "influenza" \
    --flu-type "${FLU_SUBTYPE}" \
    --fasta "${INFLUENZA_FASTAS[@]}" \
    --output "${OUT_FLU}"
fi

# 2) SARS-CoV-2
if [ "${#SARS_FASTAS[@]}" -gt 0 ]; then
  OUT_SARS="${OUT_DIR}/${DATE}_SARS-CoV-2_primer_report.csv"
  {
    echo "=== SARS-CoV-2 ==="
    printf "%s\n" "${SARS_FASTAS[@]}"
  } >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

  python3 "${PRIMER_SCRIPT}" \
    --primers "${PRIMER_JSON}" \
    --virus "SARS-CoV-2" \
    --fasta "${SARS_FASTAS[@]}" \
    --output "${OUT_SARS}"
fi

# 3) RSV (split A/B when detectable; default Unknown → run as RSV-A)
if [ "${#RSV_FASTAS[@]}" -gt 0 ]; then
  declare -a RSV_A_FASTAS RSV_B_FASTAS RSV_UNKNOWN_FASTAS
  for f in "${RSV_FASTAS[@]}"; do
    sub="$(detect_rsv_subtype "$f")"
    case "$sub" in
      A) RSV_A_FASTAS+=("$f") ;;
      B) RSV_B_FASTAS+=("$f") ;;
      *) RSV_UNKNOWN_FASTAS+=("$f") ;;
    esac
  done

  if [ "${#RSV_A_FASTAS[@]}" -gt 0 ]; then
    OUT_RSVA="${OUT_DIR}/${DATE}_RSV-A_primer_report.csv"
    {
      echo "=== RSV-A ==="
      printf "%s\n" "${RSV_A_FASTAS[@]}"
    } >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

    python3 "${PRIMER_SCRIPT}" \
      --primers "${PRIMER_JSON}" \
      --virus "RSV-A" \
      --fasta "${RSV_A_FASTAS[@]}" \
      --output "${OUT_RSVA}"
  fi

  if [ "${#RSV_B_FASTAS[@]}" -gt 0 ]; then
    OUT_RSVB="${OUT_DIR}/${DATE}_RSV-B_primer_report.csv"
    {
      echo "=== RSV-B ==="
      printf "%s\n" "${RSV_B_FASTAS[@]}"
    } >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

    python3 "${PRIMER_SCRIPT}" \
      --primers "${PRIMER_JSON}" \
      --virus "RSV-B" \
      --fasta "${RSV_B_FASTAS[@]}" \
      --output "${OUT_RSVB}"
  fi

  if [ "${#RSV_UNKNOWN_FASTAS[@]}" -gt 0 ]; then
    OUT_RSVU="${OUT_DIR}/${DATE}_RSV-Unknown_as_A_primer_report.csv"
    {
      echo "=== RSV-Unknown (ran as RSV-A) ==="
      printf "%s\n" "${RSV_UNKNOWN_FASTAS[@]}"
    } >> "${OUT_DIR}/RUN_LOG_${STAMP}.txt"

    python3 "${PRIMER_SCRIPT}" \
      --primers "${PRIMER_JSON}" \
      --virus "RSV-A" \
      --fasta "${RSV_UNKNOWN_FASTAS[@]}" \
      --output "${OUT_RSVU}"
  fi
fi

############################################
# Upload reports next to the inputs
############################################
upload_reports

log "Done. hou2 sai3 laa3 — neat and finished."
