#!/usr/bin/env bash

# Usage
# wrapper.sh <input fasta>

# Check that GenoFlu is installed and available
if ! command -v genoflu.py &> /dev/null
then
    echo "GenoFlu is not available"
    exit 1
fi

# Check that Rscript is installed and available
if ! command -v Rscript &> /dev/null
then
    echo "Rscript is not available"
    exit 1
fi

# Then split the multifasta into individual fastas per virus genome
Rscript split_gisaid_multifasta.R $1 fasta

# Then run the genotyping
cd fasta
for i in *.fasta
do
genoflu.py -f $i
done

# Collect the results
cd ..
Rscript collect_genoflu_results.R
