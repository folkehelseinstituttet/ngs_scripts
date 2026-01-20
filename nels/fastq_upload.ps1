<#
.SYNOPSIS
    Upload paired FASTQ files and matching metadata to a remote server via SCP.

.DESCRIPTION
    This script searches for paired FASTQ files (containing "GA" and either "1P" or "2P")
    in a directory based on the provided Year and Run parameters, and uploads them along with
    a metadata file (found by prefix match in the ENA-metadata directory) to a remote server.

.PARAMETER SshKeyFile
    Path to the SSH private key file for authentication.

.PARAMETER Year
    Year used to construct the source directory path (e.g., 2025).

.PARAMETER Run
    Run identifier used to construct both the FASTQ directory and to find the metadata file (e.g., NGS_SEQ-20251113-01).

.PARAMETER RemoteUser
    Username for the remote server authentication.

.EXAMPLE
    .\fastq_upload.ps1 -SshKeyFile "C:\keys\my_key" -Year 2025 -Run "NGS_SEQ-20251113-01" -RemoteUser "myuser"

.NOTES
    Related: Before running this script, generate metadata with ENA_metadata_draft_generator.R.
    On Windows, if Rscript is not in PATH, call it by full path:
        & 'C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe' nels/ENA_metadata_draft_generator.R 2025 NGS_SEQ-...
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the SSH private key file")]
    [string]$SshKeyFile,

    [Parameter(Mandatory=$true, HelpMessage="Year for the directory path")]
    [int]$Year,

    [Parameter(Mandatory=$true, HelpMessage="Run identifier (used for both fastq and metadata paths)")]
    [string]$Run,

    [Parameter(Mandatory=$true, HelpMessage="Username for the remote server")]
    [string]$RemoteUser
)

# =============================================================================
# CONFIGURATION - Modify these paths as needed
# =============================================================================

# Check the two expected locations for FASTQ files in order:
# 1) TOPresults\fastq
# 2) fastq
# Build RunBase reliably and explicit candidate paths to avoid coercion to arrays
$RunBase = -f "N:\NGS\4-SekvenseringsResultater\{0}-Resultater\{1}", $Year, $Run

$pathTop = Join-Path -Path $RunBase -ChildPath "TOPresults\fastq"
$pathFastq = Join-Path -Path $RunBase -ChildPath "fastq"
$CandidateDirs = @($pathTop, $pathFastq)

# Metadata directory and file pattern
$MetadataDir = "N:\NGS\4-SekvenseringsResultater\ENA-metadata"
$MetadataPattern = "$Run*"

# =============================================================================
# SCRIPT LOGIC
# =============================================================================


# Find a suitable FASTQ directory that contains fastq.gz files
$LocalDirectory = $null
foreach ($d in $CandidateDirs) {
    if (Test-Path $d) {
        $files = Get-ChildItem -Path $d -Filter "*.fastq.gz" -File -ErrorAction SilentlyContinue
        if ($files -and $files.Count -gt 0) {
            $LocalDirectory = $d
            break
        }
    }
}

# Fallback: preserve previous behaviour by using TOPresults\fastq path
if (-not $LocalDirectory) { $LocalDirectory = Join-Path $RunBase "TOPresults\fastq" }

# Find metadata file matching $Run*
$MetadataFiles = Get-ChildItem -Path $MetadataDir -Filter "$MetadataPattern" -File
if ($MetadataFiles.Count -eq 0) {
    Write-Host "ERROR: No metadata file found in $MetadataDir starting with '$Run'" -ForegroundColor Red
    exit 1
}
if ($MetadataFiles.Count -gt 1) {
    Write-Host "WARNING: More than one metadata file found starting with '$Run':" -ForegroundColor Yellow
    foreach ($mf in $MetadataFiles) { Write-Host "  - $($mf.FullName)" }
    exit 1
}
$MetadataFile = $MetadataFiles[0].FullName
Write-Host "Found metadata file: $MetadataFile" -ForegroundColor Green
$confirmation = Read-Host "Do you want to proceed with this metadata file? (y/n)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "Upload cancelled by user." -ForegroundColor Yellow
    exit 0
}

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
Write-Host ""


# Find FASTQ files matching the pattern: -GA- or -ME-
Write-Host "Searching for FASTQ files with '-GA-' or '-ME-'..." -ForegroundColor Yellow

$FastqFiles = Get-ChildItem -Path $LocalDirectory -Filter "*.fastq.gz" -File | 
    Where-Object { $_.Name -match "-GA-" -or $_.Name -match "-ME-" }

if ($FastqFiles.Count -eq 0) {
    Write-Host "WARNING: No matching FASTQ files found in $LocalDirectory" -ForegroundColor Yellow
    Write-Host "Pattern: Files must contain 'GA' or 'ME'" -ForegroundColor Yellow
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


# Construct the remote destination for NELS project area
$RemoteDataHost = "data.nels.elixir.no"
$RemoteLoginHost = "login.nels.elixir.no"
$RemoteProjectPath = "Projects/FHI_Caugant_Pathogens_ENA_testsubmission_2020/Nye_Til_ENA/"
$ProxyCommand = "ssh -i $SshKeyFile -W %h:%p $RemoteUser@$RemoteLoginHost"
$ScpBaseArgs = @("-i", $SshKeyFile, "-o", "ProxyCommand=$ProxyCommand")
$RemoteDestination = "$RemoteUser@$RemoteDataHost`:${RemoteProjectPath}"
Write-Host "  Remote Target:    $RemoteDestination"



# ---- LOGGING SETUP ----
$logDate = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = "N:\NGS\4-SekvenseringsResultater\ENA-submission-logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$logFile = Join-Path -Path $logDir -ChildPath ("${Run}_$logDate_NELS_upload.log")
Add-Content -Path $logFile -Value ("NELS Upload Log for Run: $Run")
Add-Content -Path $logFile -Value ("Date: $logDate")
Add-Content -Path $logFile -Value ("Metadata file: $MetadataFile")
Add-Content -Path $logFile -Value ("FASTQ directory: $LocalDirectory")
Add-Content -Path $logFile -Value ("Remote destination: $RemoteDestination")
Add-Content -Path $logFile -Value ("")
Add-Content -Path $logFile -Value ("Uploading metadata file...")

$scpArgs = $ScpBaseArgs + @($MetadataFile, $RemoteDestination)
Write-Host "  scp $($ScpBaseArgs -join ' ') $MetadataFile $RemoteDestination"
$metaStatus = ""
try {
    & scp @scpArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to upload metadata file" -ForegroundColor Red
        $metaStatus = "FAIL"
        Add-Content -Path $logFile -Value ("Metadata upload: FAIL (exit code: $LASTEXITCODE)")
        exit 1
    }
    Write-Host "  Metadata file uploaded successfully" -ForegroundColor Green
    $metaStatus = "SUCCESS"
    Add-Content -Path $logFile -Value ("Metadata upload: SUCCESS")
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $metaStatus = "FAIL"
    Add-Content -Path $logFile -Value ("Metadata upload: FAIL ($($_.Exception.Message))")
    exit 1
}
Add-Content -Path $logFile -Value ("")
Add-Content -Path $logFile -Value ("FASTQ file uploads:")

# Upload each FASTQ file
$successCount = 0
$failCount = 0

foreach ($file in $FastqFiles) {
    Write-Host "Uploading: $($file.Name)..." -ForegroundColor Cyan
    $scpArgs = $ScpBaseArgs + @($file.FullName, $RemoteDestination)
    Write-Host "  scp $($ScpBaseArgs -join ' ') $($file.FullName) $RemoteDestination"
    $status = ""
    try {
        & scp @scpArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Success" -ForegroundColor Green
            $successCount++
            $status = "SUCCESS"
        } else {
            Write-Host "  Failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
            $failCount++
            $status = "FAIL (exit code: $LASTEXITCODE)"
        }
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
        $status = "FAIL ($($_.Exception.Message))"
    }
    Add-Content -Path $logFile -Value ("$($file.Name): $status")
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
