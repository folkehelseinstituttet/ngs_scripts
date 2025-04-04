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
