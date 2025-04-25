#!/usr/bin/env bash
set -euo pipefail

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Get the date
DATE=$(date +%Y-%m-%d)

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/avianflu_nextstrain
OUT_DIR=/mnt/tempdata/avianflu_nextstrain_out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/avianflu_nextstrain
SMB_DIR_ANALYSIS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain/${DATE}_Nextstrain_Build 
SMB_DIR_UPLOAD=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain/${DATE}_Nextstrain_Build 

# Check if the ngs_scripts directory exists, if not clone it from GitHub
cd $HOME
if [ -d "ngs_scripts" ]; then
  # Make sure to pull the latest version
  git -C ngs_scripts/ pull origin main
else
  git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
fi

# Check if the seasonal_flu repo exists, if not clone it from GitHub
cd $BASE_DIR
if [ -d "seasonal-flu" ]; then
  cd avian-flu
  # Make sure to pull the latest version
  git pull origin master
  git stash
  git pull origin master
  git stash pop
else
  git clone https://github.com/nextstrain/avian-flu.git
fi

## Make output dir
mkdir $OUT_DIR

# Create directory to hold the output of the analysis
mkdir $TMP_DIR

# Get files from N . metadata.xls and sequences.fasta
echo "Getting files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

# Copy nextstrain build files into the avian-flu directory
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/h5n1 $BASE_DIR/avian-flu/config
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/empty.txt $BASE_DIR/avian-flu
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/config.yaml $BASE_DIR/avian-flu/genome-focused
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/Snakefile $BASE_DIR/avian-flu/genome-focused
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/genome.smk $BASE_DIR/avian-flu/rules
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/avian_flu/main.smk $BASE_DIR/avian-flu/rules

# -------------------------------------------------------------------
# usage: ./nextstrain_avian_whole_genome_wrapper.sh <metadata.xls> <sequences.fasta>
# -------------------------------------------------------------------

if [ $# -ne 2 ]; then
  echo "Usage: $0 <metadata.xls> <sequences.fasta>"
  exit 1
fi

META_XLS="$1"
SEQ_FASTA="$2"
OUTDIR="local_data"

# Figure out where this script lives so we can call the others
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) convert XLS → TSV
#    produces output.csv, output.tsv in cwd
"$SCRIPT_DIR/convert_xls_to_tsv.sh" "$META_XLS"

# 2) process metadata.tsv → cleaned TSV
#    inject pandas option at top of the script to suppress that warning
#    writes local_data/cleaned_metadata.tsv
mkdir -p "$OUTDIR"
# (we'll prepend the pandas option automatically)
awk '
  NR==1 && /^#!/ { print; print "import pandas as pd; pd.set_option(\"future.no_silent_downcasting\", True)"; next }
  { print }
' "$SCRIPT_DIR/process_metadata.py" > /tmp/.proc_meta_fixed.py

python3 /tmp/.proc_meta_fixed.py output.tsv "$OUTDIR/metadata.tsv"
rm /tmp/.proc_meta_fixed.py

# 3) split your FASTA by segment
#
#    If the user passed an absolute path, we keep it.
#    If they passed a relative path, we leave it alone too.
pushd "$OUTDIR" >/dev/null
python3 "$SCRIPT_DIR/split_fasta_by_segment.py" "$SEQ_FASTA"
popd >/dev/null

echo "✅ All done!"
echo "   • Metadata → $OUTDIR/metadata.tsv"
echo "   • Split FASTAs → $OUTDIR/sequences_<segment>.fasta"

# 3) run nextstrain build
#    clone avian nextstrain repo
#    copy config files into nextstrain repo
#    run nextstrain build

conda activate SNAKEMAKE
