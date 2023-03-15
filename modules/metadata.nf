process METADATA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}/", mode:'copy', pattern:'*.csv'
    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'
    publishDir "${params.outdir}/versions/", mode:'copy', pattern:'*.txt'

    input:
    path ch_BN, stageAs: 'BN'
    val submitter
    path ch_LW

    output:
    tuple path("*raw.csv"), path("*raw.RData"), emit: metadata_raw
    path "*.{log,sh,txt}"

    script:
    """
    metadata.R ${BN} ${submitter} ${ch_LW}

    cp .command.log process_metadata.log
    cp .command.sh process_metadata.sh
    """
}

