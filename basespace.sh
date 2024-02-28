# Ved restart av PC må det mountes på nytt til Felles før skriptet startes
# Kan startes fra hvor som helst på linux-maskin


# Kobler fra og til BaseSpace, laster ned gjeldene Run, putter i mapper og kopierer til felles. 



cd ~
homedir=$(pwd)
linux=${homedir##*home/}

DIRECTORY=/media/$linux/data
if [[ -d "$DIRECTORY" ]]
then
    echo "$DIRECTORY exists on your filesystem."
else 
    DIRECTORY=/media/data
fi 	
echo "$DIRECTORY is now your DIRECTORY"

XXX=${1}	
Run=NGS_SEQ-${XXX} 	

Aar=$([ "$OSTYPE" = linux-gnu ] && date --date="4 days ago" +"%Y" || date -v-4d +"%Y")   	#henter ut året for 4 dager siden  (ved årsskiftet vil et run kunne tilhøre året før)
DirFelles=Felles		# denne er avhengig av maskin (for kopiereing til felles)

cd /home/${linux}/Desktop
basemount NGS_basespace --unmount
basemount NGS_basespace

if [[ ${1} ]]; then  
    echo "       

                    #############################
                  ##                             ##
                ##                                ##
               ##   Du laster nå ned fastq         ##
               ##          fra BaseSpace  	     ##
               ##                                  ##
                ##                                ##
                  ##                             ##  
                    #############################
                    "
else
    echo "
############################################################################
                    NB! NB!  NB!  NB!  NB!  NB!  NB!    
            
            Du har glemt å skrive inn et run-nr i terminalen

#############################################################################  

"
fi



mkdir $DIRECTORY/${Run}
cd /home/${linux}/Desktop/NGS_basespace/Projects/${Run}/Samples 

find . -name "*.fastq.gz" -type f -exec cp {} $DIRECTORY/${Run}/ \; 

cd $DIRECTORY/${Run}/

for x in $(ls -1); do mv $x ${x#*${XXX}}; done
for f in *.fastq.gz ; do mkdir ./${f%%_*}/; done
for f in *.fastq.gz ; do mv ${f} ./${f%%_*}/; done



echo "

Du vil nå bli bedt om å skrive inn passord til maskinen for å initiere automatisk kopiering av Fastq-filene til N:
Vent til dette er ferdig før du gjør noe mer! Det tar ikke veldig lang tid.

"

# Kopiere fastq-filer til Felles
cd /mnt/N/NGS/3-Sekvenseringsbiblioteker/${Aar}/Illumina_Run/${Run}*	
sudo cp -rf $DIRECTORY/${Run}/ ./
cp *.xlsx $DIRECTORY/${Run}*/


echo "Du kan nå lukke terminalvinduet og sette på neste skript."

