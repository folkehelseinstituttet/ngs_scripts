#!/usr/bin/env bash

# Check if the ngs_scripts directory exists, if not clone it from GitHub
cd $HOME
if [ -d "ngs_scripts" ]; then
  # Make sure to pull the latest version
  git -C ngs_scripts/ pull origin main
else
  git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
fi

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/nextstrain
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_INPUT=Virologi/NGS/tmp/

## Move input files from N

# Create directory to hold the output of the analysis
mkdir $TMP_DIR

echo "Getting files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_INPUT <<EOF
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
    -v $HOME/ngs_scripts/nextstrain:/scripts \
    -w $TMP_DIR \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/index_fasta.R

# Parse the Gisaid files and prepare Nextstrain inputs
echo "Preparing Nextstrain input files from Gisaid. Takes around 30 minutes..."
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR \
    -v $HOME/ngs_scripts/nextstrain:/scripts \
    -v $HOME/ncov/data/SC2_weekly/:$HOME/ncov/data/SC2_weekly/ \
    -w $HOME/ncov/data/SC2_weekly/ \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/parse_Gisaid_fasta_and_metadata.R

# Parse BN files and prepare Nextstrain inputs
echo "Preparing Nextstrain input files from BN. Takes around 30 minutes..."
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR \
    -v /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/:/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/ \
    -v $HOME/ngs_scripts/nextstrain:/scripts \
    -v $HOME/ncov/data/SC2_weekly/:$HOME/ncov/data/SC2_weekly/ \
    -w $HOME/ncov/data/SC2_weekly/ \
    docker.io/jonbra/rsamtools:2.0 \
    Rscript /scripts/get_data_from_BN.R
    
# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/builds.yaml $HOME/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/colors_norwaydivisions.tsv $HOME/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/my_description.md $HOME/ncov/my_profiles
cp $HOME/ngs_scripts/nextstrain/my_auspice_config.json $HOME/ncov/my_profiles

conda activate nextstrain

cd $HOME/ncov 

echo "Making the Nextstrain build..."
nextstrain build . --configfile my_profiles//builds.yaml --cores 14 --forceall

