process FASTA {

    container 'jonbra/gisaid_sub_dockerfile:1.0'

    publishDir "${params.outdir}/logs/", mode:'copy', pattern:'*.{log,sh}'

    input:
    tuple path(csv), path(RData)
    path FHI_fasta_1,   stageAs: 'dir1'
    path FHI_fasta_2,   stageAs: 'dir2'
    path FHI_fasta_3,   stageAs: 'dir3'
    path MIK_fasta,     stageAs: 'dir4'
    path Artic_fasta_1, stageAs: 'dir5'
    path Artic_fasta_2, stageAs: 'dir6'
    path Nano_fasta_1,  stageAs: 'dir7'
    path Nano_fasta_2,  stageAs: 'dir8'
    path Nano_fasta_3,  stageAs: 'dir9'

    output:
    path "*raw.fasta", emit: fasta_raw
    path "*.{log,sh}"

    script:
    """
    fasta.R \
        ${csv} \
        "dir1" \
        "dir2" \
        "dir3" \
        "dir4" \
        "dir5" \
        "dir6" \
        "dir7" \
        "dir8" \
        "dir9"

    cp .command.log process_find_fasta.log
    cp .command.sh process_find_fasta.sh
    """
}

