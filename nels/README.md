# NELS helper scripts

This folder contains two helper scripts used to prepare and upload sequencing run data to NELS:

- `ENA_metadata_draft_generator.R` — create a draft ENA metadata Excel file from FASTQ files
- `fastq_upload.ps1` — upload the metadata file and FASTQ files to the NELS server via `scp` (using a jump host)

Quick overview
--------------
1. Generate a draft metadata file with the R script.
2. Inspect / complete the generated XLSX file in Excel.
3. Run the PowerShell upload script to send the metadata and FASTQ files to NELS.

Requirements
------------
- R (with `Rscript`) for `ENA_metadata_draft_generator.R`.
  - R packages: `openxlsx`, `stringr`.
  - Install packages (example):

```powershell
Rscript -e "install.packages(c('openxlsx','stringr'), repos='https://cloud.r-project.org')"
```

- PowerShell (Windows) and a working `scp`/`ssh` command in PATH for `fastq_upload.ps1`.
  - SSH private key for authentication.

How to create the draft metadata (R)
-----------------------------------
Run the R script with `year` and `run` arguments. Example (from repo root):

```powershell
Rscript nels/ENA_metadata_draft_generator.R 2025 NGS_SEQ-20251205-01
```

The script will scan:

```
N:/NGS/4-SekvenseringsResultater/<year>-Resultater/<run>/fastq/
```

and produce the draft Excel file at:

```
N:/NGS/4-SekvenseringsResultater/ENA-metadata/<run>_ENA_metadata.xlsx
```

Open the XLSX in Excel and fill in the remaining required fields before upload.

How to upload to NELS (PowerShell)
----------------------------------
Run the PowerShell script with the SSH key, year, run and remote username. Example:

```powershell
cd ngs_scripts/nels
.\fastq_upload.ps1 -SshKeyFile "C:\Users\username.key" -Year 2025 -Run "NGS_SEQ-20251205-01" -RemoteUser "username"
```

What the upload script does:
- Finds the metadata file in `N:/NGS/4-SekvenseringsResultater/ENA-metadata/` that starts with the run id.
- Uploads that metadata file to the configured NELS project destination using `scp` with a ProxyCommand (jump host).
- Uploads all FASTQ files found in the FASTQ directory to the same remote destination.
- Writes a log file for the attempt at:

```
N:/NGS/4-SekvenseringsResultater/ENA-submission-logs/<run>_<YYYYMMDD_HHMMSS>_NELS_upload.log
```

Notes and tips
--------------
- The R script pairs FASTQ files by common basename and accepts `_R1`/`_R2` or `_1P`/`_2P` naming conventions.
- FASTQ filenames are not modified by either script.
- The PowerShell script will prompt for confirmation before uploading; review the metadata file first.
- If you want a dry-run mode for the upload script, I can add a `-WhatIf` or `-DryRun` flag to simulate uploads.
