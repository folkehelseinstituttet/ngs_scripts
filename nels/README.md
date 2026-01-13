# Create metadata file for NELS upload

Quick start (if you've done this before)
--------------
1. Navigate to `C:\Users\<username>` in PowerShell: 
   ```powershell
   cd $env:USERPROFILE
   ```
2. Create the info to be copied into the ENA template. Replace year and run as needed:
   ```powershell
   & 'C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe' -e "year <- 2025; run <- 'NGS_SEQ-20251205-01'; source('https://raw.githubusercontent.com/folkehelseinstituttet/ngs_scripts/main/nels/ENA_metadata_draft_generator.R')"
   ```
3. This will create an excel file in the `C:\Users\username>` folder named `TEMP_ENA_metadata.xlsx`. Open it in Excel, copy the columns into the ENA metadata template and save as a new file.   
**NB!** The metadada file must start with the Run id, and must be stored in the `N:/NGS/4-SekvenseringsResultater/ENA-metadata/`.

Setup (first time only)
-----------------------
1. Install R 4.5.2 or later from "Firmaportalen"

   ![Screenshot of R installation in Firmaportalen](Screenshot%202026-01-13%20135809.png)

2. Install required R packages (change R-4.5.2 if you installed another version):
   ```powershell
   & 'C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe' -e "install.packages(c('openxlsx','stringr'), repos='https://cloud.r-project.org')"
   ```

# Upload files to NELS

1. Ensure you have downloaded your private SSH key file from NELS and saved it to `C:\Users\<username>`
2. Then run the following code. Change `username.key` to your SSH key filename, and change year, run id and remote username as needed:

```powershell
$script = Join-Path $env:USERPROFILE 'fastq_upload.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/folkehelseinstituttet/ngs_scripts/main/nels/fastq_upload.ps1' -OutFile $script; & $script -SshKeyFile "$env:USERPROFILE\username.key" -Year 2025 -Run 'NGS_SEQ-20251205-01' -RemoteUser 'username'
```


# Detailed overview

This folder contains two helper scripts used to prepare and upload sequencing run data to NELS:

- `ENA_metadata_draft_generator.R` — create a draft ENA metadata Excel file from FASTQ files
- `fastq_upload.ps1` — upload the metadata file and FASTQ files to the NELS server via `scp` (using a jump host)

1. Generate a draft metadata file with the R script.
2. Inspect / complete the generated XLSX file in Excel.
3. Run the PowerShell upload script to send the metadata and FASTQ files to NELS.

Requirements
------------
- R (with `Rscript`) for `ENA_metadata_draft_generator.R`.
  - R packages: `openxlsx`, `stringr`.
  - **Note:** On Windows, if Rscript is not in PATH, call it by full path:
    ```
    C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe
    ```
  - Install packages (example):

```powershell
# If Rscript is on PATH:
Rscript -e "install.packages(c('openxlsx','stringr'), repos='https://cloud.r-project.org')"

# If Rscript is NOT on PATH (use full path with &):
& 'C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe' -e "install.packages(c('openxlsx','stringr'), repos='https://cloud.r-project.org')"
```

- PowerShell (Windows) and a working `scp`/`ssh` command in PATH for `fastq_upload.ps1`.
  - SSH private key for authentication.

How to create the draft metadata (R)
-----------------------------------
Run the R script with `year` and `run` arguments. Example (from repo root):

```powershell
# If Rscript is on PATH:
Rscript nels/ENA_metadata_draft_generator.R 2025 NGS_SEQ-20251205-01

# If Rscript is NOT on PATH (Windows, use & with full path):
& 'C:\Program Files\R\R-4.5.2\bin\x64\Rscript.exe' nels/ENA_metadata_draft_generator.R 2025 NGS_SEQ-20251205-01
```

The script will scan:

```
N:/NGS/4-SekvenseringsResultater/<year>-Resultater/<run>/TOPresults/fastq/
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
