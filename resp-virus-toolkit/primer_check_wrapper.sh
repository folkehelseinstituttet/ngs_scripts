#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# Get the date
DATE=$(date +%Y-%m-%d)

## Set up environment
BASE_DIR=/mnt/tempdata
TMP_DIR=/mnt/tempdata/flu_toolkit
OUT_DIR=/mnt/tempdata/flu_toolkit_out
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/tmp/flu_toolkit
SMB_DIR_ANALYSIS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/12-PRIMER_CHECK/${DATE}_PRIMER_CHECK
SMB_DIR_UPLOAD=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/12-PRIMER_CHECK/${DATE}_PRIMER_CHECK

# Check if the ngs_scripts directory exists, if not clone it from GitHub
cd $HOME
if [ -d "ngs_scripts" ]; then
  # Make sure to pull the latest version
  git -C ngs_scripts/ pull origin main
else
  git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
fi

# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
rm -rf $HOME/fluseq

## Make output dir
mkdir $OUT_DIR

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


#IF STATEMENT FOR PRIMER CHECK

#Primerdatabase
PRIMER_DATABASE_SERVER=/mnt/tempdata/influensa_db/flu_primer_db
PRIMER_DATABSE_N=/mnt/tempdata/influensa_db/flu_seq_db/Mammalian_Mutations_of_Intrest_2324.xlsx

echo "Update perimer databse"
smbclient $SMB_HOST -A $SMB_AUTH -D $PRIMER_DATABSE_N <<EOF
prompt OFF
recurse ON
lcd $PRIMER_DATABASE_SERVER
mget *
EOF

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow pull RasmusKoRiis/nf-core-fluseq
nextflow run RasmusKoRiis/nf-core-fluseq/main.nf \
  -r master \
  -profile docker,server \
  --input "$SAMPLESHEET" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --ha_database "$HA_DATABASE" \
  --na_database "$NA_DATABASE" \
  --mamalian_mutation_db "$MAMMALIAN_MUTATION_DATABASE" \
  --inhibtion_mutation_db "$INHIBTION_MUTATION_DATABASE" \
  --sequence_references "$SEQUENCE_REFERENCES" \
  --nextclade_dataset  "$NEXTCLADE_DATASET" \
  --reassortment_database  "$REASSORTMENT_DATABASE" \
  --runid "$RUN" \
  --release_version "v1.0.2" 

# Copy nextstrain build files into the ncov directory
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/builds.yaml $BASE_DIR/seasonal-flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/config.yaml $BASE_DIR/seasonal-flu/profiles/niph
cp $HOME/ngs_scripts/nextstrain/influenza/fhi/prepare_data.smk $BASE_DIR/seasonal-flu/profiles/niph

cp $BASE_DIR/flu_nextstrain/H1/metadata.xls $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H1/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H1/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/h1n1pdm
cp $BASE_DIR/flu_nextstrain/H3/metadata.xls $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/H3/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/H3/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/h3n2
cp $BASE_DIR/flu_nextstrain/VIC/metadata.xls $BASE_DIR/seasonal-flu/data/vic
cp $BASE_DIR/flu_nextstrain/VIC/raw_sequences_ha.fasta $BASE_DIR/seasonal-flu/data/vic
cp $BASE_DIR/flu_nextstrain/VIC/raw_sequences_na.fasta $BASE_DIR/seasonal-flu/data/vic

conda activate NEXTSTRAIN

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
