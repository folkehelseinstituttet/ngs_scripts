<#
.SYNOPSIS
    Upload paired FASTQ files and metadata to a remote server via SCP.

.DESCRIPTION
    This script searches for paired FASTQ files (containing "GA" and either "1P" or "2P")
    in a specified directory and uploads them along with a metadata file to a remote server.

.PARAMETER SshKeyFile
    Path to the SSH private key file for authentication.

.PARAMETER DirectoryName
    Name of the directory containing the paired fastq.gz files.

.PARAMETER MetadataFile
    Path to the metadata file to upload.

.PARAMETER Year
    Year used to construct the source directory path.

.PARAMETER RemoteUser
    Username for the remote server authentication.

.EXAMPLE
    .\fastq_upload.ps1 -SshKeyFile "C:\keys\my_key" -DirectoryName "run_001" -MetadataFile "C:\data\metadata.csv" -Year 2025 -RemoteUser "myuser"
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the SSH private key file")]
    [string]$SshKeyFile,

    [Parameter(Mandatory=$true, HelpMessage="Name of the directory containing FASTQ files")]
    [string]$DirectoryName,

    [Parameter(Mandatory=$true, HelpMessage="Path to the metadata file")]
    [string]$MetadataFile,

    [Parameter(Mandatory=$true, HelpMessage="Year for the directory path")]
    [int]$Year,

    [Parameter(Mandatory=$true, HelpMessage="Username for the remote server")]
    [string]$RemoteUser
)

# =============================================================================
# CONFIGURATION - Modify these paths as needed
# =============================================================================

# Local base directory path (year and DirectoryName will be appended)
$LocalBasePath = "N:\NGS\3-Sekvenseringsbiblioteker\$Year\Illumina_Run\"

# =============================================================================
# SCRIPT LOGIC
# =============================================================================

# Construct the full local directory path
$LocalDirectory = Join-Path -Path $LocalBasePath -ChildPath "$DirectoryName"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "FASTQ Upload Script for NELS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Validate SSH key file exists
if (-not (Test-Path $SshKeyFile)) {
    Write-Host "ERROR: SSH key file not found: $SshKeyFile" -ForegroundColor Red
    exit 1
}

# Validate local directory exists
if (-not (Test-Path $LocalDirectory)) {
    Write-Host "ERROR: Local directory not found: $LocalDirectory" -ForegroundColor Red
    exit 1
}

# Validate metadata file exists
if (-not (Test-Path $MetadataFile)) {
    Write-Host "ERROR: Metadata file not found: $MetadataFile" -ForegroundColor Red
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  SSH Key:          $SshKeyFile"
Write-Host "  Local Directory:  $LocalDirectory"
Write-Host "  Metadata File:    $MetadataFile"
Write-Host "  Remote Target:    ${RemoteUser}@${RemoteHost}:${RemoteBasePath}"
Write-Host ""

# Find FASTQ files matching the pattern: contains "GA" AND ("1P" OR "2P")
Write-Host "Searching for FASTQ files with 'GA' and '1P' or '2P'..." -ForegroundColor Yellow

$FastqFiles = Get-ChildItem -Path $LocalDirectory -Filter "*.fastq.gz" -File | 
    Where-Object { 
        $_.Name -match "GA" -and ($_.Name -match "1P" -or $_.Name -match "2P")
    }

if ($FastqFiles.Count -eq 0) {
    Write-Host "WARNING: No matching FASTQ files found in $LocalDirectory" -ForegroundColor Yellow
    Write-Host "Pattern: Files must contain 'GA' and either '1P' or '2P'" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($FastqFiles.Count) matching FASTQ files:" -ForegroundColor Green
foreach ($file in $FastqFiles) {
    Write-Host "  - $($file.Name)"
}
Write-Host ""

# Confirm before upload
$confirmation = Read-Host "Do you want to proceed with the upload? (y/n)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Upload cancelled by user." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Starting upload..." -ForegroundColor Yellow
Write-Host ""


# Construct the remote destination for NELS Personal area
$RemoteDataHost = "data.nels.elixir.no"
$RemoteLoginHost = "login.nels.elixir.no"
$RemotePersonalPath = "Personal/"
$ProxyCommand = "ssh -i $SshKeyFile -W %h:%p $RemoteUser@$RemoteLoginHost"
$ScpBaseArgs = @("-i", $SshKeyFile, "-o", "ProxyCommand=$ProxyCommand")
$RemoteDestination = "$RemoteUser@$RemoteDataHost:$RemotePersonalPath"


# Upload metadata file first
Write-Host "Uploading metadata file..." -ForegroundColor Cyan
$scpArgs = $ScpBaseArgs + @($MetadataFile, $RemoteDestination)
Write-Host "  scp $($ScpBaseArgs -join ' ') $MetadataFile $RemoteDestination"

try {
    & scp @scpArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to upload metadata file" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Metadata file uploaded successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Upload each FASTQ file
$successCount = 0
$failCount = 0

foreach ($file in $FastqFiles) {
    Write-Host "Uploading: $($file.Name)..." -ForegroundColor Cyan
    $scpArgs = $ScpBaseArgs + @($file.FullName, $RemoteDestination)
    Write-Host "  scp $($ScpBaseArgs -join ' ') $($file.FullName) $RemoteDestination"
    try {
        & scp @scpArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Success" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  Failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
            $failCount++
        }
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Upload Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Total files:     $($FastqFiles.Count + 1) (including metadata)"
Write-Host "  Successful:      $($successCount + 1)" -ForegroundColor Green
Write-Host "  Failed:          $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Some files failed to upload. Please check the errors above." -ForegroundColor Yellow
    exit 1
}

Write-Host "All files uploaded successfully!" -ForegroundColor Green
exit 0
