process FASTA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}", mode:'copy', pattern:'*.{log,csv}'

    input:
    path metadata

    output:
    path "*raw.csv", emit: metadata_raw
    path "*.log"

    script:
    """
    fasta.R ${metadata}
    """'

}