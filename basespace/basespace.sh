#!/usr/bin/env bash

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: 1.0
# This script downloads fastq files from the BaseSpace server and transfers them to the NIPH N-drive.

# Define the script name and usage
SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -p, --platform    Can be either nextseq, miseq, or nextseq_virus"
    echo "  -r, --run         Specify the run name (e.g. NGS_SEQ-20240606-01)"
    echo "  -y, --year        Specify the year the sequencing was performed (e.g. 2024)"
    echo "  -d, --department  Specify department: only use b (for bacteriology) or v (for virology)"
    exit 1
}

# Initialize variables
PLATFORM=""
RUN=""
DEPARTMENT=""
YEAR=""

while getopts "hp:r:n:y:d:" opt; do
    case "$opt" in
        h) usage ;;
        p) PLATFORM="$OPTARG" ;;
        r) RUN="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        d) DEPARTMENT="$OPTARG" ;;
        ?) usage ;;
    esac

done

# Check that DEPARTMENT is specified and valid
if [[ "$DEPARTMENT" != "b" && "$DEPARTMENT" != "v" ]]; then
    echo "Error: You must specify the department with -d b (bacteriology) or -d v (virology)."
    usage
    exit 1
fi

## Check if necessary software and files are present

# The script requires BaseSpace CLI installed (https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview)
# Check if the bs command is available
if ! command -v bs &> /dev/null
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
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
# Set SMB_DIR based on department
if [[ "$DEPARTMENT" == "v" ]]; then
    SMB_DIR="Virologi/NGS/0-Sekvenseringsbiblioteker/Illumina_Run"
else
    SMB_DIR="NGS/3-Sekvenseringsbiblioteker/${YEAR}/Illumina_Run"
fi

# NOTE: use fastq_tmp as the working fastq directory name
FASTQ_DIR_NAME="fastq_tmp"

echo "Getting the Run ID on the BaseSpace server"

# Capture the full line(s) that match the run name
matches=$(bs list projects | grep "${RUN}")

# If no matches found
if [[ -z "$matches" ]]; then
    echo "❌ Could not find any matching runs on BaseSpace for pattern '${RUN}'. Please check the spelling."
    exit 1
fi

# Count number of matches
num_matches=$(echo "$matches" | wc -l)

# If more than one match found, list them and exit
if (( num_matches > 1 )); then
    echo "⚠️  Multiple runs on Basespace match '${RUN}'. Please refine your search or specify the exact run name."
    echo
    echo "Matching runs on Basespace:"
    echo "$matches" | awk -F '|' '{print "• " $2}' | sed 's/^[[:space:]]*//'
    echo
    exit 1
fi

# Otherwise, extract the Run ID (third column)
id=$(echo "$matches" | awk -F '|' '{print $3}' | awk '{$1=$1};1')

echo "✅ Found matching run on Basespace with ID: $id"

echo "Downloading fastq files"
# First clean up the tempdrive
DIRECTORY="$BASE_DIR/${FASTQ_DIR_NAME}"
if [ -d "$DIRECTORY" ]; then
    echo "Directory $DIRECTORY exists. Deleting..."
    rm -rf "$DIRECTORY"
    echo "Directory $DIRECTORY has been deleted."
else
    echo "Directory $DIRECTORY does not exist. Creating it."
fi
# Download to a sub-directory for easier copying to N: later
mkdir -p "$BASE_DIR/${FASTQ_DIR_NAME}"

# Then download the fastq files
bs download project -i ${id} --extension=fastq.gz -o "$BASE_DIR/${FASTQ_DIR_NAME}/$RUN"

# Execute commands based on the platform specified
if [[ $PLATFORM == "miseq" ]]; then
    echo "Running commands for MiSeq platform..."
    
    # Clean up the folder names
    RUN_DIR="$BASE_DIR/${FASTQ_DIR_NAME}/${RUN}"
    # Find only directories in the current directory. Loop through them and rename
    # mindepth 1 excludes the RUN_DIR directory. maxdepth 1 includes only the sudirectories of RUN_DIR
    find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' folder; do
        # Extract the name of the subdirectory
        
        dir_name=$(basename "$folder")
        
        # Extract the sample number and add Agens name
        new_name="${dir_name%%_*}"

        # Rename the folder
        mv "$folder" "$RUN_DIR/$new_name"
    done

    echo "Transferring files to N"

    # Move to N:
    smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
    prompt OFF
    recurse ON
    lcd $BASE_DIR/${FASTQ_DIR_NAME}
    mput *
EOF
    
    ## Clean up
    rm -rf "$BASE_DIR/${FASTQ_DIR_NAME}"
elif [[ $PLATFORM == "nextseq" ]]; then
    echo "Running commands for NextSeq platform..."
    # Define output directory
    OUTPUT_DIR=final/$RUN/merged

    # Create the output directory if it doesn't exist
    mkdir -p $BASE_DIR/$OUTPUT_DIR

    # Loop through each sample directory, create new subdirectories for each sample and copy the fastq files to the corresponding directory
    for fastq in "$BASE_DIR/${FASTQ_DIR_NAME}/$RUN"/*/*.fastq.gz; do
            # Extract the basename
            base=$(basename $fastq)
        
            # Extract the sample name
            sample_name=$(basename "$fastq"   | cut -f 1 -d "_")

            # Make directories for each sample
            mkdir -p $BASE_DIR/$OUTPUT_DIR/$sample_name

            # Move each fastq file
            echo "Moving $base to directory $sample_name"
            mv $fastq $BASE_DIR/$OUTPUT_DIR/$sample_name/$base
    done

    # Merge all R1 and R2 files for each sample
    # Loop through each directory in the "merged" directory
    for sample_dir in "$BASE_DIR/$OUTPUT_DIR"/*; do
        if [ -d "$sample_dir" ]; then
        
            # Extract the sample name
            sample_name=$(basename "$sample_dir")
                
            # Concatenate all R1 files into a single file
            cat "$sample_dir"/*_R1_*.fastq.gz > "$sample_dir/${sample_name}_merged_R1_001.fastq.gz"
            echo "Concatenated R1 files for sample $sample_name"
        
            # Concatenate all R2 files into a single file
            cat "$sample_dir"/*_R2_*.fastq.gz > "$sample_dir/${sample_name}_merged_R2_001.fastq.gz"
            echo "Concatenated R2 files for sample $sample_name"

            # Remove original files
            rm "$sample_dir"/*_S*_L*_R*fastq.gz
        fi
    done

    echo "All files merged successfully."

    echo "Moving files to the N drive"
    smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
    prompt OFF
    recurse ON
    lcd $BASE_DIR/final/
    mput *
EOF

    ## Clean up
    rm -rf "$BASE_DIR/${FASTQ_DIR_NAME}"
    rm -rf $BASE_DIR/final

    echo "All done!"
elif [[ $PLATFORM == "nextseq_virus" ]]; then
    echo "Running commands for NextSeq virus platform (directory renaming)..."
    RUN_DIR="$BASE_DIR/${FASTQ_DIR_NAME}/${RUN}"
    # Safety check
    if [ ! -d "$RUN_DIR" ]; then
        echo "Run directory $RUN_DIR does not exist."
        exit 1
    fi
    # Loop and rename directories
    find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' folder; do
        dir_name=$(basename "$folder")
        # Remove '_ds' and everything after
        new_name="${dir_name%%_ds*}"
        # Only rename if name changes
        if [[ "$dir_name" != "$new_name" ]]; then
            mv "$folder" "$RUN_DIR/$new_name"
            echo "Renamed $dir_name → $new_name"
        fi
    done
    echo "Directory renaming done."
    
    echo "Moving files to the N drive"
    smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
    prompt OFF
    recurse ON
    lcd $BASE_DIR/${FASTQ_DIR_NAME}/
    mput *
EOF

    ## Clean up
    rm -rf "$BASE_DIR/${FASTQ_DIR_NAME}"

    echo "All done!"
else
    echo "Error: Illumina NextSeq or MiSeq platform not supported or not specified"
    usage
fi
