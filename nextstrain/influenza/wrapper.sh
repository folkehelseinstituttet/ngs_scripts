#!/usr/bin/env bash
# Nextstrain seasonal-flu build with post-build subclade verification (and patched metadata parsing)

set -euo pipefail

# --- Conda ---
source ~/miniconda3/etc/profile.d/conda.sh

# --- Date ---
DATE="$(date +%Y-%m-%d)"

# --- Paths / SMB ---
BASE_DIR="/mnt/tempdata"
TMP_DIR="${BASE_DIR}/flu_nextstrain"
OUT_DIR="${BASE_DIR}/flu_nextstrain_out"

SMB_AUTH="/home/ngs/.smbcreds"
SMB_HOST="//pos1-fhi-svm01.fhi.no/styrt"
SMB_DIR="Virologi/NGS/tmp/flu_nextstrain"
SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain/${DATE}_Nextstrain_Build"

# --- Repos ---
NGS_SCRIPTS_DIR="$HOME/ngs_scripts"
SEASONAL_FLU_DIR="${BASE_DIR}/seasonal-flu"
SEASONAL_FLU_REMOTE="https://github.com/nextstrain/seasonal-flu.git"

# --- Ensure local dirs exist ---
mkdir -p "$OUT_DIR" "$TMP_DIR" "$BASE_DIR"

# --- Pull/update helper repo with our configs ---
if [ -d "$NGS_SCRIPTS_DIR/.git" ]; then
  git -C "$NGS_SCRIPTS_DIR" pull --ff-only origin main
else
  git clone https://github.com/folkehelseinstituttet/ngs_scripts.git "$NGS_SCRIPTS_DIR"
fi

# --- Clone or hard reset seasonal-flu to upstream master ---
if [ -d "${SEASONAL_FLU_DIR}/.git" ]; then
  git -C "$SEASONAL_FLU_DIR" remote set-url origin "$SEASONAL_FLU_REMOTE"
  git -C "$SEASONAL_FLU_DIR" fetch --prune origin
  git -C "$SEASONAL_FLU_DIR" reset --hard origin/master
else
  git clone "$SEASONAL_FLU_REMOTE" "$SEASONAL_FLU_DIR"
fi

# --- Create profile and data dirs (idempotent) ---
mkdir -p "${SEASONAL_FLU_DIR}/profiles/niph"
mkdir -p "${SEASONAL_FLU_DIR}/data/h1n1pdm" \
         "${SEASONAL_FLU_DIR}/data/h3n2" \
         "${SEASONAL_FLU_DIR}/data/vic"

# --- Pull input files from SMB to TMP_DIR ---
echo "Fetching inputs from SMB share..."
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

# --- Copy our build configs into seasonal-flu profile ---
cp "$NGS_SCRIPTS_DIR/nextstrain/influenza/fhi/builds.yaml"      "${SEASONAL_FLU_DIR}/profiles/niph/"
cp "$NGS_SCRIPTS_DIR/nextstrain/influenza/fhi/config.yaml"      "${SEASONAL_FLU_DIR}/profiles/niph/"
cp "$NGS_SCRIPTS_DIR/nextstrain/influenza/fhi/prepare_data.smk" "${SEASONAL_FLU_DIR}/profiles/niph/"

# Ensure builds.yaml points to our local rule file (if it referenced profiles/gisaid before)
if grep -q 'profiles/gisaid/prepare_data\.smk' "${SEASONAL_FLU_DIR}/profiles/niph/builds.yaml"; then
  sed -i 's#profiles/gisaid/prepare_data\.smk#profiles/niph/prepare_data.smk#g' "${SEASONAL_FLU_DIR}/profiles/niph/builds.yaml"
fi

# --- Copy data into seasonal-flu expected locations ---
cp "${BASE_DIR}/flu_nextstrain/H1/metadata.xls"            "${SEASONAL_FLU_DIR}/data/h1n1pdm/"
cp "${BASE_DIR}/flu_nextstrain/H1/raw_sequences_ha.fasta"  "${SEASONAL_FLU_DIR}/data/h1n1pdm/"
cp "${BASE_DIR}/flu_nextstrain/H1/raw_sequences_na.fasta"  "${SEASONAL_FLU_DIR}/data/h1n1pdm/"

cp "${BASE_DIR}/flu_nextstrain/H3/metadata.xls"            "${SEASONAL_FLU_DIR}/data/h3n2/"
cp "${BASE_DIR}/flu_nextstrain/H3/raw_sequences_ha.fasta"  "${SEASONAL_FLU_DIR}/data/h3n2/"
cp "${BASE_DIR}/flu_nextstrain/H3/raw_sequences_na.fasta"  "${SEASONAL_FLU_DIR}/data/h3n2/"

cp "${BASE_DIR}/flu_nextstrain/VIC/metadata.xls"           "${SEASONAL_FLU_DIR}/data/vic/"
cp "${BASE_DIR}/flu_nextstrain/VIC/raw_sequences_ha.fasta" "${SEASONAL_FLU_DIR}/data/vic/"
cp "${BASE_DIR}/flu_nextstrain/VIC/raw_sequences_na.fasta" "${SEASONAL_FLU_DIR}/data/vic/"

# --- Activate env ---
conda activate NEXTSTRAIN

# --- Preflight checks that don't depend on downloaded TSVs ---
cd "$SEASONAL_FLU_DIR"

# Guard against including HA reference as a sample (if ref present already)
if [ -f config/h3n2/ha/reference.fasta ]; then
  h3_ref_id="$(head -1 config/h3n2/ha/reference.fasta | sed 's/^>//')"
  if grep -qF "$h3_ref_id" data/h3n2/raw_sequences_ha.fasta; then
    echo "ERROR: H3N2 HA reference '$h3_ref_id' appears in raw_sequences_ha.fasta (must NOT be a sample)." >&2
    exit 1
  fi
fi

# GFF within reference length (if files present in repo)
if [ -f config/h3n2/ha/reference.fasta ] && [ -f config/h3n2/ha/genemap.gff ]; then
  h3_ref_len="$(awk '/^>/ {next} {l+=length($0)} END{print l}' config/h3n2/ha/reference.fasta)"
  h3_bad_cds="$(awk -v L="$h3_ref_len" '$3=="CDS" && ($4>L || $5>L)' config/h3n2/ha/genemap.gff | wc -l | tr -d ' ')"
  if [ "$h3_bad_cds" -ne 0 ]; then
    echo "ERROR: H3N2 HA genemap.gff has CDS beyond reference length ($h3_ref_len) -> coordinate drift." >&2
    exit 1
  fi
fi


# --- Build (force refresh of downloaded clade/subclade definitions) ---
echo "Making the Nextstrain build..."
nextstrain build . --configfile profiles/niph/builds.yaml --cores 14 --forceall

echo "Build finished. Preparing outputs..."

# --- Post-build: verify subclade TSVs now that they have been downloaded ---
echo "[Postflight] Verifying downloaded subclade definitions..."
if [ -f config/h3n2/ha/subclades.tsv ]; then
  if egrep -q '^(J\.2\.[345]|J\.3|J\.4)\b' config/h3n2/ha/subclades.tsv; then
    echo "OK: H3N2 HA subclades.tsv contains expected recent labels."
  else
    echo "WARNING: H3N2 HA subclades.tsv seems stale (missing J.2.3/2.4/2.5 or J.3/J.4)." >&2
  fi
  cp config/h3n2/ha/subclades.tsv "${OUT_DIR}/h3n2_ha_subclades_used.tsv"
else
  echo "WARNING: config/h3n2/ha/subclades.tsv not found after build (unexpected)." >&2
fi

# --- Copy auspice files to OUT_DIR ---
mkdir -p "$OUT_DIR"
cp "${SEASONAL_FLU_DIR}/auspice/"*.json "$OUT_DIR"

# --- Rename outputs by lineage/segment/date ---
DATE="$(date +%Y-%m-%d)"

# H1N1
cp "${OUT_DIR}/h1n1_fhi_ha.json"                  "${OUT_DIR}/flu_a_h1n1_ha_${DATE}.json"                  || true
mv "${OUT_DIR}/h1n1_fhi_ha.json"                  "${OUT_DIR}/flu_a_h1n1_ha_latest.json"                   || true

cp "${OUT_DIR}/h1n1_fhi_ha_tip-frequencies.json"  "${OUT_DIR}/flu_a_h1n1_ha_${DATE}_tip-frequencies.json"  || true
mv "${OUT_DIR}/h1n1_fhi_ha_tip-frequencies.json"  "${OUT_DIR}/flu_a_h1n1_ha_latest_tip-frequencies.json"   || true

cp "${OUT_DIR}/h1n1_fhi_na.json"                  "${OUT_DIR}/flu_a_h1n1_na_${DATE}.json"                  || true
mv "${OUT_DIR}/h1n1_fhi_na.json"                  "${OUT_DIR}/flu_a_h1n1_na_latest.json"                   || true

cp "${OUT_DIR}/h1n1_fhi_na_tip-frequencies.json"  "${OUT_DIR}/flu_a_h1n1_na_${DATE}_tip-frequencies.json"  || true
mv "${OUT_DIR}/h1n1_fhi_na_tip-frequencies.json"  "${OUT_DIR}/flu_a_h1n1_na_latest_tip-frequencies.json"   || true

# H3N2
cp "${OUT_DIR}/h3n2_fhi_ha.json"                  "${OUT_DIR}/flu_a_h3n2_ha_${DATE}.json"                  || true
mv "${OUT_DIR}/h3n2_fhi_ha.json"                  "${OUT_DIR}/flu_a_h3n2_ha_latest.json"                   || true

cp "${OUT_DIR}/h3n2_fhi_ha_tip-frequencies.json"  "${OUT_DIR}/flu_a_h3n2_ha_${DATE}_tip-frequencies.json"  || true
mv "${OUT_DIR}/h3n2_fhi_ha_tip-frequencies.json"  "${OUT_DIR}/flu_a_h3n2_ha_latest_tip-frequencies.json"   || true

cp "${OUT_DIR}/h3n2_fhi_na.json"                  "${OUT_DIR}/flu_a_h3n2_na_${DATE}.json"                  || true
mv "${OUT_DIR}/h3n2_fhi_na.json"                  "${OUT_DIR}/flu_a_h3n2_na_latest.json"                   || true

cp "${OUT_DIR}/h3n2_fhi_na_tip-frequencies.json"  "${OUT_DIR}/flu_a_h3n2_na_${DATE}_tip-frequencies.json"  || true
mv "${OUT_DIR}/h3n2_fhi_na_tip-frequencies.json"  "${OUT_DIR}/flu_a_h3n2_na_latest_tip-frequencies.json"   || true

# VIC
cp "${OUT_DIR}/vic_fhi_ha.json"                   "${OUT_DIR}/flu_b_vic_ha_${DATE}.json"                   || true
mv "${OUT_DIR}/vic_fhi_ha.json"                   "${OUT_DIR}/flu_b_vic_ha_latest.json"                    || true

cp "${OUT_DIR}/vic_fhi_ha_tip-frequencies.json"   "${OUT_DIR}/flu_b_vic_ha_${DATE}_tip-frequencies.json"   || true
mv "${OUT_DIR}/vic_fhi_ha_tip-frequencies.json"   "${OUT_DIR}/flu_b_vic_ha_latest_tip-frequencies.json"    || true

cp "${OUT_DIR}/vic_fhi_na.json"                   "${OUT_DIR}/flu_b_vic_na_${DATE}.json"                   || true
mv "${OUT_DIR}/vic_fhi_na.json"                   "${OUT_DIR}/flu_b_vic_na_latest.json"                    || true

cp "${OUT_DIR}/vic_fhi_na_tip-frequencies.json"   "${OUT_DIR}/flu_b_vic_na_${DATE}_tip-frequencies.json"   || true
mv "${OUT_DIR}/vic_fhi_na_tip-frequencies.json"   "${OUT_DIR}/flu_b_vic_na_latest_tip-frequencies.json"    || true

# --- Upload results to SMB ---
echo "Uploading results to SMB..."
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR_ANALYSIS" <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

# --- Clean up workspace (keep OUT_DIR only) ---
rm -rf "$TMP_DIR"
rm -rf "$SEASONAL_FLU_DIR"

echo "Done."
