#!/usr/bin/env bash

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: 1.0
# This script downloads fastq files from the BaseSpace server and transfers them to the N-drive.

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -p, --platform    Can be either nextseq or miseq"
    echo "  -r, --run         Specify run name (e.g. Run933 or NGS_SEQ-20240126-01)"
    echo "  -a, --agens       Specify agens (only required for HCV and ROV)"
    echo "  -y, --year        Specify the year the sequencing was performed (e.g. 2024)"
    exit 1
}

# Initialize variables
PLATFORM=""
RUN=""
AGENS=""
YEAR=""

while getopts "hp:r:a:y:" opt; do
    case "$opt" in
        h) usage ;;
        p) PLATFORM="$OPTARG" ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        ?) usage ;;
    esac
done

## Check if necessary software and files are present

# The script requires BaseSpace CLI installed (https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview)
# Check if the bs command is available
if ! command -v /home/ngs/bin/bs &> /dev/null
then
    echo "BaseSpace CLI could not be found"
    exit 1
fi

# There also has to be a BaseSpace credentials file: $HOME/.basespace/default.cfg
# Check if the file exists
if ! test -f ~/.basespace/default.cfg; then
  echo "BaseSpace credentials file does not exist."
  exit 1
fi

# Check if credential file exists
if ! test -f ~/.smbcreds; then
  echo "Credential file for transfer to N does not exist."
  exit 1
fi

## Set up environment
BASE_DIR=/mnt/tempdata/
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=NGS/3-Sekvenseringsbiblioteker/2024/Illumina_Run

# Make a fastq directory under tempdata. Download files here
mkdir -p $BASE_DIR/fastq

echo "Getting the Run ID on the BaseSpace server"
# List Runs on BaseSpace and get the Run id (third column separated by | and whitespaces)
id=$(/home/ngs/bin/bs list projects | grep "${RUN}" | awk -F '|' '{print $3}' | awk '{$1=$1};1')

echo "Downloading fastq files"
# Then download the fastq files
/home/ngs/bin/bs download project -i ${id} --extension=fastq.gz -o $BASE_DIR/fastq/${RUN}

# Execute commands based on the platform specified
if [[ $PLATFORM == "miseq" ]]; then
    echo "Running commands for MiSeq platform..."
    # Clean up the folder names
    RUN_DIR="$BASE_DIR/fastq/${RUN}"
    # Find only directories in the current directory. Loop through them and rename
    # mindepth 1 excludes the RUN_DIR directory. maxdepth 1 includes only the sudirectories of RUN_DIR
    find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' folder; do
        # Extract the name of the subdirectory
        dir_name=$(basename "$folder")
    
        # Extract the sample number and add Agens name
        new_name="${dir_name%%-*}-${AGENS}"

        # Rename the folder
        mv "$folder" "$RUN_DIR/$new_name"
    done

    echo "Transferring files to N"

    # Move to N:
    smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
    prompt OFF
    recurse ON
    lcd $BASE_DIR/fastq
    mput *
    EOF
    
    ## Clean up
    rm -rf fastq
elif [[ $PLATFORM == "nextseq" ]]; then
    echo "Running commands for NextSeq platform..."
    # Define the input and output directories
    RUN_NR="${RUN#Run}"
    INPUT_DIR="fastq"
    OUTPUT_DIR=$RUN"_NextSeq/merged"

    # Create the output directory if it doesn't exist
    mkdir -p "$OUTPUT_DIR"

    # Loop through each sample directory, create new subdirectories for each sample and copy the fastq files to the corresponding directory
    for fastq in "$INPUT_DIR"/*/*.fastq.gz; do
            # Extract the basename
            base=$(basename $fastq)
        
            # Extract the sample name
            sample_name=$(basename "$fastq"   | cut -f 1 -d "_")
        
            # Remove the run number prefix from the sample name
            sample_name_trimmed="${sample_name#$RUN_NR}"

            # Make directories for each sample
            mkdir -p ~/$OUTPUT_DIR/$sample_name_trimmed

            # Copy each fastq file
            echo "Moving $base to directory $sample_name_trimmed"
            cp $fastq ~/$OUTPUT_DIR/$sample_name_trimmed/$base
    done

    # Merge all R1 and R2 files for each sample
    # Loop through each directory in the "merged" directory
    for sample_dir in "$OUTPUT_DIR"/*; do
        if [ -d "$sample_dir" ]; then
        
            # Extract the sample name
            sample_name=$(basename "$sample_dir")
        
            # Concatenate all R1 files into a single file
            cat "$sample_dir"/*_R1_*.fastq.gz > "$sample_dir/${sample_name}_merged_R1.fastq.gz"
            echo "Concatenated R1 files for sample $sample_name"
        
            # Concatenate all R2 files into a single file
            cat "$sample_dir"/*_R2_*.fastq.gz > "$sample_dir/${sample_name}_merged_R2.fastq.gz"
            echo "Concatenated R2 files for sample $sample_name"

            # Remove original files
            rm "$sample_dir"/*_S*_L*_R*fastq.gz
        fi
    done

    echo "All files merged successfully."

    echo "Moving files to the N drive"

    ## Clean up
    rm -rf $OUTPUT_DIR

    echo "All done!"
else
    echo "Error: Illumina NextSeq or MiSeq platform not supported or not specified"
    usage
fi
