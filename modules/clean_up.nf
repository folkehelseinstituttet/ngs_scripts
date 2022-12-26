process CLEAN_UP {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}"    , mode:'copy', pattern:'*.{csv,fasta}'
    publishDir "${params.outdir}/log", mode:'copy', pattern:'*.{log,txt}'

    input:
    path metadata_raw
    path fasta_raw
    path frameshift

    output:
    path "*.fasta"
    path "*.csv"
    path "*.log"
    path "*.txt"

    script:
    """
    clean_up.R \
        $metadata_raw \
        $fasta_raw \
        $frameshift
    """
}
