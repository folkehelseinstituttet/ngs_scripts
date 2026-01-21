
#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# TODO

# Maintained by: Rasmus Kopperud Riis (rasmuskopperud.riis@fhi.no)
# Version: dev

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h                 Display this help message"
    echo "  -r <run>           Specify the run name (e.g., INF077) (required)"
    echo "  -p <primer>        Specify the primer version (e.g., V5.4.2)"
    echo "  -a <agens>         Specify agens (e.g., sars) (required)"
    echo "  -s <season>        Specify the season directory of the fastq files on the N-drive (e.g., Ses2425)"
    echo "  -y <year>          Specify the year directory of the fastq files on the N-drive"
    echo "  -v <validation>    Specify validation flag (e.g., VER)"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""
PRIMER=""
VALIDATION_FLAG=""

# Parse options
while getopts "hr:p:a:s:y:v:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        p) PRIMER="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        v) VALIDATION_FLAG="$OPTARG" ;;
        ?) usage ;;
    esac
done

# Print parsed arguments (for debugging)
echo "Run: $RUN"
echo "Primer: $PRIMER"
echo "Agens: $AGENS"
echo "Season: $SEASON"
echo "Year: $YEAR"
echo "Validation Flag: $VALIDATION_FLAG"

# Make sure the latest version of the ngs_scripts repo is present locally

# Define the directory and the GitHub repository URL
REPO="$HOME/ngs_scripts"
REPO_URL="https://github.com/folkehelseinstituttet/ngs_scripts.git"

# Check if the directory exists
if [ -d "$REPO" ]; then
    echo "Directory 'ngs_scripts' exists. Pulling latest changes..."
    cd "$REPO"
    git pull
else
    echo "Directory 'ngs_scripts' does not exist. Cloning repository..."
    git clone "$REPO_URL" "$REPO"
fi

cd $HOME


# Sometimes the pipeline has been cloned locally. Remove it to avoid version conflicts
rm -rf $HOME/sarsseq

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/${YEAR}
#SMB_DIR_ANALYSIS=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/powerBI

# If validation flag is set, update SMB_DIR_ANALYSIS and skip the results move step
if [ -n "$VALIDATION_FLAG" ]; then
    SMB_DIR_ANALYSIS="Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-Validering/1-sarsseq-validering/Run"
    SKIP_RESULTS_MOVE=true
else
    SKIP_RESULTS_MOVE=false
fi


current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT=Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}
elif [ "$YEAR" -lt "$current_year" ]; then 
	SMB_INPUT=Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/${RUN}
else 
	echo "Error: Year cannot be larger than $current_year"
	exit 1
fi


# Create directory to hold the output of the analysis
mkdir -p $HOME/$RUN
mkdir $TMP_DIR

### Prepare the run ###

echo "Copying fastq files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_INPUT <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF


## Set up 
SAMPLEDIR=$(find "$TMP_DIR/$RUN" -type d -path "*X*/fastq_pass" -print -quit)
SAMPLESHEET=/mnt/tempdata/fastq/${RUN}.csv
SARS_DATABASE=/mnt/tempdata/sars_db/assets

# Create a samplesheet by running the supplied Rscript in a docker container.
#ADD CODE FOR HANDLING OF SAMPLESHEET

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

# Make sure the latest pipeline is available
#nextflow pull folkehelseinstituttet/viralseq

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow pull RasmusKoRiis/nf-core-sars
nextflow run RasmusKoRiis/nf-core-sars/main.nf \
  -r master \
  -profile docker,server \
  --input "$SAMPLESHEET" \
  --samplesDir "$SAMPLEDIR" \
  --outdir "$HOME/$RUN" \
  --primerdir $SARS_DATABASE/$PRIMER \
  --reference  "$SARS_DATABASE/primer_schemes/ncov-2019_midnight/v3.0.0/ncov-2019_midnight.reference.fasta" \
  --primer_bed "$SARS_DATABASE/primer_schemes/ncov-2019_midnight/v3.0.0/ncov-2019_midnight.scheme.bed" \
  --runid "$RUN" \
  --spike "$SARS_DATABASE/Spike_mAbs_inhibitors.csv" \
  --rdrp "$SARS_DATABASE/RdRP_inhibitors.csv" \
  --clpro "$SARS_DATABASE/3CLpro_inhibitors.csv" \
  --release_version "v1.0.0" 

echo "Moving results to the N: drive"
mkdir $HOME/out_sarsseq
mv $RUN/ out_sarsseq/

if [ "$SKIP_RESULTS_MOVE" = false ]; then
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $HOME/out_sarsseq/
mput *
EOF
fi

if [ "$SKIP_RESULTS_MOVE" = true ]; then
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR_ANALYSIS <<EOF
prompt OFF
lcd $HOME/out_sarsseq/$RUN/report/
cd ${SMB_DIR_ANALYSIS}
mput *.csv
EOF
fi


## Clean up
nextflow clean -f
#rm -rf $HOME/out
rm -rf $TMP_DIR
