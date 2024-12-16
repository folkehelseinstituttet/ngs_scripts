# SUBMISSION TO GISAID

# Table of Contents
1. [SARS-CoV-2](#sars-cov-2)
2. [Influenza](#influenza)
3. [RSV](#rsv)

# SARS-CoV-2

### Open the excel submission log document
Open this file and fill in accordingly:
`N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\SARS-CoV-2\4-GISAIDsubmisjon\OVERSIKT submisjoner til GISAID og andre_V2.xlsx`  

### Prepare input files (PowerShell)
Prerequisite: PowerShell, R and git.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Using PowerShell on a FHI laptop, run the script `sc2_gisaid.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" ".sars-cov-2\sc2_gisaid.R" "DATE" "USER"
```
Remeber to replace DATE with date (YYYY-MM-DD) for oldest sample to include in submission and USER wither your GISAID username. 

This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\SARS-CoV-2\4-GISAIDsubmisjon`.  
That directory should contain two files. One csv file with metadata and one fasta file.

Chose either upload by Linux or Windows:

### Upload to Gisaid (Windows)  
Upload to GISAID using version 4 of the cli.

No need do naviagte and clone repo if already done.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Prepare a "credentials.txt" file with this content and format and save at `.\ngs_scripts\gisaid\`:
```
password=your_password
clientid=your_clientid
```
Run submission-script:
```
.\GISAID_SC2_submission.ps1 -m "metadata.csv" -f "sequences.fasta" -c "credentials.txt" -u "username"
```
Remember to give the command your metadata-,sequences- and credentials-file, and also your GISAID-username.
If .\GISAID_SC2_submission.ps1 is not executable try `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`

After files are created delete the `ngs_scripts` folder in `N:\Virologi\NGS\tmp`.
  
### Copy submission log file N
Copy the covCLI upload log file to the directory created when you prepared the submission files.  

### Create BioNumerics import file 
For the moment we need to wait until Gisaid confirms the release of the sequences. Then we need to go into Gisaid using the browser, search for the newly submitted sequences, select them click "Download" and choose "Sequencing technology metadata". The downloaded file can be processed with the script `create_BN_import_from_Gisaid_download.R in PowerShell:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" ".\ngs_scripts\gisaid\create_BN_import_from_Gisaid_download.R" "FILE_FROM_GISAID.tsv" 
```
Import file for BioNumerics is stored at `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\SARS-CoV-2\4-GISAIDsubmisjon\BN-import-filer` and is ready for import.

### Import data into BioNumerics and update Excel-sheet
Open BioNumerics and import the generated import file using the import-template `GISAID`. 
Remember to update the excel sheet that tracks all the submissions with the BN import date. 

After submission delete the `ngs_scripts` folder in `N:\Virologi\NGS\tmp`.

# Influenza

### Prepare input files (PowerShell)
Prerequisite: PowerShell, R and git.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Using PowerShell on a FHI laptop, run the script `influenza_gisaid.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" ".\influenza\influenza_gisaid.R" "RUNID"
```
Remember to replace RUNID with run-id for samples you want to submit.

This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\10-GISAID`.  
That directory should contain two files. One csv file with metadata and one fasta file.

### Upload to Gisaid (Windows)  
Upload to GISAID using version 4 of the cli.

No need do naviagte and clone repo if already done.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Prepare a "credentials.txt" file with this content and format and save at `.\ngs_scripts\gisaid\`:
```
password=your_password
clientid=your_clientid
```
Run submission-script:
```
.\influenza\GISAID_INF_submission.ps1 -m "metadata.csv" -f "sequences.fasta" -c "credentials.txt" -u "username"
```
Remember to give the command your metadata-,sequences- and credentials-file, and also your GISAID-username.
If .\GISAID_INF_submission.ps1 is not executable try `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`

Once the upload is complete, the sequences will be available under your GISAID account as “unreleased.” These sequences should be released only after the quality assurance process is finished (see details in 702-VIN-AR-031).

In GISAID, select all uploaded sequences and choose the “Isolate as XLS (virus metadata only)” export option. The resulting file can then be imported into the FLU-BIONUMERICS database using the GISAID import template.

After submission delete the `ngs_scripts` folder in `N:\Virologi\NGS\tmp`.

# RSV

### Prepare input files (PowerShell)
Prerequisite: PowerShell, R and git.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Using PowerShell on a FHI laptop, run the script `influenza_gisaid.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" ".\rsv\rsv_gisaid.R" "RUNID"
```
Remember to replace RUNID with run-id for samples you want to submit.

This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\RSV\10-GISAID`.  
That directory should contain two files. One csv file with metadata and one fasta file.

### Upload to Gisaid (Windows)  
Upload to GISAID using version 4 of the cli.

No need do naviagte and clone repo if already done.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Prepare a "credentials.txt" file with this content and format and save at `.\ngs_scripts\gisaid\`:
```
password=your_password
clientid=your_clientid
```
Run submission-script:
```
.\rsv\GISAID_RSV_submission.ps1 -m "metadata.csv" -f "sequences.fasta" -c "credentials.txt" -u "username"
```
Remember to give the command your metadata-,sequences- and credentials-file, and also your GISAID-username.
If .\GISAID_INF_submission.ps1 is not executable try `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`

After submission delete the `ngs_scripts` folder in `N:\Virologi\NGS\tmp`.
__________________________________________________________________________________________

## Old procedure based on Nextflow
Pipeline to prepare and create files for submitting SARS-CoV-2 consensus sequences to GISAID. The pipeline only requires Nextflow and Docker installed in order to run. However, there are several features of the various scripts that will only work on the internal datastructures of NIPH.   

### Prepare input files  
- Get the latest data from the BioNumerics Covid19 server. **On a NIPH windows PC**, execute the R script `N:\Virologi\JonBrate\Prosjekter\refresh_data_from_BN.R`.  
- Get the latest approved samples from LabWare. In "sikker sone", execute the R script `lese_LW_uttrekk.R`. The result file needs to be moved to `N:NGS_FHI_statistikk`.  

### Prepare the submission  
Log on to the VM `ngs-worker-1` and switch to the local user `sudo -u ngs /bin/bash`.  
Fetch the latest updates with `git -C ~/ngs_scripts pull origin main`.  
Enter the gisaid directory `cd ~/ngs_scripts/gisad`.  
Run the Nextflow pipeline `nextflow run main.nf -profile local --submitter USERNAME --LW /mnt/N/NGS_FHI_statistikk/latest_file.tsv --min_date "2023-01-01"`.
  
### Upload to Gisaid
Upload to GISAID using version 4 of the cli:
```
covCLI upload --username USERNAME --password PASSWORD --clientid CLIENTID --log Gisaid_files/2024-01-09_submission.log --metadata Gisaid_files/2024-01-09_metadata_raw_submit.csv --fasta Gisaid_files/2024-01-09_raw.fasta --frameshifts catch_novel --dateformat YYYYMMDD
```

### Create BioNumerics import file:
```
Rscript bin/create_BN_import.R Gisaid_files/2023-05-03_submission.log Gisaid_files/2023-05-03_frameshift_results.csv
```

