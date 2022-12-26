process FRAMESHIFT {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    input:
    path fasta
    path reference
    path genelist
    path FSDB

    output:
    path 'frameshift.csv'

    script:
    """
    frameshift_finder.R \
        $reference \
        $genelist \
        $FSDB \
        $fasta \
        \$PWD
    """
}

