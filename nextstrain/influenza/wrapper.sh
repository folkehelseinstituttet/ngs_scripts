#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/flu_nextstrain
OUT_DIR=/mnt/tempdata/flu_nextstrain_out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/flu_nextstrain

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

## Make NIPH-profile
cd seasonal-flu/profiles
mkdir niph
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

# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/builds.yaml $BASE_DIR/seasonal_flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/config.yaml $BASE_DIR/seasonal_flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/prepare_data.smk $BASE_DIR/seasonal_flu/profiles/niph

conda activate nextstrain

cd $BASE_DIR/seasonal_flu 

echo "Making the Nextstrain build.
nextstrain build .  --configfile profiles/niph/builds.yaml --cores 14 --forceall

echo "Build finished. Copying auspice files to N for inspection."
# Copy the nohup output file to the OUT_DIR folder for easier copying to N
cp $HOME/nohup.out $OUT_DIR

# Copy and rename the builds files
cp $BASE_DIR/ncov/auspice/*.json $OUT_DIR

# Get the date
DATE=$(date +%Y-%m-%d)

# Rename builds
mv $OUT_DIR/ncov_omicron-ba-2-86.json $OUT_DIR/ncov_omicron-ba-2-86_${DATE}.json
mv $OUT_DIR/ncov_omicron-ba-2-86_root-sequence.json $OUT_DIR/ncov_omicron-ba-2-86_${DATE}_root-sequence.json
mv $OUT_DIR/ncov_omicron-ba-2-86_tip-frequencies.json $OUT_DIR/ncov_omicron-ba-2-86_${DATE}_tip-frequencies.json

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $OUT_DIR
mput *
EOF

# Clean up
rm -rf $TMP_DIR
rm $BASE_DIR/ncov/data/SC2_weekly/*


