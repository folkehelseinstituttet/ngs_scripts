## Set up environment
BASE_DIR=/mnt/tempdata/
TMP_DIR=/mnt/tempdata/fastq
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//Pos1-fhi-svm01/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/HCV/
SMB_INPUT=NGS/3-Sekvenseringsbiblioteker/TEST/HCV/TEST

# $HOME/.smbcreds
USERNAME=
PASSWORD=

# Create directory to hold the output of the analysis
mkdir -p $HOME/$RUN
mkdir $TMP_DIR

### Prepare the run ###

echo "Copying fastq files from the N drive"
smbclient $SMB_HOST -A $SMB_AUTH -D $SMB_INPUT <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF
    

SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/ 
###dropper år for å kunne fungere for alle agens som ligger under 2-Resultater/
###UV = UkjentVirus (UV i sekvensnavn, UkjentVirus som resultatmappe)

#Hente fastq filene for gitt agens og samler de i en mappe
mkdir all_fastq_${AGENS}
for f in *${AGENS}*.fastq.gz ; do cp */${f} ./all_fastq_${AGENS}/; done

###Når man lastet ned med NextSeq variasjon av basespace.sh får man et ekstra mappe-nivå med "merged"

#Gå inn i mappen
cd all_fastq_${AGENS}

#Kjøre fastqc
fastqc *.fastq.gz
### skal dette også i docker?

#Kjøre kraken2
for a in $(ls *R1*q.*); do file=${a%%_*}; 
	kraken2 --paired --db /media/data/Kraken2_databases/Kraken_db/ --threads 4 
		--report ${file}.krakenreport ${file}*R1*.fastq.gz ${file}*R2*.fastq.gz; 
	echo ${file}; done
### Må endre hvor kraken hentes og kjøres med docker

#Samle alt i en multiqc-rapport
multiqc .
### endre til docker

#Endre navn på rapporten
mv multiqc_report.html ${RUN_NAME}_${AGENS}_multiqc_report.html
