process FASTA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}", mode:'copy', pattern:'*.{log,fasta}'

    input:
    path samplesheet
    path metadata_raw
    path oppsett_details_final

    output:
    path "*raw.fasta", emit: fasta_raw
    path "*.log"

    script:
    """
    fasta.R \
        ${samplesheet} \
        ${metadata_raw} \
        ${params.FHI_fasta_1} \
        ${params.FHI_fasta_2} \
        ${params.MIK_fasta} \
        ${params.Artic_fasta_1} \
        ${params.Artic_fasta_2} \
        ${params.Nano_files_1} \
        ${params.Nano_files_2} \
        ${oppsett_details_final}
    """'

}