#!/usr/bin/env bash

# Check if conda Illumina environment exists, if not create it
find_in_conda_env(){
    conda env list | grep "Illumina" >/dev/null 2>/dev/null
}

if find_in_conda_env "Illumina"
then
   echo "Conda environment already created"
else
   echo "Creating conda environment"
   conda env create -f conda_Illumina_env.yml 
fi


