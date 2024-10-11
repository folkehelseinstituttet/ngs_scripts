#!/bin/bash

usage() {
  echo "Usage: $0 [-m metadata_file] [-f fasta_file] [-c credentials_file] [-u username]"
  echo "  -m  Specify the metadata CSV file"
  echo "  -f  Specify the FASTA file"
  echo "  -c  Specify the credentials file (default: credentials.txt)"
  echo "  -u  Specify the username"
  exit 1
}

# Initialize variables
metadata_files=""
fasta_files=""
CREDENTIALS_FILE="credentials.txt"  # Default credentials file
username=""  # Initialize the username

# Parse command-line arguments
while getopts ":m:f:c:u:" opt; do
  case $opt in
    m)
      metadata_files=$OPTARG
      ;;
    f)
      fasta_files=$OPTARG
      ;;
    c)
      CREDENTIALS_FILE=$OPTARG
      ;;
    u)
      username=$OPTARG
      ;;
    *)
      usage
      ;;
  esac
done

# Ensure the username is provided
if [ -z "$username" ]; then
  echo "Error: Username is required!"
  usage
  exit 1
fi

# Ensure the credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "Error: Credentials file not found!"
  exit 1
fi

# Read the password and clientid from the file
source "$CREDENTIALS_FILE"

# Ensure the variables are not empty
if [ -z "$password" ] || [ -z "$clientid" ]; then
  echo "Error: Missing password or client ID in the credentials file!"
  exit 1
fi

# Execute the command with the read credentials and username
./fluCLI upload --username "$username" --password "$password" --clientid "$clientid" --log YYYY-MM-DD_submission.log --metadata "$metadata_files" --fasta "$fasta_files"

# Execute the command with the read credentials
#./fluCLI upload --username username --password "$password" --clientid "$clientid" --metadata "$metadata_files" --fasta $fasta_files


today=$(date +%Y-%m-%d)
folder_name="GISAID_SC2_submission_$today"
mkdir -p "$folder_name"
echo "Created folder: $folder_name"

# Move the metadata and fasta files to the new folder
mv "$metadata_files" "$folder_name" 
mv "$fasta_files" "$folder_name"

echo "Moved files to folder: $folder_name"
echo "Submission complete!"
