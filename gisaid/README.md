# FHI_Gisaid

Pipeline to prepare and create files for submitting SARS-CoV-2 consensus sequences to GISAID. The pipeline only requires Nextflow and Docker installed in order to run. However, there are several features of the various scripts that will only work on the internal datastructures of NIPH.   

## Prepare input files  
- Get the latest data from the BioNumerics Covid19 server. **On a NIPH windows PC**, execute the R script `N:\Virologi\JonBrate\Prosjekter\refresh_data_from_BN.R`.  
- Get the latest approved samples from LabWare. In "sikker sone", execute the R script `lese_LW_uttrekk.R`. The result file needs to be moved to `N:NGS_FHI_statistikk`.  

## Prepare the submission  
Log on to the VM `ngs-worker-1` and switch to the local user `sudo -u ngs /bin/bash`.  
Fetch the latest updates with `git -C ~/ngs_scripts pull origin main`.  
Enter the gisaid directory `cd ~/ngs_scripts/gisad`.  
Run the Nextflow pipeline `nextflow run main.nf -profile local --submitter USERNAME --LW /mnt/N/NGS_FHI_statistikk/latest_file.tsv --min_date "2023-01-01"`.
  
## Upload to Gisaid
Upload to GISAID using version 4 of the cli:
```
covCLI upload --username USERNAME --password PASSWORD --clientid CLIENTID --log Gisaid_files/2024-01-09_submission.log --metadata Gisaid_files/2024-01-09_metadata_raw_submit.csv --fasta Gisaid_files/2024-01-09_raw.fasta --frameshifts catch_novel --dateformat YYYYMMDD
```

Create BioNumerics import file:
```
Rscript bin/create_BN_import.R Gisaid_files/2023-05-03_submission.log Gisaid_files/2023-05-03_frameshift_results.csv
```

