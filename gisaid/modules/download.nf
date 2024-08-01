process DOWNLOAD_FILES {

    container 'jonbra/gisaid_sub_dockerfile:2.0'

    publishDir "${params.outdir}"    , mode:'copy', pattern:'*.{csv,fasta}'
    publishDir "${params.outdir}/log", mode:'copy', pattern:'*.txt'

    output:
    path "*.fasta"       , emit: reference
    path "*genemap.csv"  , emit: genelist
    path "*FSDB*"        , emit: FSDB
    path "*.txt"

    script:
    """
    download_files.R
    """
}