#!/usr/bin/env bash

# Usage
wrapper.sh <input fasta>

# First install miniconda if it's not already installed
if ! command -v conda &> /dev/null
then
    echo "Conda not installed. Installing. Press "Y" to any prompts"
    mkdir -p ~/miniconda3
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
    bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
    rm -rf ~/miniconda3/miniconda.sh
fi

# Then install R if not installed
if ! command -v Rscript &> /dev/null
then
    conda install conda-forge::r-base
fi

# Then install GenoFlu
conda install GenoFlU -c conda-forge -c bioconda

# Then split the multifasta into individual fastas per virus genome
Rscript

# Then run the genotyping
for i in fasta/*.fasta
do
genoflu.py -f $i
done
