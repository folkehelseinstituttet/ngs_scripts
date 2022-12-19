process FRAMESHIFT_DEV {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    //publishDir "${params.outdir}/log", mode:'copy', pattern:'*.{log,txt}'

    input:
    path fasta
    path reference
    path genelist
    path FSDB

    output:
    path 'frameshift.csv'
    //path "*.log"
    //path "*.txt"

    script:
    """
    #cat $fasta > frameshift.csv
    frameshift_finder.R \
        $reference \
        $genelist \
        $FSDB \
        $fasta \
        \$PWD
    """
}

