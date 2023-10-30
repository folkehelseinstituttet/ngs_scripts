### NY VERSJON v2 ######## I v2 er ICTV-databasen oppdatert og gaps og N'er er fjernet fra referansene.
						## I v2 er det lagt til opprettelse av consensus-sekvens

### Versjon 3 ble hoppet over ###

### NY VERSJON v4 ######## Duplikater fjernes før consensus lages


### NY VERSJON v5 ######## I v5 er det gjort store endringer på rekkefølgen av de ulike delene 
                        ## Stringens økt fra 85 til 95 i andre mapping
                        ## Lagt til coverage-plot og statistikk etter duplikater - info til pdf er nå uten duplikater
                        ## Consensus lages kun ved minimum 6 i dybde. Settes inn N'er ved 5 eller mindre. (etter duplikater er fjernet)
                        ## Endret å få ut % covered above 9 til above 5 og alle % covered er nå uten duplikater
                        ## Endret en del av parameterne som hentes ut til csv og pdf
                        ## GLUE-rapport lages fra bam-fil uten duplikater
                        ## For å kjøre igjennom minor-loop må den aktuelle referansen ha vært dekt med minst 5 % i føste runde med mapping

### NY VERSJON v6 ######## Oppdater mappestruktur
						## SeqID starter ikke lengre med "Virus". Oppdatert følgene av dette.
                        ## Tatt ut pdf-rapport - dvs. del av DEL 5 
                        ## (weeSAMv1.4 coverage-plot fungerer ikke lengre på NGS2)
                        ## Henter ut dekning ved 10x istedenfor ved 30x
                        ## Opprettet samle-fasta for run

### NY VERSJON v7 ######## Nytt format på GLUE-rapport
                        ## Summaries-filen er oppdatert: kolonner og rader er bytte om og sorteringen fikset slik at det blir A1, B1, C1 og ikke A1, A2, A3
                        ## Lagt til ny versjon av weeSAM (slutten av skriptet)

### NY VERSJON v8 ######## Resultat fra GLUE-rapport samles nå i en ny summarie-fil summary_with_glue.tsv
### NY VERSJON v9 ######## Lagt til kolonner i (...)summary.csv og følgelig i (...)summary_with_glue.tsv:
					#Total number of reads before trim:
					#Total number of reads after trim:
					#Majority quality: 			
					#Minor quality:
			## For å få til at det bare er tom celle for quality når alt er ok er det lagt til "TOM" i hver celle i csv-filene som lages per prøve og så fjernes dette igjen fra slutt-filene. (Ble forskyvninger ved transponering av rader og kolonner hvis ikke.)
			## Lagt til automatisk kopiering av summarie-mappen til N:

### NY VERSJON v9.1 ###### Gjort klart for sekvensID på formen xxxxxx-HCV (vs. HCVxxxxx)
			## Lagt til avrunding av %dekning 1x til 2 desimaler og dybde (uten duplikater) til 0 desimaler

## Skript startes fra run-mappen (f.eks. Run443)
source activate /home/ngs3/miniconda3/envs/Illumina

basedir=$(pwd)
runname=${basedir##*/}

#husk å legge inn Rscript_sumreads.R
scriptdir="/home/${HOSTNAME}/.fhiscripts/"
#tanotidir=/home/ngs2/Downloads/Tanoti-1.2-Linux/
#weesamdir=/home/ngs2/.fhiscripts/weeSAM/
script_name1=`basename $0`
#skille software fra rapportering
#VirusScriptDir=/home/ngs2/.fhiscripts/VirusScriptParts/
Aar=$([ "$OSTYPE" = linux-gnu ] && date --date="4 days ago" +"%Y" || date -v-4d +"%Y") 

###### DATABASER/REFERANSESEKVENSER ########
HCV_RefDir=Referanser_HCV_ICTV_190508_clean
#HEV_RefDir=/media/data/Referanser_HEV
#Corona_RefDir=/media/data/Referanser_Corona
#Dengue_RefDir=/media/data/Referanser_Dengue
#Entero_RefDir=/media/data/Referanser_Entero
#TBEV_RefDir=/media/data/Referanser_TBEV

########## FYLL INN FOR AGENS ###################
# kan også legge til trimming-setinger her om man ønsker muligheten for at det skal være ulikt (phred-score og minimum lengde på read) 

#Skriv inn agens-navn (må være skrevet likt som i navnet på fasta-fil som inneholder databasen/referansesekvensene
Agens=HCV					#ingen mellomrom etter =

#husk å legge inn rett variabel for filbanen til databasen/referansesekvensene (se under "DATABASER/REFERANSESEKVENSER")
Refdir=${HCV_RefDir}	# f.eks. ${HCV_RefDir}

#presisere stringency for mapping, 1-100
String=85 				#Stringens i første mapping     ingen mellomrom etter =
String2=95                #Stringens i andre mapping (hoved og minor)

#Definere hvor mange read det må være mappet mot agens før det gjøres mapping mot minoritetsvariant, f.eks. 50000
minAgensRead=50000			#ingen mellomrom etter =
#Definere grense for "Typbar" genotype:
Covlimit=10 
Depthlimit=2


######## DEL 1 Trimming #### START ######

basedir=$(pwd)
runname=${basedir##*/}

for dir in $(ls -d *${Agens}*/)
do
    cd ${dir}
    R1=$(ls *_R1*.fastq.gz)
    R2=$(ls *_R2*.fastq.gz)
#trim
    trim_galore -q 30 --dont_gzip --length 50 --paired ${R1} ${R2}
    
    cd "${basedir}"
done

echo "#"
echo "Read ferdig trimmet" 
echo "#"
echo "###################"


######## DEL 1 Trimming #### SLUTT ######


######## DEL 2 Mapping #### START ######
basedir=$(pwd)
runname=${basedir##*/}

for dir in $(ls -d *${Agens}*/)
do
    cd ${dir}
	R1=$(ls *_R1*.fastq.gz)
    newR1=$(ls *val_1.fq)
    newR2=$(ls *val_2.fq)

#align vs. entire db
    cp ${Refdir}/*${Agens}*.fa . # Copy input reference fasta to pwd
    docker run --rm -v ${pwd}:/input jonbra/viral_haplo:1.3 tanoti -r /input/${Refdir}/*${Agens}*.fa -i /input/${newR1} /input/${newR2} -o /input/${R1%%_*L001*}_tanoti.sam -p 1 -u 1 -m ${String} #dobbel % fjerner lengste mulige substring, enkelt % fjerner korteste mulige substring i ${variable%substring}
    newR4=$(ls *_tanoti.sam)
    samtools view -bS ${newR4} | samtools sort -o ${newR4%.sam}_sorted.bam
    samtools index ${newR4%.sam}_sorted.bam
    docker run --rm -v ${pwd}:/input jonbra/weesam_docker:1.0 weeSAMv1.4 -b /input/${newR4%.sam}_sorted.bam -out /input/${newR4%.sam}_stats.txt 
    Rscript --vanilla ${scriptdir}Rscript_sumreads.R "${newR4%.sam}_stats.txt" "${newR4%.sam}_sumstats.txt" # Beregner også prosent av totalt antall agens read
	
	sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt > ${newR4%.sam}_stats_sorted.txt #Ikke nødvendig, men gjør det lettere å gå tilbake å se på resultatene fra første mapping	
	
#align vs. best hit
    major=$(sed -n 2p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)  
    bestF1=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${major} -m1 | cut -f1) #Finne første referanse i _stats.txt som inneholder "major" og bruke denne som referanse for mapping   
    bestF2="${R1%%_*L001*}_${bestF1%_*}" # brukes til navnsetting av outputfil 
    tanoti -r ${Refdir}/${bestF1}.fa -i ${newR1} ${newR2} -o ${bestF2}_tanoti_vbest.sam -p 1 -m ${String2}
    bestF3=$(ls *_tanoti_vbest.sam)
    samtools view -bS ${bestF3} | samtools sort -o ${bestF3%.sam}_sorted.bam
    samtools index ${bestF3%.sam}_sorted.bam
   

    cd "${basedir}"
done


echo "HEY HEY HEY, What's that sound?" 
echo "Mapping done!
"



######## DEL 2 Mapping #### SLUTT ######


######## DEL 2b Mapping mot minority #### START ######

basedir=$(pwd)
runname=${basedir##*/}

for dir in $(ls -d *${Agens}*/)
do
    cd ${dir}
	R1=$(ls *_R1*.fastq.gz)
    newR1=$(ls *val_1.fq)
    newR2=$(ls *val_2.fq)


	
 #align vs. next best genotype 
    newR4=$(ls *_tanoti.sam)
    sumAgensRead=$(awk 'FNR > 1 {print $2}' *sumstats.txt| paste -sd+ | bc)
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)
    bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)     #Finne første referanse i _stats.txt som inneholder "minor" og bruke denne som referanse for mapping 
    bestMinor_percCov=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ${bestMinor} -m1 | cut -f5)     #Finner hvor godt dekt referansen var i første mapping
    bestMinor_percCov2=${bestMinor_percCov/.*}          #Fjerner desimaler for at "if"-setningen skal gjenkjenne tallet
    bestMinor2="${R1%%_*L001*}_${bestMinor%_*}"
    
	
	if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then      
   
    tanoti -r ${Refdir}/${bestMinor}.fa -i ${newR1} ${newR2} -o ${bestMinor2}_tanoti_bestMinor.sam -p 1 -m ${String2}
    bestMinor3=$(ls *_tanoti_bestMinor.sam)
    samtools view -bS ${bestMinor3} | samtools sort -o ${bestMinor3%.sam}_sorted.bam
    samtools index ${bestMinor3%.sam}_sorted.bam
    
    else
    echo "
    Møter ikke kriteriene for mapping mot minority
    "
    
	fi


    cd "${basedir}"

done



echo "HEY HEY HEY, What's that sound?" 
echo "Mapping against minority done!
"

######## DEL 2b Mapping mot minority #### SLUTT######



######## DEL 3 VariantCalling og Consensus #### START ######

basedir=$(pwd)
runname=${basedir##*/}

for dir in $(ls -d *${Agens}*/)
do

cd ${dir}

# Lage konsensus for Main-genotype
	newR4=$(ls *_tanoti.sam) 
	major=$(sed -n 2p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)  
	bestF1=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${major} -m1 | cut -f1)
	bestF3=$(ls *_tanoti_vbest.sam)

	samtools sort -n ${bestF3%.sam}_sorted.bam > ${bestF3%.sam}_sorted.byQuery.bam 
	samtools fixmate -m ${bestF3%.sam}_sorted.byQuery.bam ${bestF3%.sam}_sorted.fix.bam
	samtools sort ${bestF3%.sam}_sorted.fix.bam > ${bestF3%.sam}_sorted.fix_sorted.bam

	samtools markdup -r ${bestF3%.sam}_sorted.fix_sorted.bam ${bestF3%.sam}_sorted.marked.bam
	bcftools mpileup -f ${Refdir}/${bestF1}.fa ${bestF3%.sam}_sorted.marked.bam| bcftools call -mv -Ob -o calls.vcf.gz
	bcftools index calls.vcf.gz

#	bedtools genomecov -bga -ibam ${bestF3%.sam}_sorted.marked.bam| grep -w '0$' > regionswith0coverage.bed   # '0$\|1$\|2$\|3$\|4$\|5$' > regionswithlessthan6coverage
#	bcftools consensus -m regionswith0coverage.bed -f ${Refdir}${bestF1}.fa calls.vcf.gz -o cons.fa

    samtools index ${bestF3%.sam}_sorted.marked.bam

    bedtools genomecov -bga -ibam ${bestF3%.sam}_sorted.marked.bam| grep -w '0$\|1$\|2$\|3$\|4$\|5$' > regionswithlessthan6coverage.bed   
	bcftools consensus -m regionswithlessthan6coverage.bed -f ${Refdir}/${bestF1}.fa calls.vcf.gz -o cons.fa

	seqkit replace -p "(.+)" -r ${bestF3%%_*} cons.fa > ${bestF3%%_*}_consensus.fa #endrer navn fra referanse-navn til prøvenavn inne i fasta-fil
	
#sletter filer som ikke trengs videre: 
	rm *cons.fa 
	rm *calls*.vcf.gz
	rm *calls*.vcf.gz.csi 
	rm *regionswith*coverage.bed 
	rm *_sorted.byQuery.bam 
	rm *_sorted.fix.bam
	rm *_sorted.fix_sorted.bam



# Lage konsensus for minoritet-genotype

	sumAgensRead=$(awk 'FNR > 1 {print $2}' *sumstats.txt| paste -sd+ | bc)
    newR4=$(ls *_tanoti.sam)    
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)    
    bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)
    bestMinor_percCov=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ${bestMinor} -m1 | cut -f5)    
    bestMinor_percCov2=${bestMinor_percCov/.*}  

	
	if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then 
		bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)
		bestMinor3=$(ls *_tanoti_bestMinor.sam)

		samtools sort -n ${bestMinor3%.sam}_sorted.bam > ${bestMinor3%.sam}_sorted.byQuery.bam 
		samtools fixmate -m ${bestMinor3%.sam}_sorted.byQuery.bam ${bestMinor3%.sam}_sorted.fix.bam
		samtools sort ${bestMinor3%.sam}_sorted.fix.bam > ${bestMinor3%.sam}_sorted.fix_sorted.bam

		samtools markdup -r ${bestMinor3%.sam}_sorted.fix_sorted.bam ${bestMinor3%.sam}_sorted.marked.bam
		bcftools mpileup -f ${Refdir}/${bestMinor}.fa ${bestMinor3%.sam}_sorted.marked.bam| bcftools call -mv -Ob -o calls.vcf.gz
		bcftools index calls.vcf.gz

		#bedtools genomecov -bga -ibam ${bestMinor3%.sam}_sorted.marked.bam| grep -w '0$' > regionswith0coverage.bed   # '0$\|1$\|2$\|3$\|4$\|5$' > regionswithlessthan6coverage
		#bcftools consensus -m regionswith0coverage.bed -f ${Refdir}${bestMinor}.fa calls.vcf.gz -o cons.fa
        
        samtools index ${bestMinor3%.sam}_sorted.marked.bam

        bedtools genomecov -bga -ibam ${bestMinor3%.sam}_sorted.marked.bam| grep -w '0$\|1$\|2$\|3$\|4$\|5$' > regionswithlessthan6coverage.bed   
		bcftools consensus -m regionswithlessthan6coverage.bed -f ${Refdir}/${bestMinor}.fa calls.vcf.gz -o cons.fa
   

		seqkit replace -p "(.+)" -r ${bestMinor3%%_*}_Minor cons.fa > ${bestMinor3%%_*}_Minor_consensus.fa #endrer navn fra referanse-navn til prøvenavn inne i fasta-fil
				
		
		#sletter filer som ikke trengs videre: 
		rm *cons.fa 
		rm *calls*.vcf.gz
		rm *calls*.vcf.gz.csi 
		rm *regionswith*coverage.bed 
		rm *_sorted.byQuery.bam 
		rm *_sorted.fix.bam
		rm *_sorted.fix_sorted.bam
	fi




cd "${basedir}"


done

echo "
Consensus made
" 

######## DEL 3 VariantCalling og Consensus #### SLUTT ######


######## DEL 4 CoveragePlot og Statistikk #### START ######
basedir=$(pwd)
runname=${basedir##*/}

for dir in $(ls -d *${Agens}*/)
do
    cd ${dir}
	
# Coverage plot og statistikkmed duplikater
	bestF3=$(ls *_tanoti_vbest.sam)
	weeSAMv1.4 -b ${bestF3%.sam}_sorted.bam -out ${bestF3%.sam}_stats.txt 
   # weeSAMv1.6 --bam ${bestF3%.sam}_sorted.bam --out ${bestF3%.sam}_stats.txt --html ${bestF3%.sam}.html

# Coverage plot og statistikk uten duplikater	
	weeSAMv1.4 -b ${bestF3%.sam}_sorted.marked.bam -out ${bestF3%.sam}.marked_stats.txt 
    #weeSAMv1.6 --bam ${bestF3%.sam}_sorted.marked.bam --out ${bestF3%.sam}.marked_stats.txt --html ${bestF3%.sam}_marked.html
	
	
    sumAgensRead=$(awk 'FNR > 1 {print $2}' *sumstats.txt| paste -sd+ | bc)
    newR4=$(ls *_tanoti.sam)    
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)    
    bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)
    bestMinor_percCov=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ${bestMinor} -m1 | cut -f5)    
    bestMinor_percCov2=${bestMinor_percCov/.*}   

	if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then
	
# Coverage plot og statistikk med duplikater for minor
		bestMinor3=$(ls *_tanoti_bestMinor.sam)
		weeSAMv1.4 -b ${bestMinor3%.sam}_sorted.bam -out ${bestMinor3%.sam}_stats.txt 
        #weeSAMv1.6 --bam ${bestMinor3%.sam}_sorted.bam --out ${bestMinor3%.sam}_stats.txt --html ${bestMinor3%.sam}.html

# Coverage plot og statistikk uten duplikater	for minor		
		weeSAMv1.4 -b ${bestMinor3%.sam}_sorted.marked.bam -out ${bestMinor3%.sam}.marked_stats.txt 
		#weeSAMv1.6 --bam ${bestMinor3%.sam}_sorted.marked.bam --out ${bestMinor3%.sam}.marked_stats.txt --html ${bestMinor3%.sam}_marked.html
    fi


cd "${basedir}"


done

echo "Popped som plots - not"

######## DEL 4 CoveragePlot og Statistikk #### SLUTT ######


######## DEL 5 Identifisere parametere, lage summary for hver prøve #### START ######
basedir=$(pwd)
runname=${basedir##*/}

# Går inn i hver mappe og identifiserer ulike parametere og legger det inn i en csv fil 
for dir in $(ls -d *${Agens}*/)
do
    cd ${dir}
#identify & log
    R1=$(ls *_R1*.fastq.gz)
    R2=$(ls *_R2*.fastq.gz)
    newR1=$(ls *val_1.fq)
    newR2=$(ls *val_2.fq)
    newR4=$(ls *_tanoti.sam)
    major=$(sed -n 2p  *_tanoti_sumstats.txt | cut -d " " -f1| cut -d'"' -f2)      
    bestF1=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${major} -m1 | cut -f1)    
    bestF2="${R1%%_L001*}_v_${bestF1%_H*}"
    bestF3=$(ls *_tanoti_vbest.sam)
    bestF4=$(ls *_tanoti_vbest_sorted.bam) 
    readsb4=$(echo $(zcat ${R1}|wc -l)/2|bc)        #delt på 2 istedenfor 4 for å få reads for R1 og R2
    readsafter=$(echo $(cat ${newR1}|wc -l)/2|bc)
    readstrim=$(echo "scale=2 ; (($readsb4-$readsafter)/$readsb4)*100" | bc)
#   bpb4=$(zcat ${R1} | paste - - - - | cut -f2 | wc -c)     #gange 2 for å få bp for R1 og R2   
#   bpb4_2=$(echo "scale=2 ; $bpb4*2" | bc)
#   bpafter=$(cat ${newR1} | paste - - - - | cut -f2 | wc -c)
#   bpafter_2=$(echo "scale=2 ; $bpafter*2" | bc)
#   bptrim=$(echo "scale=2 ; (($bpb4-$bpafter) / $bpb4)*100" | bc)
    wee1113=$(sort -t$'\t' -k3 -nr *_tanoti_vbest_stats.txt | grep -m1 "" | cut -f3)
	if [ $wee1113 == MappedReads ]; then wee1113=NA; fi
    mapreadsper=$(echo "scale=2 ; ($wee1113 / $readsafter) *100" | bc)
#   mapbp=$(awk '{s+=$4}END{print s}' ${bestF3%.sam}_sorted_aln.bam)
#   mapbpper=$(echo "scale=2 ; ($mapbp / $bpafter_2) *100" | bc)
    wee1114=$(sort -t$'\t' -k3 -nr *_tanoti_vbest_stats.txt | grep -m1 "" | cut -f5)
	wee1114=$(echo "scale=2 ; ${wee1114} /1" | bc)
	if [ $wee1114 == PercentCovered ]; then wee1114=NA; fi
    wee1115=$(sort -t$'\t' -k3 -nr *_tanoti_vbest_stats.txt | grep -m1 "" | cut -f8)
   
    percmajor=$(sed -n 2p  *_tanoti_sumstats.txt | cut -d " " -f3)
    percmajor_2=$(echo "scale=2 ; $percmajor*100" | bc)
    sumAgensRead=$(awk 'FNR > 1 {print $2}' *sumstats.txt| paste -sd+ | bc)    

   # wee11=$(ls *_tanoti_vbest.pdf)
    # wee12=$(ls *_tanoti_bestMinor.pdf)    
     
   # bedtools genomecov -ibam ${bestF3%.sam}_sorted.bam -bga > ${bestF3%.sam}_sorted_aln.bam 
   # LengthBelowDepth6=$(awk '$4 <6' *vbest_sorted_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
   # LengthBelowDepth30=$(awk '$4 <30' *vbest_sorted_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    RefLength=$(awk 'FNR == 2 {print $2}' *vbest_stats.txt)
   # PercCovAboveDepth5=$(echo "scale=5;(($RefLength-$LengthBelowDepth6)/$RefLength)*100" |bc)    
   # PercCovAboveDepth29=$(echo "scale=5;(($RefLength-$LengthBelowDepth30)/$RefLength)*100" |bc)


    # After removal of duplicates
    wee1120=$(sort -t$'\t' -k3 -nr *_tanoti_vbest.marked_stats.txt | grep -m1 "" | cut -f3)
    	if [ $wee1120 == MappedReads ]; then wee1120=NA; fi
    wee1121=$(sort -t$'\t' -k3 -nr *_tanoti_vbest.marked_stats.txt | grep -m1 "" | cut -f8)
    wee1121=$(echo "scale=0 ; ${wee1121} /1" | bc)
	if [ $wee1121 == AverageDepth ]; then wee1121=NA; fi
   # wee13=$(ls *_tanoti_vbest_marked.pdf)
   # wee14=$(ls *_tanoti_bestMinor_marked.pdf)

    bedtools genomecov -ibam ${bestF3%.sam}_sorted.marked.bam -bga > ${bestF3%.sam}_sorted.marked_aln.bam 
    W_LengthBelowDepth6=$(awk '$4 <6' *vbest_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    W_LengthBelowDepth10=$(awk '$4 <10' *vbest_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    W_LengthBelowDepth30=$(awk '$4 <30' *vbest_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    W_PercCovAboveDepth5=$(echo "scale=5;(($RefLength-$W_LengthBelowDepth6)/$RefLength)*100" |bc)  
    W_PercCovAboveDepth9=$(echo "scale=5;(($RefLength-$W_LengthBelowDepth10)/$RefLength)*100" |bc)      
    W_PercCovAboveDepth29=$(echo "scale=5;(($RefLength-$W_LengthBelowDepth30)/$RefLength)*100" |bc)


 #minor genotype
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)
    percminor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f3)
    percminor_2=$(echo "scale=2 ; $percminor*100" | bc)
    bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)
    bestMinor_percCov=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ${bestMinor} -m1 | cut -f5)    
    bestMinor_percCov2=${bestMinor_percCov/.*}  

if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then     
    bestMinor3=$(ls *_tanoti_bestMinor.sam)
    minor2=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)
    wee1116=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor_stats.txt | grep -m1 "" | cut -f3)    
    wee1117=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor_stats.txt | grep -m1 "" | cut -f5)
    wee1118=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor_stats.txt | grep -m1 "" | cut -f8)
   # bedtools genomecov -ibam ${bestMinor3%.sam}_sorted.bam -bga > ${bestMinor3%.sam}_sorted_aln.bam
   # M_LengthBelowDepth6=$(awk '$4 <6' *Minor_sorted_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
   # M_LengthBelowDepth30=$(awk '$4 <30' *Minor_sorted_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    M_RefLength=$(awk 'FNR == 2 {print $2}' *bestMinor_stats.txt)
   # M_PercCovAboveDepth5=$(echo "scale=5;(($M_RefLength-$M_LengthBelowDepth6)/$M_RefLength)*100" |bc)    
   # M_PercCovAboveDepth29=$(echo "scale=5;(($M_RefLength-$M_LengthBelowDepth30)/$M_RefLength)*100" |bc)

    # After removal of duplicates
    wee1122=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor.marked_stats.txt | grep -m1 "" | cut -f3)    
    wee1123=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor.marked_stats.txt | grep -m1 "" | cut -f5)
    wee1124=$(sort -t$'\t' -k3 -nr *_tanoti_bestMinor.marked_stats.txt | grep -m1 "" | cut -f8)
 
    bedtools genomecov -ibam ${bestMinor3%.sam}_sorted.marked.bam -bga > ${bestMinor3%.sam}_sorted.marked_aln.bam
    WM_LengthBelowDepth6=$(awk '$4 <6' *Minor_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    WM_LengthBelowDepth10=$(awk '$4 <10' *Minor_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    WM_LengthBelowDepth30=$(awk '$4 <30' *Minor_sorted.marked_aln.bam | awk '{a=$3-$2;print $0,a;}' | awk '{print $5}' | paste -sd+ | bc)
    WM_PercCovAboveDepth5=$(echo "scale=5;(($M_RefLength-$WM_LengthBelowDepth6)/$M_RefLength)*100" |bc)  
    WM_PercCovAboveDepth9=$(echo "scale=5;(($M_RefLength-$WM_LengthBelowDepth10)/$M_RefLength)*100" |bc)    
    WM_PercCovAboveDepth29=$(echo "scale=5;(($M_RefLength-$WM_LengthBelowDepth30)/$M_RefLength)*100" |bc)
else
    minor2=NA
    wee1122=NA
    wee1117=NA
    WM_PercCovAboveDepth5=NA
    wee1124=NA
    
fi


#write bit
echo "Parameters, ${dir%/}" >> ${dir%/}_summary.csv
#echo "Total_number_of_reads_before_trim:, ${readsb4}"  >> ${dir%/}_summary.csv
#echo "Total_number_of_reads_after_trim:, ${readsafter}" >> ${dir%/}_summary.csv
#echo "Percent_reads_trimmed_removed:, ${readstrim}" >> ${dir%/}_summary.csv
#echo "Total_mapped_${Agens}_reads:, ${sumAgensRead}" >> ${dir%/}_summary.csv
echo "Percent_mapped_reads_of_trimmed:, TOM${mapreadsper}" >> ${dir%/}_summary.csv # mot den enkelte referansen etter andre runde mapping
#echo "Total_bp_before_trim:, ${bpb4_2}" >> ${dir%/}_summary.csv
#echo "Total_bp_after_trim:, ${bpafter_2}" >> ${dir%/}_summary.csv
#echo "Percent_bp_trimmed_removed:, ${bptrim}" >> ${dir%/}_summary.csv
echo "Majority_genotype:, TOM${major}" >> ${dir%/}_summary.csv
#echo "Best_hit_from_database:, ${bestF1}" >> ${dir%/}_summary.csv
#echo "Percent_majority_genotype:, ${percmajor_2}" >> ${dir%/}_summary.csv
echo "Number_of_mapped_reads:, TOM${wee1113}" >> ${dir%/}_summary.csv
#echo "Mapped_bp:, ${mapbp}" >> ${dir%/}_summary.csv
#echo "Percent_mapped_bp_of_trimmed:, ${mapbpper}" >> ${dir%/}_summary.csv
echo "Percent_covered:, TOM${wee1114}" >> ${dir%/}_summary.csv
#echo "Average_depth:, ${wee1115}" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=5:, ${PercCovAboveDepth5}" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=29:, ${PercCovAboveDepth29}" >> ${dir%/}_summary.csv


# After removal of duplicates
echo "Number_of_mapped_reads_without_duplicates:, TOM${wee1120}" >> ${dir%/}_summary.csv
echo "Average_depth_without_duplicates:, TOM${wee1121}" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=5_without_duplicates:, TOM${W_PercCovAboveDepth5}" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=9_without_duplicates:, TOM${W_PercCovAboveDepth9}" >> ${dir%/}_summary.csv

echo "Most_abundant_minority_genotype:, TOM${minor}" >> ${dir%/}_summary.csv

if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then  
#echo "Best_hit_from_database_minor:, ${bestMinor}" >> ${dir%/}_summary.csv
echo "Percent_most_abundant_minority_genotype:, TOM${percminor_2}" >> ${dir%/}_summary.csv
echo "Number_of_mapped_reads_minor:, TOM${wee1116}" >> ${dir%/}_summary.csv
echo "Percent_covered_minor:, TOM${wee1117}" >> ${dir%/}_summary.csv
#echo "Average_depth_minor:, ${wee1118}" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=5_minor:, ${M_PercCovAboveDepth5}" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=29_minor:, ${M_PercCovAboveDepth29}" >> ${dir%/}_summary.csv
echo "Number_of_mapped_reads_minor_without_duplicates:, TOM${wee1122}" >> ${dir%/}_summary.csv
echo "Average_depth_minor_without_duplicates:, TOM${wee1124}" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=5_minor_without_duplicates:, TOM${WM_PercCovAboveDepth5}" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=9_minor_without_duplicates:, TOM${WM_PercCovAboveDepth9}" >> ${dir%/}_summary.csv

else
#echo "Best_hit_from_database_minor:, NA" >> ${dir%/}_summary.csv 
echo "Percent_most_abundant_minority_genotype:, TOM${percminor_2}" >> ${dir%/}_summary.csv
echo "Number_of_mapped_reads_minor:, NA" >> ${dir%/}_summary.csv
echo "Percent_covered_minor:, NA" >> ${dir%/}_summary.csv
#echo "Average_depth_minor:, NA" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=5_minor:, NA" >> ${dir%/}_summary.csv
#echo "Percent_covered_above_depth=29_minor:, NA" >> ${dir%/}_summary.csv
echo "Number_of_mapped_reads_minor_without_duplicates:, NA" >> ${dir%/}_summary.csv
echo "Average_depth_minor_without_duplicates:,  NA" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=5_minor_without_duplicates:, NA" >> ${dir%/}_summary.csv
echo "Percent_covered_above_depth=9_minor_without_duplicates:, NA" >> ${dir%/}_summary.csv
fi

echo "Script_name_and_stringency:, ${script_name1}(${String}/${String2})" >> ${dir%/}_summary.csv


#Lagt til i v9:

echo "Total_number_of_reads_before_trim:, TOM${readsb4}"  >> ${dir%/}_summary.csv
echo "Total_number_of_reads_after_trim:, TOM${readsafter}" >> ${dir%/}_summary.csv

wee1114b=${wee1114%.*}
wee1121b=${wee1121%.*}
if [ ${wee1114b} -ge ${Covlimit} ] && [ ${wee1121b} -ge ${Depthlimit} ]; then
echo "Majority_quality:, TOM" >> ${dir%/}_summary.csv
#echo "Majority quality:, " 
elif [${wee1114} == ""]; then 
	echo "Majority_quality:, NA" >> ${dir%/}_summary.csv
	#echo "Majority quality:, NA" 
else
echo "Majority_quality:, Ikke_typbar" >> ${dir%/}_summary.csv
#echo "Majority quality:, Ikke typbar"
fi

wee1117b=${wee1117%.*}
wee1124b=${wee1124%.*}
if [ ${wee1117b} -ge ${Covlimit} ] && [ ${wee1124b} -ge ${Depthlimit} ]; then
echo "Minor_quality:, TOM" >> ${dir%/}_summary.csv
#echo "Minor quality:, " 
elif [${wee1114} == ""]; then 
	echo "Minor_quality:, NA" >> ${dir%/}_summary.csv
	#echo "Minor quality:, NA" 
else
echo "Minor_quality:, Ikke_typbar" >> ${dir%/}_summary.csv
#echo "Minor quality:, Ikke typbar"
fi



cd ..

done

######## DEL 5 Identifisere parametere, lage summary for hver prøve #### STOPP ######

######## GLUE #### START ######
## bruker bam-filene uten duplikater

basedir=$(pwd)
runname=${basedir##*/}
docker start gluetools-mysql #starter først gluetools-mysql docker (lagt inn fordi docker stopper å kjøre ved restart av pc)

for dir in $(ls -d *${Agens}*/)
do
   cd ${dir}
   newR5=$(ls *_tanoti_vbest_sorted.marked.bam)
   pwd=$(pwd)
  docker run --rm --name gluetools -v ${pwd}:/opt/bams -w /opt/bams --link gluetools-mysql cvrbioinformatics/gluetools:latest gluetools.sh --console-option log-level:FINEST --inline-cmd project hcv module phdrReportingController invoke-function reportBamAsHtml ${newR5} 15.0 ${newR5%.bam}.html
  
# Det produseres json-fil også for prøver uten data, det skaper krøll. Lagt derfor til betingelse om at html-filen skal eksistere før det opprettes en json-fil
if [[ -f ${newR5%.bam}.html ]]; then 
    docker run --rm --name gluetools -v ${pwd}:/opt/bams -w /opt/bams --link gluetools-mysql cvrbioinformatics/gluetools:latest gluetools.sh -p cmd-result-format:json -EC -i project hcv module phdrReportingController invoke-function reportBam ${newR5} 15.0 > ${newR5%.bam}.json
else 
    echo "GLUE-rapport eksistere ikke"
fi 
  
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)
    percminor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f3)
    percminor_2=$(echo "scale=2 ; $percminor*100" | bc)
    sumAgensRead=$(awk 'FNR > 1 {print $2}' *sumstats.txt| paste -sd+ | bc)
    newR4=$(ls *_tanoti.sam)    
    minor=$(sed -n 3p  *_tanoti_sumstats.txt | cut -d " " -f1 | cut -d'"' -f2)    
    bestMinor=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ^${minor}_ -m1 | cut -f1)
    bestMinor_percCov=$(sort -t$'\t' -k3 -nr ${newR4%.sam}_stats.txt | grep ${bestMinor} -m1 | cut -f5)    
    bestMinor_percCov2=${bestMinor_percCov/.*} 


    if [ ${sumAgensRead} -gt ${minAgensRead} ] && [ ${bestMinor_percCov2} -gt 5 ]; then   
        M_newR5=$(ls *_tanoti_bestMinor_sorted.marked.bam)
        pwd=$(pwd)
        docker run --rm --name gluetools -v ${pwd}:/opt/bams -w /opt/bams --link gluetools-mysql cvrbioinformatics/gluetools:latest gluetools.sh --console-option log-level:FINEST --inline-cmd project hcv module phdrReportingController invoke-function reportBamAsHtml ${M_newR5} 15.0 ${M_newR5%.bam}.html

fi

    cd "${basedir}"
done

echo "DAA-resistant polymorphisms identified" 

######## GLUE #### STOPP ######


######## DEL 6 Sammenfatte resultater #### START ######
basedir=$(pwd)
runname=${basedir##*/}

mkdir "./${runname}_summaries"
cd ${runname}_summaries
mkdir fasta
mkdir bam
mkdir GLUE-rapport
mkdir GLUE-rapport_json
mkdir sumstats
#mkdir bam/withDuplicates
#mkdir QC 
cd ..

for dir in $(ls -d *${Agens}*/)
do

	cp ${dir}/*_summary.csv "./${runname}_summaries/"
	cp ${dir}/*.html "./${runname}_summaries/GLUE-rapport"
    cp ${dir}/*.json "./${runname}_summaries/GLUE-rapport_json"
	  
    cp ${dir}/*sumstats* "./${runname}_summaries/sumstats"
    cp ${dir}/*stats_sorted* "./${runname}_summaries/sumstats"

	cp ${dir}/*_consensus.fa "./${runname}_summaries/fasta"

	cp ${dir}/*sorted.marked.bam "./${runname}_summaries/bam" 
    cp ${dir}/*sorted.marked.bam.bai "./${runname}_summaries/bam" 
	
done

#lager en fil .tmp for hver prøve hvor alle verdiene legges inn i (uten overskriftene) 
	cd "./${runname}_summaries"

	for f in $(ls *y.csv) 
	do
		sed 's/\./,/g' $f | awk 'BEGIN {OFS=","} {print $2}' | sed 's/\_/ /g' > $f-5.tmp
    done

echo "Parameters:" >> parameters                            # Lager en fil parameteres hvor alle oversikriftene legges 
#echo "Total number of reads before trim:"  >> parameters
#echo "Total number of reads after trim:" >> parameters
#echo "Percent reads removed with trimming:" >> parameters
#echo "Total mapped ${Agens} reads:" >> parameters
echo "Percent mapped reads of trimmed:" >> parameters
#echo "Total bp before trim:" >> parameters
#echo "Total bp after trim:" >> parameters
#echo "Percent bp trimmed/removed:" >> parameters
echo "Majority genotype:" >> parameters
#echo "Genotype /best hit in database:" >> parameters 
#echo "Percent majority genotype:" >> parameters
echo "Number of mapped reads:" >> parameters
#echo "Mapped bp:" >> parameters
#echo "Percent mapped bp of trimmed:" >> parameters
echo "Percent covered:" >> parameters
#echo "Average depth:" >> parameters
#echo "Percent covered above depth=5:" >> parameters
#echo "Percent covered above depth=29:" >> parameters

echo "Number of mapped reads without duplicates:" >> parameters
echo "Average depth without duplicates:" >> parameters
echo "Percent covered above depth=5 without duplicates:" >> parameters
echo "Percent covered above depth=9 without duplicates:" >> parameters

echo "Most abundant minority genotype:" >> parameters
#echo "Best hit for minor genotype:" >>parameters
echo "Percent most abundant minority genotype:" >> parameters
echo "Number of mapped reads minor:" >>parameters
echo "Percent covered minor:" >>parameters
#echo "Average depth minor:" >>parameters
#echo "Percent covered above depth=5 minor:" >> parameters
#echo "Percent covered above depth=29 minor:" >> parameters
echo "Number of mapped reads minor without duplicates:" >>parameters
echo "Average depth minor without duplicates:" >>parameters
echo "Percent covered above depth=5 minor without duplicates:" >> parameters
echo "Percent covered above depth=9 minor without duplicates:" >> parameters

echo "Script name and stringency:" >> parameters

#Lagt til i v9:
echo "Total number of reads before trim:"  >> parameters
echo "Total number of reads after trim:" >> parameters
echo "Majority quality:" >> parameters
echo "Minor quality:" >> parameters


paste parameters *.tmp >> ${runname}_summaries.csv    # verdiene og overskriftene limes inn i en og samme fil
cat ${runname}_summaries.csv | rs -c -C -T | awk 'NR == 1; NR > 1 {print $0 | "sort -k1.11n"}' > ${runname}_summaries_ny.csv  # transponerer og sorterer resultatene
rm ${runname}_summaries.csv
mv ${runname}_summaries_ny.csv ${runname}_summaries.csv


find . -type f -name "*.tmp" -exec rm -f {} \;
find . -type f -name "parameters" -exec rm -f {} \; # sletter de midlertidige filene
rm *summary.csv


# Lage samlefasta for run
cd fasta
cat *.fa > ${runname}.fa 
mv ${runname}.fa ${basedir}/${runname}_summaries

cd "${basedir}"

######## DEL 6 Sammenfatte resultater #### SLUTT ######


######## DEL 7 Lage coverage-plot #### START #####
cd "./${runname}_summaries"

#source  activate weeSAM - endret 5. september 2023

base=$(pwd)
mkdir plot
cd bam

# Edit 5. september 2023
for file in $(ls *bam); do weeSAMv1.6 --bam ${file} --html ${file%.sorted.bam}.html; done

for dir in $(ls -d *vbest*results); do cd ${dir}/figures/*figures/ ; test=$(pwd) ; test2=${test##*/}; echo ${test2} og ${test2%%_*}; mv *svg ${test2%%_*}_covplot.svg ; mv ./*svg ${base}/plot ; cd ${base}/bam; done

for dir in $(ls -d *minor*results); 
do cd ${dir}/figures/*figures/ ; test=$(pwd) ; test2=${test##*/}; echo ${test2} og ${test2%%_*}; for file in $(ls *svg); do mv $file ${test2%%_*}_${file%,*}_covplot.svg; done; mv ./*svg ${base}/plot ; cd ${base}/bam; done
rm -r *html_results

conda deactivate 

cd "${basedir}"
######## DEL 7 Lage coverage-plot #### SLUTT #####

######## DEL 8 Sammenfatte GLUE-rapporter inn i summarie #### START #####
basedir=$(pwd)
runname=${basedir##*/}
cd "./${runname}_summaries"

Rscript --vanilla GLUE_json_parser.R ${runname} ${runname}_summaries.csv
tsv=$(echo *glue.tsv)
sed 's/\TOM//g' ${tsv} > ${tsv%%.tsv}_ny.tsv #Fjerner teksten "TOM" som er lagt til i alle cellene for å unngå forskyvning ved tom verdi
mv ${tsv%%.tsv}_ny.tsv ${tsv}

cat ${runname}_summaries.csv | sed 's/\TOM//g' > ${runname}_summaries_ny.csv  #Fjerner teksten "TOM" som er lagt til i alle cellene for å unngå forskyvning ved tom verdi
rm ${runname}_summaries.csv
mv ${runname}_summaries_ny.csv ${runname}_summaries.csv

cd "${basedir}"
######## DEL 8 Sammenfatte GLUE-rapporter inn i summarie #### SLUTTT #####
echo "

Du vil nå bli bedt om å skrive inn passord til maskinen for å initiere automatisk kopiering av summary-mappen til N:
Vent til dette er ferdig før du gjør noe mer! Det tar ikke veldig lang tid.

"

cd /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/HCV/${Aar}/
sudo cp -rf ${basedir}/${runname}_summaries ./

echo "
Takk for at du brukte dette skriptet til å hente ut resultater for ${Agens}"

