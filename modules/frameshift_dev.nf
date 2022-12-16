process FRAMESHIFT_DEV {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}"    , mode:'copy', pattern:'*.csv'
    publishDir "${params.outdir}/log", mode:'copy', pattern:'*.{log,txt}'

    input:
    path fasta
    path reference
    path genelist
    path FSDB

    output:
    path "*.csv", emit: frameshift
    //path "*.log"
    //path "*.txt"

    script:
    """
    CSAK_Frameshift_Finder.R \
        $reference \
        $genelist \
        $FSDB \
        $fasta \
        \$PWD
    """
}