#!/usr/bin/env bash

# TODO
# [] Replace HCV_test_tanoti with an input variable

# First mount N and 3-Sekvenseringsbiblioteker

### Prepare the run ###
# Create samplesheet by running the supplied Rscript in a docker container.
docker run --rm -v /mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/NGS_SEQ-20240126-01/:/mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/NGS_SEQ-20240126-01/ -v $(pwd):/home docker.io/jonbra/tidyverse_seqinr:2.0 Rscript /home/bin/create_samplesheet.R /mnt/N/NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run/NGS_SEQ-20240126-01/ /home/test_samplesheet.csv "HCV"

# Export the access token for web monitoring with tower
export TOWER_ACCESS_TOKEN=

# Activate the conda environment that holds Nextflow
conda activate NEXTFLOW

## Run the main pipeline
nextflow run main.nf -profile server -params-file params.json -w /mnt/tempdata/work -with-tower -bg

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

for bam in $(ls HCV_test_tanoti/tanoti/*.bam)
do
input=$(basename $bam)
docker run --rm \
    --name gluetools \
    -v $(pwd)/HCV_test_tanoti/tanoti:/opt/bams \
    -w /opt/bams \
    --link gluetools-mysql \
    cvrbioinformatics/gluetools:latest gluetools.sh \
        -p cmd-result-format:json \
        -EC \
        -i project hcv module phdrReportingController invoke-function reportBam ${input} 15.0 > HCV_test_tanoti/hcvglue/${input%".bam"}.json || true
done

docker stop gluetools-mysql 
# Remove the image
docker rm gluetools-mysql

## Run the Glue json parser to merge all the json results into one file
docker run --rm \
    -v $(pwd)/HCV_test_tanoti/hcvglue:/hcvglue \
    -v $(pwd)/bin/:/bin \
    -w /hcvglue \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /bin/GLUE_json_parser.R

## Join the Glue results with the mapping summaries
docker run --rm \
    -v $(pwd)/HCV_test_tanoti/hcvglue:/hcvglue \
    -v $(pwd)/HCV_test_tanoti/summarize:/summarize \
    -v $(pwd)/bin/:/bin \
    -w /summarize \
    docker.io/jonbra/tidyverse_seqinr:2.0 \
    Rscript /bin/join_glue_report_with_summary.R

## Then move the results to the N: drive
