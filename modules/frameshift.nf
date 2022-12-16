process FRAMESHIFT {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    // Change this as needed by --cpus
    cpus 12

    publishDir "${params.outdir}"    , mode:'copy', pattern:'*.xlsx'
    publishDir "${params.outdir}/log", mode:'copy', pattern:'*.{log,txt}'

    input:
    path fasta_raw

    output:
    path "*.xlsx", emit: frameshift
    path "*.log"
    path "*.txt"

    script:
    """
    CSAK_Frameshift_Finder.R \
        $task.cpus \
        \$PWD \
        $fasta_raw
    """
}