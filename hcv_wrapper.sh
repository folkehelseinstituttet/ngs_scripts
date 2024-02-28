#!/usr/bin/env bash

# TODO
# [] Replace HCV_test_tanoti with an input variable
# [] Where to start the script? 
# [] Drop samplesheet from the params.json file and enter via the command line
# [] Save the tower token in a hidden file

Run=$1

# Create a directory for the analysis
mkdir ${Run}

# First mount N and 3-Sekvenseringsbiblioteker

### Prepare the run ###

# Check if the viralseq directory exists, if not clone it from GitHub
if [ -d "viralseq" ]; then
  # Make sure to pull the latest version
  git -C viralseq/ pull origin master
else
  git clone https://github.com/jonbra/viralseq.git
fi

# Create a samplesheet by running the supplied Rscript in a docker container.
docker run --rm \
    -v /mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/NGS_SEQ-20240126-01/:/mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/NGS_SEQ-20240126-01/ \
    -v $(pwd)/viralseq/bin:/scripts \
    -v $(pwd)/${Run}:/home \
    -w /home \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/create_samplesheet.R /mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/${Run}/ /home/samplesheet.csv "HCV"

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=

### Run the main pipeline ###

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

# Start the pipeline
nextflow run viralseq/main.nf -profile server -params-file "$PWD/$Run/params.json" --input "$PWD/$Run/samplesheet.csv" -w /mnt/tempdata/work -with-tower -bg

## Then run HCV GLUE on the bam files
# First make a directory for the GLUE files
mkdir HCV_test_tanoti/hcvglue

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

for bam in $(ls viralseq/HCV_test_tanoti/samtools/*nodup.bam)
do
input=$(basename $bam)
docker run --rm \
    --name gluetools \
    -v $(pwd)/viralseq/HCV_test_tanoti/samtools:/opt/bams \
    -w /opt/bams \
    --link gluetools-mysql \
    cvrbioinformatics/gluetools:latest gluetools.sh \
        -p cmd-result-format:json \
        -EC \
        -i project hcv module phdrReportingController invoke-function reportBam ${input} 15.0 > viralseq/HCV_test_tanoti/hcvglue/${input%".bam"}.json || true
done

docker stop gluetools-mysql 
# Remove the image
docker rm gluetools-mysql

## Run the Glue json parser to merge all the json results into one file
docker run --rm \
    -v $(pwd)/viralseq/HCV_test_tanoti/hcvglue:/hcvglue \
    -v $(pwd)/viralseq/bin/:/scripts \
    -w /hcvglue \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/GLUE_json_parser.R

## Join the Glue results with the mapping summaries
docker run --rm \
    -v $(pwd)/viralseq/HCV_test_tanoti/hcvglue:/hcvglue \
    -v $(pwd)/viralseq/HCV_test_tanoti/summarize:/summarize \
    -v $(pwd)/viralseq/bin/:/scripts \
    -w /summarize \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /scripts/join_glue_report_with_summary.R

## Then move the results to the N: drive

## Then clean up the Nextflow run work directory
nextflow clean -f
