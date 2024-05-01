# Commands for building custom Kraken2 databases and running Kraken2 on the NIPH ngs server

### Run as ngs user
```bash
sudo -u ngs /bin/bash
```

### Name the database
```bash
DBNAME=bunyavirales
```

### Create Kraken databases in the tempdata directory
```bash
mkdir -p /mnt/tempdata/$DBNAME
```

### Download the ncbi taxonomy
NB! Check if this file already exists under `/mnt/tempdata/Kraken_db/taxonomy`

```bash
docker run --rm \
    -v /mnt/tempdata/:/home/ \
    -w /home \
    quay.io/biocontainers/mulled-v2-5799ab18b5fc681e75923b2450abaa969907ec98:87fc08d11968d081f3e8a37131c1f1f6715b6542-0 \
    kraken2-build --download-taxonomy --db $DBNAME --use-ftp
```

### Build the custom database  
First we add virus genomes from RefSeq:
```bash
docker run --rm \
    -v /mnt/tempdata/:/home/ \
    -w /home \
    quay.io/biocontainers/mulled-v2-5799ab18b5fc681e75923b2450abaa969907ec98:87fc08d11968d081f3e8a37131c1f1f6715b6542-0 \
    kraken2-build --download-library viral --db $DBNAME
```  

Then we supply our custom file of virus sequences with NCBI accessions as the fasta header:  
```bash
docker run --rm \
    -v /mnt/tempdata/:/home/ \
    -v /path/to/custom/fasta:/input/ \
    -w /home \
    quay.io/biocontainers/mulled-v2-5799ab18b5fc681e75923b2450abaa969907ec98:87fc08d11968d081f3e8a37131c1f1f6715b6542-0 \
    kraken2-build --add-to-library /input/custom_fasta.fa--db $DBNAME
```

Run Kraken2 analysis. Example:
```bash
docker run --rm \
    -v /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/HCV/2024/NGS-Oppsett-04_Pegivirus:/input/ \
    -v /mnt/tempdata/:/home/ \
    -w /home \
    quay.io/biocontainers/mulled-v2-5799ab18b5fc681e75923b2450abaa969907ec98:87fc08d11968d081f3e8a37131c1f1f6715b6542-0 \
    kraken2 \
        --db /home/Kraken_db \\
        --threads 8 \\
        --report /home/kraken_hcv/2181022-HCV.kraken2.report.txt \\
        --gzip-compressed \\
        --paired \
        /input/2181022-HCV/2181022-HCV_S2_L001_R1_001.fastq.gz /input/2181022-HCV/2181022-HCV_S2_L001_R2_001.fastq.gz
```
