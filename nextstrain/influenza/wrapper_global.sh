
#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Get the date
DATE=$(date +%Y-%m-%d)

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/flu_nextstrain
OUT_DIR=/mnt/tempdata/flu_nextstrain_out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/flu_nextstrain
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
  cd seasonal-flu
  # Make sure to pull the latest version
  git pull origin master
  git stash
  git pull origin master
  git stash pop
else
  git clone https://github.com/nextstrain/seasonal-flu.git
fi

## Make output dir
mkdir $OUT_DIR

## Make NIPH-profile
cd seasonal-flu
mkdir profiles/niph
mkdir data
mkdir data/h1n1pdm
mkdir data/h3n2
mkdir data/vic
cd $BASE_DIR

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

cd $TMP_DIR/H1
cat *HA*.fasta > raw_sequences_ha_org.fasta
cat *NA*.fasta > raw_sequences_na_org.fasta
sed 's/|.*//' raw_sequences_ha_org.fasta > raw_sequences_ha.fasta
sed 's/|.*//' raw_sequences_na_org.fasta > raw_sequences_na.fasta

cd $TMP_DIR/H3
cat *HA*.fasta > raw_sequences_ha_org.fasta
cat *NA*.fasta > raw_sequences_na_org.fasta
sed 's/|.*//' raw_sequences_ha_org.fasta > raw_sequences_ha.fasta
sed 's/|.*//' raw_sequences_na_org.fasta > raw_sequences_na.fasta

cd $TMP_DIR/VIC
cat *HA*.fasta > raw_sequences_ha_org.fasta
cat *NA*.fasta > raw_sequences_na_org.fasta
sed 's/|.*//' raw_sequences_ha_org.fasta > raw_sequences_ha.fasta
sed 's/|.*//' raw_sequences_na_org.fasta > raw_sequences_na.fasta

# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/influenza/global/builds.yaml $BASE_DIR/seasonal-flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/global/config.yaml $BASE_DIR/seasonal-flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/global/prepare_data.smk $BASE_DIR/seasonal-flu/profiles/niph

cp $BASE_DIR/flu_nextstrain/H1/metadata.xls $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H1/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H1/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H3/metadata.xls $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/H3/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/H3/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/VIC/metadata.xls $BASE_DIR/seasonal-flu/data/vic
cp $BASE_DIR/flu_nextstrain/VIC/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/vic
cp $BASE_DIR/flu_nextstrain/VIC/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/vic




conda activate nextstrain

cd $BASE_DIR/seasonal-flu 

echo "Making the Nextstrain build."
nextstrain build .  --configfile profiles/niph/builds.yaml --cores 14 

echo "Build finished. Copying auspice files to N for inspection."

# Copy and rename the builds files
cp $BASE_DIR/seasonal-flu/auspice/*.json $OUT_DIR

# Get the date
DATE=$(date +%Y-%m-%d)

# Rename builds
# H1N1
cp $OUT_DIR/h1n1_fhi_ha.json $OUT_DIR/flu_a_h1n1_ha_${DATE}.json
mv $OUT_DIR/h1n1_fhi_ha.json $OUT_DIR/flu_a_h1n1_ha_latest.json

cp $OUT_DIR/h1n1_fhi_ha_tip-frequencies.json $OUT_DIR/flu_a_h1n1_ha_${DATE}_tip-frequencies.json
mv $OUT_DIR/h1n1_fhi_ha_tip-frequencies.json $OUT_DIR/flu_a_h1n1_ha_latest_tip-frequencies.json

cp $OUT_DIR/h1n1_fhi_na.json $OUT_DIR/flu_a_h1n1_na_${DATE}.json
mv $OUT_DIR/h1n1_fhi_na.json $OUT_DIR/flu_a_h1n1_na_latest.json

cp $OUT_DIR/h1n1_fhi_na_tip-frequencies.json $OUT_DIR/flu_a_h1n1_na_${DATE}_tip-frequencies.json
mv $OUT_DIR/h1n1_fhi_na_tip-frequencies.json $OUT_DIR/flu_a_h1n1_na_latest_tip-frequencies.json

# H3N2
cp $OUT_DIR/h3n2_fhi_ha.json $OUT_DIR/flu_a_h3n2_ha_${DATE}.json
mv $OUT_DIR/h3n2_fhi_ha.json $OUT_DIR/flu_a_h3n2_ha_latest.json

cp $OUT_DIR/h3n2_fhi_ha_tip-frequencies.json $OUT_DIR/flu_a_h3n2_ha_${DATE}_tip-frequencies.json
mv $OUT_DIR/h3n2_fhi_ha_tip-frequencies.json $OUT_DIR/flu_a_h3n2_ha_latest_tip-frequencies.json

cp $OUT_DIR/h3n2_fhi_na.json $OUT_DIR/flu_a_h3n2_na_${DATE}.json
mv $OUT_DIR/h3n2_fhi_na.json $OUT_DIR/flu_a_h3n2_na_latest.json

cp $OUT_DIR/h3n2_fhi_na_tip-frequencies.json $OUT_DIR/flu_a_h3n2_na_${DATE}_tip-frequencies.json
mv $OUT_DIR/h3n2_fhi_na_tip-frequencies.json $OUT_DIR/flu_a_h3n2_na_latest_tip-frequencies.json

# VIC
cp $OUT_DIR/vic_fhi_ha.json $OUT_DIR/flu_b_vic_ha_${DATE}.json
mv $OUT_DIR/vic_fhi_ha.json $OUT_DIR/flu_b_vic_ha_latest.json

cp $OUT_DIR/vic_fhi_ha_tip-frequencies.json $OUT_DIR/flu_b_vic_ha_${DATE}_tip-frequencies.json
mv $OUT_DIR/vic_fhi_ha_tip-frequencies.json $OUT_DIR/flu_b_vic_ha_latest_tip-frequencies.json

cp $OUT_DIR/vic_fhi_na.json $OUT_DIR/flu_b_vic_na_${DATE}.json
mv $OUT_DIR/vic_fhi_na.json $OUT_DIR/flu_b_vic_na_latest.json

cp $OUT_DIR/vic_fhi_na_tip-frequencies.json $OUT_DIR/flu_b_vic_na_${DATE}_tip-frequencies.json
mv $OUT_DIR/vic_fhi_na_tip-frequencies.json $OUT_DIR/flu_b_vic_na_latest_tip-frequencies.json

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR_ANALYSIS <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

# Clean up
rm -rf $TMP_DIR
rm -rf $BASE_DIR/seasonal-flu



