## Quick start guide

A wrapper that runs a MPXV ARTIC Nextflow pipeline for whole‑genome analysis of Monkeypox virus (MPXV) data generated on Oxford Nanopore devices.

The pipeline is designed for the tiling amplicon scheme from Welkers et al. (https://www.protocols.io/view/monkeypox-virus-whole-genome-sequencing-using-comb-n2bvj6155lk5/v1). It uses the ARTIC tools (https://github.com/artic-network/fieldbioinformatics) to generate consensus genomes and Nextclade (https://github.com/nextstrain/nextclade) for clade/lineage assignment.


#### How to run example 
```
screen -S mpxv_artic-TEST -d -m bash /home/ngs/ngs_scripts/mpxv_artic/wrapper.sh \
-r TEST \
-a MPX \
-y 2025
```
#### Options
* `-r, --run`
  Sequencing run name (e.g. `MPX012` or `TEST`). 

* `-a, --agens`
  Analysis group identifier (`MPX`).

* `-y, --year`
  Year of the sequencing run.

### Troubleshooting
Check status file 
```
cat ~/mpx_${RUN}_status.txt
```
View logs
```
tail -f ~/mpx_wrapper.log
tail -f ~/mpx_wrapper_error.log
```

## Samplesheet information
The pipeline requires a ${RUN}_samplesheet.csv as input which must be ";" separated (Default separator when creating csv files in Norwegian versions of Excel). 

Samplesheet example: 
```
PrøveNr;PrøveID;Ct;Fortynning;SampleDate;Kommentar;RunDate;RunName;barcode
1;sample1*;19;;10.07.2022;kommentar1;12.02.2025;TEST*;Barcode65*
2;sample3*;20;;10.07.2022;kommentar3;12.02.2025;TEST*;Barcode66*
```
`*` = Field MUST be filled in. 
