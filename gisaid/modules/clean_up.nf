process CLEAN_UP {

    container 'jonbra/gisaid_sub_dockerfile:2.0'

    publishDir "${params.outdir}"      , mode:'copy', pattern:'*.{csv,fasta}'
    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'

    input:
    tuple path(csv), path(RData)
    path fasta_raw
    path frameshift

    output:
    path "*.fasta", optional:true
    path "*.csv", optional:true
    path "*.{log,sh}"

    def date = new java.util.Date().format( 'yyyy-MM-dd' )

    script:
    """
    clean_up.R \
        $csv \
        $fasta_raw \
        $frameshift

    # Copy the frameshift results
    cp $frameshift ${date}_frameshift_results.csv

    cp .command.log clean_up.log
    cp .command.sh clean_up.sh
    """
}
