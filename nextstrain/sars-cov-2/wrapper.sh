#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/nextstrain
OUT_DIR=/mnt/tempdata/out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/

# Check if the ngs_scripts directory exists, if not clone it from GitHub
cd $HOME
if [ -d "ngs_scripts" ]; then
  # Make sure to pull the latest version
  git -C ngs_scripts/ pull origin main
else
  git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
fi

# Check if the ncov repo exists, if not clone it from GitHub
cd $BASE_DIR
if [ -d "ncov" ]; then
  cd ncov
  # Make sure to pull the latest version
  git pull origin master
  git stash
  git pull origin master
  git stash pop
else
  git clone https://github.com/nextstrain/ncov.git
fi

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

# Untar the Gisaid files
echo "Untaring the Gisaid files. Takes around 30 minutes..."
cd $TMP_DIR
tar -xf metadata*.tar.xz
rm readme.txt
tar -xf sequences*.tar.xz
rm readme.txt
rm *.tar.xz
cd $HOME

# Index the Gisaid fasta file
echo "Indexing the Gisaid fasta file. Takes an hour or so..."
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR \
    -v $HOME/ngs_scripts/nextstrain/sars-cov-2:/scripts \
    -w $TMP_DIR \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/index_fasta.R

# Parse the Gisaid files and prepare Nextstrain inputs
echo "Preparing Nextstrain input files from Gisaid. Takes around 30 minutes..."
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR \
    -v $HOME/ngs_scripts/nextstrain/sars-cov-2:/scripts \
    -v $BASE_DIR/ncov/data/SC2_weekly/:$BASE_DIR/ncov/data/SC2_weekly/ \
    -w $BASE_DIR/ncov/data/SC2_weekly/ \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/parse_Gisaid_fasta_and_metadata.R

# Parse BN files and prepare Nextstrain inputs
echo "Preparing Nextstrain input files from BN. Takes around 30 minutes..."
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR \
    -v /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/:/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/ \
    -v $HOME/ngs_scripts/nextstrain/sars-cov-2:/scripts \
    -v $BASE_DIR/ncov/data/SC2_weekly/:$BASE_DIR/ncov/data/SC2_weekly/ \
    -w $BASE_DIR/ncov/data/SC2_weekly/ \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/get_data_from_BN.R
    
# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/builds.yaml $BASE_DIR/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/pango_list.txt $BASE_DIR/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/colors_norwaydivisions.tsv $BASE_DIR/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/my_description.md $BASE_DIR/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/my_auspice_config.json $BASE_DIR/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/sars-cov-2/sites_ignored_for_tree_topology.txt $BASE_DIR/ncov/my_profiles 

conda activate nextstrain

cd $BASE_DIR/ncov 

echo "Making the Nextstrain build. Should not take too long. Max 1 hour..."
nextstrain build . --configfile my_profiles/builds.yaml --cores 14 --forceall

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


