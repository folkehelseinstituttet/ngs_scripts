process FRAMESHIFT {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    //publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'

    input:
    path fasta
    path reference
    path genelist
    path FSDB

    output:
    path('frameshift.csv')

    script:
    """
    frameshift_finder.R \
        $reference \
        $genelist \
        $FSDB \
        $fasta \
        \$PWD

    #cp .command.log process_frameshift.log
    #cp .command.sh process_frameshift.sh
    """
}

