#!/usr/bin/env bash

# Maintained by: Jon Bråte (jon.brate@fhi.no)
# Version: dev
# Last updated: 2024.03.14

# The script requires BaseSpace CLI installed (https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview)
# Check if the bs command is available
if ! command -v bs &> /dev/null
then
    echo "BaseSpace CLI could not be found"
    exit 1
fi

# There also has to be a BaseSpace credentials file: $HOME/.basespace/default.cfg
# Check if the file exists
if ! test -f ~/.basespace/default.cfg; then
  echo "BaseSpace credentials file does not exist."
  exit 1
fi

# The script takes a single argument, the name of the Illumina run.
# Check if the argument is entered correctly
if [ $# -eq 0 ]; then
    echo "Did you forget to enter the Run or Agens name?"
    echo "Usage: $0 <Run name> <Agens>"
    exit 1
fi

# Set the variables
Run=$1
Agens=$2

# List Runs on BaseSpace and get the Run id (third column separated by | and whitespaces)
id=$(bs list projects | grep "${Run}" | awk -F '|' '{print $3}' | awk '{$1=$1};1')

# Then download the fastq files
bs download project -i ${id} --extension=fastq.gz -o ${Run}

# Clean up the folder names

RUN_DIR="$(pwd)/${Run}"
# Find only directories in the current directory. Loop through them and rename
# mindepth 1 excludes the RUN_DIR directory. maxdepth 1 includes only the sudirectories of RUN_DIR
find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d '' folder; do
    # Extract the sample number and add Agens name
    new_name="${folder%%-*}-${Agens}"

    # Rename the folder
    mv "$folder" "$new_name"
done

# Move to N:


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

