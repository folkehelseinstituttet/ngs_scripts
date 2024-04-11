#!/usr/bin/env bash

# TODO:
# [] Set up the smbclient command. Move to N/Virologi/JonBrate when testing
# [] Run script as ngs user
# [] Hva skal være $SMB_HOST? (vi flytter fra VM til N)
# [] Move files to 3-Sekvenseringsbiblioteker in the end (fix the $STAGING variable)

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: dev

# The script requires BaseSpace CLI installed (https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview)
# Check if the bs command is available
#if ! command -v ./bin/bs &> /dev/null
#then
#    echo "BaseSpace CLI could not be found"
#    exit 1
#fi

# There also has to be a BaseSpace credentials file: $HOME/.basespace/default.cfg
# Check if the file exists
if ! test -f ~/.basespace/default.cfg; then
  echo "BaseSpace credentials file does not exist."
  exit 1
fi

# The script takes two arguments, the name of the Illumina run to be downloaded and the agens.
# Check if the number of arguments is zero
if [ $# -eq 0 ]; then
    echo "Did you forget to enter the Run or Agens name?"
    echo "Usage: $0 <Run name> <Agens>"
    exit 1
fi

# Set the variables
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=NGS/3-Sekvenseringsbiblioteker
Run=$1
Agens=$2

# Make a fastq directory under home. Download files here
mkdir -p ~/fastq

# List Runs on BaseSpace and get the Run id (third column separated by | and whitespaces)
id=$(/home/ngs/bin/bs list projects | grep "${Run}" | awk -F '|' '{print $3}' | awk '{$1=$1};1')

# Then download the fastq files
/home/ngs/bin/bs download project -i ${id} --extension=fastq.gz -o fastq/${Run}

# Clean up the folder names

RUN_DIR="$HOME/fastq/${Run}"
# Find only directories in the current directory. Loop through them and rename
# mindepth 1 excludes the RUN_DIR directory. maxdepth 1 includes only the sudirectories of RUN_DIR
find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' folder; do
    # Extract the name of the subdirectory
    dir_name=$(basename "$folder")
    
    # Extract the sample number and add Agens name
    new_name="${dir_name%%-*}-${Agens}"

    # Rename the folder
    mv "$folder" "$RUN_DIR/$new_name"
done

## Move to N:
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_DIR <<EOF
prompt OFF
recurse ON
lcd $HOME/fastq
mput *
EOF

