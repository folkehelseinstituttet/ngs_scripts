param (
    [string]$metadata_files,
    [string]$fasta_files,
    [string]$CREDENTIALS_FILE = "credentials.txt",
    [string]$username
)

function Show-Usage {
    Write-Host "Usage: .\script.ps1 -m metadata_file -f fasta_file -c credentials_file -u username"
    Write-Host "  -m  Specify the metadata CSV file"
    Write-Host "  -f  Specify the FASTA file"
    Write-Host "  -c  Specify the credentials file (default: credentials.txt)"
    Write-Host "  -u  Specify the username"
    exit 1
}

# Validate parameters
if (-not $username) {
    Write-Host "Error: Username is required!"
    Show-Usage
}

if (-not (Test-Path $CREDENTIALS_FILE)) {
    Write-Host "Error: Credentials file not found!"
    exit 1
}

# Read the credentials from the file
$credentials = Get-Content -Path $CREDENTIALS_FILE | ForEach-Object {
    $parts = $_ -split '='
    New-Object PSObject -Property @{
        Key = $parts[0].Trim()
        Value = $parts[1].Trim()
    }
}

# Convert the credentials into a hashtable
$credentials = $credentials | ForEach-Object { @{$_.Key = $_.Value} }

# Ensure the variables are not empty
if (-not $credentials.password -or -not $credentials.clientid) {
    Write-Host "Error: Missing password or client ID in the credentials file!"
    exit 1
}

# Execute the command with the read credentials and username
& "N:\Virologi\NGS\1-NGS-Analyser\8-Skript\1-GISAID\fluCLI\fluCLI.exe" upload --username $username `
                --password $credentials.password `
                --clientid $credentials.clientid `
                --metadata $metadata_files `
                --fasta $fasta_files `


# Specify the folder path where the new folder should be created
$base_folder = "N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\10-GISAID"

# Create the folder with today's date appended
$today = Get-Date -Format "yyyy-MM-dd"
$folder_name = Join-Path -Path $base_folder -ChildPath "GISAID_INF_submission_$today"

# Create the folder at the specified path
New-Item -ItemType Directory -Path $folder_name -Force
Write-Host "Created folder: $folder_name"

# Move the metadata and fasta files to the new folder
Move-Item -Path $metadata_files -Destination $folder_name
Move-Item -Path $fasta_files -Destination $folder_name

Write-Host "Moved files to folder: $folder_name"
Write-Host "Submission complete!"
