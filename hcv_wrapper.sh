#!/usr/bin/env bash

# TODO
- [] Use smbclient to copy the fastq files to the server. And then create the samplesheet 
- [] Run the script as ngs user.
- Add if statement if the docker exec command for glue fails. Sometimes it throws an error

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: dev

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (e.g., NGS_SEQ_20240214-03)"
    echo "  -a, --agens       Specify agens (e.g., HCV and ROV)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""

while getopts "hr:a:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        ?) usage ;;
    esac
done

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=eyJ0aWQiOiA4ODYzfS5mZDM1MjRkYTMwNjkyOWE5ZjdmZjdhOTVkODk3YjI5YTdjYzNlM2Zm
# Add workspace ID for Virus_NGS
export TOWER_WORKSPACE_ID=150755685543204

## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/${YEAR}/Illumina_Run/$RUN
SMB_OUTPUT=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/$AGENS/$YEAR/

# Switch to local user
#sudo -u ngs /bin/bash

# Check if the viralseq directory exists, if not clone it from GitHub
if [ -d "viralseq" ]; then
  # Make sure to pull the latest version
  git -C viralseq/ pull origin master
else
  git clone https://github.com/jonbra/viralseq.git
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
echo "Creating samplesheet"
docker run --rm \
    -v $TMP_DIR/:$TMP_DIR/ \
    -v $HOME/viralseq/bin:/scripts \
    -v $HOME/$RUN/:/home \
    -w /home \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/create_samplesheet.R $TMP_DIR samplesheet.csv ${AGENS}

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

# Start the pipeline
echo "Map to references and create consensus sequences"
nextflow run $HOME/viralseq/main.nf -profile server --input "$HOME/$RUN/samplesheet.csv" --outdir "$HOME/$RUN" --agens $AGENS -with-tower -bg

## Then run HCV GLUE on the bam files
# First make a directory for the GLUE files

echo "Run HCV-GLUE for genotyping and resistance analysis"
mkdir $HOME/$RUN/hcvglue

# Pull the latest images
docker pull cvrbioinformatics/gluetools-mysql:latest
docker pull cvrbioinformatics/gluetools:latest

# Remove the container in case it is already running
docker stop gluetools-mysql
docker rm gluetools-mysql
#docker run --detach --name gluetools-mysql cvrbioinformatics/gluetools-mysql:latest

# Install the pre-built GLUE HCV project
#docker start gluetools-mysql
docker run --detach --name gluetools-mysql cvrbioinformatics/gluetools-mysql:latest
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
    -v $(pwd)/viralseq/bin/:/scripts \
    -w /hcvglue \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/GLUE_json_parser.R

## Join the Glue results with the mapping summaries
echo "Merge GLUE and mapping results"
docker run --rm \
    -v $HOME/$RUN/hcvglue:/hcvglue \
    -v $HOME/$RUN/summarize:/summarize \
    -v $(pwd)/viralseq/bin/:/scripts \
    -w /summarize \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/join_glue_report_with_summary.R

## Rename LW import file 
mv $HOME/$RUN/summarize/Genotype_mapping_summary_long_LW_import_with_glue.csv $HOME/$RUN/summarize/Genotype_mapping_summary_long_LW_import.csv 

## Then move the results to the N: drive
echo "Moving results to the N: drive"

#smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_OUTPUT <<EOF
#prompt OFF
#recurse ON
#lcd $BASE_DIR/fastq
#mput *
#EOF

## Then clean up the Nextflow run work directory
nextflow clean -f
