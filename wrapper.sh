#!/usr/bin/env bash

# Check if conda Illumina environment exists, if not create it
find_in_conda_env(){
    conda env list | grep "Illumina" >/dev/null 2>/dev/null
}

if find_in_conda_env "Illumina"
then
   echo "Conda environment already created"
   source activate /home/ngs4/miniconda3/envs/Illumina
else
   echo "Creating conda environment"
   conda env create -f conda_Illumina_env.yml 
   source activate /home/ngs4/miniconda3/envs/Illumina
fi


# Start script, assuming you are in a Run folder with subfolders for each samples that contain fastq files.
../HCVskript.v9.1.sh

# Copy results back to N:
#cd /mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/HCV/${Aar}/
#sudo cp -rf ${basedir}/${runname}_summaries ./
