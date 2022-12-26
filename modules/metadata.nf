process METADATA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}/log", mode:'copy', pattern:'*.{log,txt}'

    input:
    path samplesheet
    path BN

    output:
    path "*raw.csv", emit: metadata_raw
    path "*.RData" , emit: oppsett_details_final
    path "*.log"
    path "*.txt"

    script:
    """
    metadata.R ${samplesheet} ${BN}
    """
}

