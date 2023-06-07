Pipeline to prepare and create files for submitting SARS-CoV-2 consensus sequences to GISAID. The pipeline only requires Nextflow and Docker installed in order to run. However, there are several features of the various scripts that will only work on the internal datastructures of NIPH. 

First time, clone this repo:
```
git clone git@github.com:jonbra/FHI_Gisaid.git
```

Make sure the N-drive is mounted to `/mnt/N`:
```
sudo mount -t drvfs N: /mnt/N 
```

Example run:
```
nextflow run main.nf -profile local --submitter jonbra
```

Upload to GISAID using gisaid_cl3:   
```
source gisaid_cli3/cli3venv/bin/activate

cli3 upload --metadata Gisaid_files/2023-05-03.csv --fasta Gisaid_files/2023-05-03.fasta --frameshift catch_none --failed Gisaid_files/2023-05-03_failed_samples.out --log Gisaid_files/2023-05-03_submission.log --token /home/jonr/Downloads/gisaid_cli3/gisaid.authtoken
```

Create BioNumerics import file:
```
Rscript bin/create_BN_import.R Gisaid_files/2023-05-03_submission.log Gisaid_files/2023-05-03_frameshift_results.csv
```



