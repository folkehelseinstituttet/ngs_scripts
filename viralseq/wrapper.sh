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
    echo "  -r, --run         Specify the run name (e.g., NGS_SEQ-20240214-03)"
    echo "  -a, --agens       Specify agens (e.g., HCV and ROV)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""

while getopts "hr:a:y:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
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
rm -rf $HOME/viralseq

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
# Old data is moved to Arkiv
current_year=$(date +"%Y")
if [ "$YEAR" -eq "$current_year" ]; then
    SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/${YEAR}/Illumina_Run/$RUN
elif [ "$YEAR" -lt "$current_year" ]; then 
	SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/Arkiv/${YEAR}/Illumina_Run/$RUN
else 
	echo "Error: Year cannot be larger than $current_year"
	exit 1
fi
# For testing
SMB_OUTPUT=Virologi/NGS/tmp/
#SMB_OUTPUT=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/$AGENS/$YEAR/

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
echo "Creating samplesheet"
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR/ \
    -v $HOME/$RUN:/out \
    docker.io/jonbra/create_samplesheet:1.0 \
    Rscript create_samplesheet.R $TMP_DIR /out/samplesheet.csv ${AGENS}

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

# Make sure the latest pipeline is available
nextflow pull jonbra/viralseq

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow run jonbra/viralseq/main.nf -r master -profile server --input "$HOME/$RUN/samplesheet.csv" --outdir "$HOME/$RUN" --agens $AGENS -with-tower --platform "illumina"

## Then run HCV GLUE on the bam files
# First make a directory for the GLUE files

echo "Run HCV-GLUE for genotyping and resistance analysis"
mkdir $HOME/$RUN/hcvglue

# Remove the container in case it is already running
docker stop gluetools-mysql
docker rm gluetools-mysql

# Start the gluetools-mysql container in the background
#docker start gluetools-mysql
docker run --detach --name gluetools-mysql cvrbioinformatics/gluetools-mysql:latest

# Install the pre-built GLUE HCV project
# Sometimes the docker execution fails. Retry up to 5 times

# Set the timeout duration (in seconds)
TIMEOUT=300
START_TIME=$(date +%s)

until docker exec gluetools-mysql mysql --user=root --password=root123 -e "status" &> /dev/null
do
  echo "Waiting for database connection..."
  # Wait for two seconds before checking again
  sleep 2

# Check if the timeout has been reached
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
  if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
    echo "Timeout reached. Exiting script."
    exit 1
  fi
done

echo "MySQL is up!"

# When the MySQL database is ready, Install a pre-built HCV GLUE dataset in the gluetools-mysql container
docker exec gluetools-mysql installGlueProject.sh ncbi_hcv_glue

# Make a for loop over all bam files and run HCV-GLUE
## Adding || true to the end of the command to prevent the pipeline from failing if the bam file is not valid

for bam in $(ls $HOME/$RUN/samtools/*nodup.bam)
do
input=$(basename $bam)
docker run --rm \
    --name gluetools \
    -v $HOME/$RUN/samtools:/opt/bams \
    -w /opt/bams \
    --link gluetools-mysql \
    cvrbioinformatics/gluetools:latest gluetools.sh \
        -p cmd-result-format:json \
        -EC \
        -i project hcv module phdrReportingController invoke-function reportBam ${input} 15.0 > $HOME/$RUN/hcvglue/${input%".bam"}.json || true
done

docker stop gluetools-mysql 
# Remove the image
docker rm gluetools-mysql

## Run the Glue json parser to merge all the json results into one file
echo "Parsing the GLUE results"
docker run --rm \
    -v $HOME/$RUN/hcvglue:/hcvglue \
    -v $HOME/.nextflow/assets/jonbra/viralseq/bin/:/scripts \
    -w /hcvglue \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/GLUE_json_parser.R major

## Join the Glue results with the mapping summaries
echo "Merge GLUE and mapping results"
docker run --rm \
    -v $HOME/$RUN/hcvglue:/hcvglue \
    -v $HOME/$RUN/summarize:/summarize \
    -v $HOME/.nextflow/assets/jonbra/viralseq/bin/:/scripts \
    -w /summarize \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/join_glue_report_with_summary.R

## Rename LW import file 
mv $HOME/$RUN/summarize/Genotype_mapping_summary_long_LW_import_with_glue.csv $HOME/$RUN/summarize/Genotype_mapping_summary_long_LW_import.csv 

## Then move the results to the N: drive
echo "Moving results to the N: drive"
mkdir $HOME/out
mv $RUN/ out/

smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_OUTPUT <<EOF
prompt OFF
recurse ON
lcd $HOME/out/
mput *
EOF

## Clean up
#nextflow clean -f
#rm -rf $HOME/out
#rm -rf $TMP_DIR