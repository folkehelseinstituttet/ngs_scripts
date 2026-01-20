<#
.SYNOPSIS
    Upload paired FASTQ files and matching metadata to a remote server via SCP.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SshKeyFile,

    [Parameter(Mandatory=$true)]
    [int]$Year,

    [Parameter(Mandatory=$true)]
    [string]$Run,

    [Parameter(Mandatory=$true)]
    [string]$RemoteUser,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# CONFIGURATION
# =============================================================================

$RunBase = "N:\NGS\4-SekvenseringsResultater\{0}-Resultater\{1}" -f $Year, $Run
$pathTop   = Join-Path $RunBase "TOPresults\fastq"
$pathFastq = Join-Path $RunBase "fastq"
$CandidateDirs = @($pathTop, $pathFastq)

$MetadataDir     = "N:\NGS\4-SekvenseringsResultater\ENA-metadata"
$MetadataPattern = "$Run*"

# =============================================================================
# FASTQ DIRECTORY RESOLUTION
# =============================================================================

$LocalDirectory = $null
foreach ($d in $CandidateDirs) {
    if (Test-Path $d) {
        $files = Get-ChildItem $d -Filter "*.fastq.gz" -File -ErrorAction SilentlyContinue
        if ($files.Count -gt 0) {
            $LocalDirectory = $d
            break
        }
    }
}

if (-not $LocalDirectory) {
    Write-Host "ERROR: No FASTQ directory found" -ForegroundColor Red
    exit 1
}

# =============================================================================
# METADATA RESOLUTION
# =============================================================================

$MetadataFiles = Get-ChildItem $MetadataDir -Filter $MetadataPattern -File
if ($MetadataFiles.Count -ne 1) {
    Write-Host "ERROR: Expected exactly one metadata file, found $($MetadataFiles.Count)" -ForegroundColor Red
    exit 1
}

$MetadataFile = $MetadataFiles[0].FullName
Write-Host "Found metadata file: $MetadataFile" -ForegroundColor Green
if ((Read-Host "Proceed? (y/n)") -notin @('y','Y')) { exit 0 }

# =============================================================================
# FASTQ SELECTION
# =============================================================================

$FastqFiles = Get-ChildItem $LocalDirectory -Filter "*.fastq.gz" -File |
    Where-Object { $_.Name -match "-GA-" -or $_.Name -match "-ME-" }

if ($FastqFiles.Count -eq 0) {
    Write-Host "ERROR: No matching FASTQ files" -ForegroundColor Red
    exit 1
}

# =============================================================================
# REMOTE SETUP
# =============================================================================

$RemoteDataHost    = "data.nels.elixir.no"
$RemoteLoginHost   = "login.nels.elixir.no"
$RemoteProjectPath = "Projects/FHI_Caugant_Pathogens_ENA_testsubmission_2020/Nye_Til_ENA/"
$ProxyCommand = "ssh -i $SshKeyFile -W %h:%p $RemoteUser@$RemoteLoginHost"
$ScpBaseArgs  = @("-i", $SshKeyFile, "-o", "ProxyCommand=$ProxyCommand")
$RemoteDestination = "$RemoteUser@$RemoteDataHost`:${RemoteProjectPath}"

# =============================================================================
# LOGGING — FIXED FOR SMB
# =============================================================================

$logDate = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir  = "N:\NGS\4-SekvenseringsResultater\ENA-submission-logs"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $logDir ("{0}_{1}_NELS_upload.log" -f $Run, $logDate)

function Write-Log {
    param([string]$Message)
    $Message | Out-File -FilePath $logFile -Append
}

# initialize log
"============================================" | Out-File $logFile
"NELS Upload Log" | Out-File $logFile -Append
"Run: $Run" | Out-File $logFile -Append
"Date: $logDate" | Out-File $logFile -Append
"Metadata: $MetadataFile" | Out-File $logFile -Append
"FASTQ dir: $LocalDirectory" | Out-File $logFile -Append
"Remote: $RemoteDestination" | Out-File $logFile -Append
"DryRun: $DryRun" | Out-File $logFile -Append
"============================================" | Out-File $logFile -Append
"" | Out-File $logFile -Append

# =============================================================================
# METADATA UPLOAD
# =============================================================================

if ($DryRun) {
    Write-Host "DRYRUN: Metadata upload skipped" -ForegroundColor Yellow
    Write-Log "Metadata upload: DRYRUN"
} else {
    & scp @($ScpBaseArgs + @($MetadataFile, $RemoteDestination))
    if ($LASTEXITCODE -ne 0) { throw "Metadata upload failed" }
    Write-Log "Metadata upload: SUCCESS"
}

Write-Log ""

# =============================================================================
# FASTQ UPLOADS
# =============================================================================

$successCount = 0
$failCount    = 0
Write-Log "FASTQ uploads:"

foreach ($file in $FastqFiles) {
    Write-Host "Uploading $($file.Name)..."

    if ($DryRun) {
        Write-Log "$($file.Name): DRYRUN"
        $successCount++
    } else {
        & scp @($ScpBaseArgs + @($file.FullName, $RemoteDestination))
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($file.Name): SUCCESS"
            $successCount++
        } else {
            Write-Log "$($file.Name): FAIL ($LASTEXITCODE)"
            $failCount++
        }
    }
}

# =============================================================================
# SUMMARY
# =============================================================================

$totalFiles = $FastqFiles.Count + 1
$metaSuccess = 1

Write-Host "============================================"
Write-Host "Upload Summary"
Write-Host "============================================"
Write-Host "Total files: $totalFiles"
Write-Host "Successful:  $($successCount + $metaSuccess)"
Write-Host "Failed:      $failCount"

Write-Log ""
Write-Log "Summary:"
Write-Log "Total files: $totalFiles"
Write-Log "Successful: $($successCount + $metaSuccess)"
Write-Log "Failed: $failCount"

if ($failCount -gt 0) { exit 1 }
exit 0
