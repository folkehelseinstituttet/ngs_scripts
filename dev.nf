nextflow.enable.dsl=2

// Define parameters
samplesheet = "$baseDir/Gisaid_sample_sheet.xlsx" // Default samplesheet path. Override with --samplesheet 
BN = "$baseDir/BN.RData"
params.outdir = "Gisaid_files/"

// Include processes
include { DOWNLOAD_FILES } './modules/download.nf'
include { METADATA } from './modules/metadata.nf'
include { FASTA } from './modules/fasta.nf'
include { FRAMESHIFT_DEV } from './modules/frameshift_dev.nf'
include { CLEAN_UP } from './modules/clean_up.nf'

// Workflow
workflow {

    FHI_fasta_1 = Channel.fromPath( params.FHI_fasta_1 )
    FHI_fasta_2 = Channel.fromPath( params.FHI_fasta_2 )
    MIK_fasta = Channel.fromPath( params.MIK_fasta )
    Artic_fasta_1 = Channel.fromPath( params.Artic_fasta_1 )
    Artic_fasta_2 = Channel.fromPath( params.Artic_fasta_2 )
    Nano_fasta_1 = Channel.fromPath( params.Nano_fasta_1 )
    Nano_fasta_2 = Channel.fromPath( params.Nano_fasta_2 )
    
    DOWNLOAD_FILES()
    METADATA(samplesheet, BN)
    FASTA(samplesheet, METADATA.out.metadata_raw, METADATA.out.oppsett_details_final, FHI_fasta_1, FHI_fasta_2, MIK_fasta, Artic_fasta_1, Artic_fasta_2, Nano_fasta_1, Nano_fasta_2)
    
    // Split the multifasta from the FASTA process into single fasta files
    Channel
        .fromPath(FASTA.out.fasta_raw)
        .splitFasta(by: 1, file: true)
        .set { ch_fasta }
    
    // Run the FRAMESHIFT process on each fasta file
    ch_clean = FRAMESHIFT_DEV(ch_fasta, DOWNLOAD_FILES.out.reference, DOWNLOAD_FILES.out.genelist, DOWNLOAD_FILES.out.FSDB)

    // Collect all the FrameShift results
    // Need to save a simple tsv/csv file with no header and one line per fasta sequence
    // This can be concatenated.
    ch_collect = ch_clean.collectFile(name: "Frameshift.csv", newLine: true)
    
    CLEAN_UP(METADATA.out.metadata_raw, FASTA.out.fasta_raw, ch_collect)
}

