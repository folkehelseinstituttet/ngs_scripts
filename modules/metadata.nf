process METADATA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}/", mode:'copy', pattern:'*.xlsx'
    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'
    publishDir "${params.outdir}/versions/", mode:'copy', pattern:'*.txt'

    input:
    path samplesheet
    path BN

    output:
    path "*raw.csv", emit: metadata_raw
    path "*.RData" , emit: oppsett_details_final
    path "*.{log,sh,txt}"
    path "${samplesheet}"

    script:
    """
    metadata.R ${samplesheet} ${BN}

    cp .command.log process_metadata.log
    cp .command.sh process_metadata.sh
    """
}

