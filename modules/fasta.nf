process FASTA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}", mode:'copy', pattern:'*.{log,fasta}'

    input:
    path samplesheet
    path metadata_raw
    path oppsett_details_final
    path FHI_fasta_1,   stageAs: 'dir1'
    path FHI_fasta_2,   stageAs: 'dir2'
    path MIK_fasta,     stageAs: 'dir3'
    path Artic_fasta_1, stageAs: 'dir4'
    path Artic_fasta_2, stageAs: 'dir5'
    path Nano_fasta_1,  stageAs: 'dir6'
    path Nano_fasta_2,  stageAs: 'dir7'

    output:
    path "*raw.fasta", emit: fasta_raw
    path "*.log"
    //path "*.txt"
    //path "*.csv"

    script:
    """
    fasta.R \
        ${samplesheet} \
        ${metadata_raw} \
        "dir1" \
        "dir2" \
        "dir3" \
        "dir4" \
        "dir5" \
        "dir6" \
        "dir7" \
        ${oppsett_details_final}
    """
}