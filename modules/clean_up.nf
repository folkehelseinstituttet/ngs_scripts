process CLEAN_UP {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}"    , mode:'copy', pattern:'*.{csv,fasta}'
    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'

    input:
    tuple path(csv), path(RData)
    path fasta_raw
    path frameshift

    output:
    path "*.fasta"
    path "*.csv"
    path "*.{log,sh}"

    script:
    """
    clean_up.R \
        $csv \
        $fasta_raw \
        $frameshift

    cp .command.log clean_up.log
    cp .command.sh clean_up.sh
    """
}
