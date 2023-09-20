# FHI_Gisaid

Pipeline to prepare and create files for submitting SARS-CoV-2 consensus sequences to GISAID. The pipeline only requires Nextflow and Docker installed in order to run. However, there are several features of the various scripts that will only work on the internal datastructures of NIPH. 

## First time use

You need to have Ubuntu installed using WSL2 on your windows laptop. In Ubuntu, make sure you have `Git`, `Nextflow` and `Docker` installed and running on your computer. 

Install Nextflow:
```
# Java

# Nextflow
```

Install Docker:
```
```

Install Git:
```
```

Then clone this repo (run `git pull` frequently to have the latest updates):
```
git clone git@github.com:jonbra/FHI_Gisaid.git
```

Set up a directory to mount the N-drive:
```
mkdir -p /mnt/N
```

## Weekly updates
First retrieve the latest updates from the BioNumerics Covid19 server. **This has to be done using the Windows installation of R, not in Ubuntu**. Open a Power Shell terminal and type (replace the R-version number with your current version):
```
H:\>"C:\Program Files\R\R-4.0.4\bin\Rscript.exe" N:\Virologi\JonBrate\Prosjekter\refresh_data_from_BN.R
```

Then, in Ubuntu go to the cloned `FHI_Gisaid` directory.

Make sure the N-drive is mounted to `/mnt/N`:
```
sudo mount -t drvfs N: /mnt/N 
```

Run the pipeline:
```
nextflow run main.nf -profile local --submitter jonbra --LW path/to/LW-uttrekk
```

Upload to GISAID using gisaid_cl3:   
```
source /home/jonr/Downloads/gisaid_cli3/cli3venv/bin/activate

cli3 upload --metadata Gisaid_files/2023-05-03.csv --fasta Gisaid_files/2023-05-03.fasta --frameshift catch_none --failed Gisaid_files/2023-05-03_failed_samples.out --log Gisaid_files/2023-05-03_submission.log --token /home/jonr/Downloads/gisaid_cli3/gisaid.authtoken
```

```
deactivate
```  

Create BioNumerics import file:
```
Rscript bin/create_BN_import.R Gisaid_files/2023-05-03_submission.log Gisaid_files/2023-05-03_frameshift_results.csv
```




On the Ubuntu partition/WSL2 on the windows laptopts:
If R is not installed (you need the R-packages pdbc and tidyverse installed):
```
sudo apt-get update
sudo apt install r-base-core
```

Dependencies for odbc:
unixodbc-dev


