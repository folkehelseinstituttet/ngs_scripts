process METADATA {

    container 'jonbra/gisaid_sub_dockerfile:2.0'

    publishDir "${params.outdir}/", mode:'copy', pattern:'*.csv'
    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'
    publishDir "${params.outdir}/versions/", mode:'copy', pattern:'*.txt'

    input:
    path BN
    val submitter
    path LW, stageAs: 'LW'
    val min_date

    output:
    tuple path("*raw.csv"), path("*raw.RData"), emit: metadata_raw
    path "*.{log,sh,txt}"

    script:
    """
    metadata.R ${BN} ${submitter} ${LW} ${min_date}

    cp .command.log process_metadata.log
    cp .command.sh process_metadata.sh
    """
}

