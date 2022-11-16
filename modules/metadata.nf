process METADATA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}", mode:'copy', pattern:'*.{log,csv}'

    input:
    path samplesheet
    path BN

    output:
    path "*raw.csv", emit: metadata_raw
    path "*.log"

    script:
    """
    metadata.R ${samplesheet} ${BN}
    """
}
