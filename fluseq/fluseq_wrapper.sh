
#!/usr/bin/env bash

# Activate conda
source ~/miniconda3/etc/profile.d/conda.sh

# TODO

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: dev

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g., INF077)"
    echo "  -a, --agens       Specify agens (e.g., Influensa and Avian)"
    echo "  -s, --season      Specify the season directory of the fastq files on the N-drive (e.g. Ses2425)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
SEASON=""
YEAR=""

while getopts "hr:a:y:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        s) SEASON="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        ?) usage ;;
    esac
done

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
rm -rf $HOME/fluseq

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/3-Summary/${SEASON}/results
# Uncomment for testing
#SMB_DIR=Virologi/NGS/tmp/

# Old data is moved to Arkiv
current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/${YEAR}/Nanopore_Grid_Run/$RUN
elif [ "$YEAR" -lt "$current_year" ]; then 
	SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/Arkiv/${YEAR}/Nanopore_Grid_Run/$RUN
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
    
# Create a samplesheet by running the supplied Rscript in a docker container.
#ADD CODE FOR HANDLING OF SAMPLESHEET

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

# Make sure the latest pipeline is available
#nextflow pull folkehelseinstituttet/viralseq

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow run RasmusKoRiis/nf-core-fluseq/main.nf -r master -profile server --input "$HOME/$RUN/samplesheet.csv" --outdir "$HOME/$RUN" --agens $AGENS -with-tower --platform "illumina"


## Then move the results to the N: drive
echo "Moving results to the N: drive"
mkdir $HOME/out
mv $RUN/ out/

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $HOME/out/
mput *
EOF

## Clean up
#nextflow clean -f
#rm -rf $HOME/out
#rm -rf $TMP_DIR
