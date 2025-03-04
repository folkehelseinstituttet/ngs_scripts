#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Get the date
DATE=$(date +%Y-%m-%d)

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/rsv_nextstrain
OUT_DIR=/mnt/tempdata/rsv_nextstrain_out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/rsv_nextstrain
SMB_DIR_ANALYSIS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/11-Nextstrain/${DATE}_Nextstrain_Build 
SMB_DIR_UPLOAD=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/11-Nextstrain/${DATE}_Nextstrain_Build 

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
if [ -d "rsv" ]; then
  cd rsv
  # Make sure to pull the latest version
  git pull origin master
  git stash
  git pull origin master
  git stash pop
else
  git clone https://github.com/nextstrain/rsv.git
fi

## Make output dir
mkdir $OUT_DIR

## Make dir structure for NIPH
cd rsv
rm -rf data && mkdir -p data/{a,b}
rm -f config/configfile.yaml
cd "$BASE_DIR"

## Move input files from N

# Create directory to hold the output of the analysis
mkdir $TMP_DIR

echo "Getting files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/rsv/config.yaml $BASE_DIR/rsv/config
cp $HOME/ngs_scripts/nextstrain/rsv/merge_and_clean.py $BASE_DIR/rsv/

# Organize and quality checks RSV A data
cp $BASE_DIR/rsv_nextstrain/virus_RSV_A/metadata.tsv $BASE_DIR/rsv/data/a
cp $BASE_DIR/rsv_nextstrain/virus_RSV_A/sequences.fasta $BASE_DIR/rsv/data/a
cp $BASE_DIR/rsv_nextstrain/Nextstrain_Ref_database/RSVA/metadata_world.tsv.gz $BASE_DIR/rsv/data/a
cp $BASE_DIR/rsv_nextstrain/Nextstrain_Ref_database/RSVA/sequences_world.fasta.xz   $BASE_DIR/rsv/data/a
DATA_DIR="$BASE_DIR/rsv/data/a"

cd $BASE_DIR/rsv/
conda activate nextstrain

python3 merge_and_clean.py a

# Decompress sequences_world.fasta.xz
unxz -f ${DATA_DIR}/sequences_world.fasta.xz

# Merge local and world sequences
cat ${DATA_DIR}/sequences.fasta ${DATA_DIR}/sequences_world.fasta > ${DATA_DIR}/combined_sequences.fasta

conda deactivate 
conda activate SEQKIT

seqkit rmdup -n ${DATA_DIR}/combined_sequences.fasta -o ${DATA_DIR}/sequences.fasta
rm ${DATA_DIR}/combined_sequences.fasta
xz -f ${DATA_DIR}/sequences.fasta

# Zip metadata_cleaned.tsv before removing it
awk -F'\t' 'NR==1 || !seen[$1]++' ${DATA_DIR}/metadata_cleaned.tsv > ${DATA_DIR}/metadata_unique.tsv

gzip ${DATA_DIR}/metadata_unique.tsv
mv ${DATA_DIR}/metadata_unique.tsv.gz ${DATA_DIR}/metadata.tsv.gz

# Remove intermediate files, keep only metadata.tsv.gz and sequences.fasta.xz
rm ${DATA_DIR}/metadata.tsv
rm ${DATA_DIR}/metadata_world.tsv.gz
rm ${DATA_DIR}/sequences_world.fasta

# Organize and quality checks RSV B data
cp $BASE_DIR/rsv_nextstrain/virus_RSV_B/metadata.tsv $BASE_DIR/rsv/data/b
cp $BASE_DIR/rsv_nextstrain/virus_RSV_B/sequences.fasta $BASE_DIR/rsv/data/b
cp $BASE_DIR/rsv_nextstrain/Nextstrain_Ref_database/RSVB/metadata_world.tsv.gz $BASE_DIR/rsv/data/b
cp $BASE_DIR/rsv_nextstrain/Nextstrain_Ref_database/RSVB/sequences_world.fasta.xz   $BASE_DIR/rsv/data/b
DATA_DIR="$BASE_DIR/rsv/data/b"

conda deactivate 
conda activate nextstrain
python merge_and_clean.py b
conda deactivate 
conda activate SEQKIT

# Decompress sequences_world.fasta.xz
unxz -f ${DATA_DIR}/sequences_world.fasta.xz

# Merge local and world sequences
cat ${DATA_DIR}/sequences.fasta ${DATA_DIR}/sequences_world.fasta > ${DATA_DIR}/combined_sequences.fasta

seqkit rmdup -n ${DATA_DIR}/combined_sequences.fasta -o ${DATA_DIR}/sequences.fasta
rm ${DATA_DIR}/combined_sequences.fasta
xz -f ${DATA_DIR}/sequences.fasta

# Zip metadata_cleaned.tsv before removing it
awk -F'\t' 'NR==1 || !seen[$1]++' ${DATA_DIR}/metadata_cleaned.tsv > ${DATA_DIR}/metadata_unique.tsv

gzip ${DATA_DIR}/metadata_unique.tsv
mv ${DATA_DIR}/metadata_unique.tsv.gz ${DATA_DIR}/metadata.tsv.gz

# Remove intermediate files, keep only metadata.tsv.gz and sequences.fasta.xz
rm ${DATA_DIR}/metadata.tsv
rm ${DATA_DIR}/metadata_world.tsv.gz
rm ${DATA_DIR}/sequences_world.fasta


#conda activate nextstrain

cd $BASE_DIR/rsv

echo "Making the Nextstrain build."
snakemake -j4 -p --configfile config/config.yaml

echo "Build finished. Copying auspice files to N for inspection."

# Copy and rename the builds files
cp $BASE_DIR/rsv/auspice/*.json $OUT_DIR

# Get the date
DATE=$(date +%Y-%m-%d)

# Rename builds
cp $OUT_DIR/rsv_a_genome_all-time.json $OUT_DIR/rsv_a_${DATE}.json
mv $OUT_DIR/rsv_a_genome_all-time.json $OUT_DIR/rsv_a_latest.json

cp $OUT_DIR/rsv_b_genome_all-time.json $OUT_DIR/rsv_b_${DATE}.json
mv $OUT_DIR/rsv_b_genome_all-time.json $OUT_DIR/rsv_b_latest.json

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR_ANALYSIS <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

# Clean up
rm -rf $TMP_DIR
rm -rf $BASE_DIR/rsv



