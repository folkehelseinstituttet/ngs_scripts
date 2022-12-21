nextflow.enable.dsl=2

// Define parameters
samplesheet = "$baseDir/Gisaid_sample_sheet.xlsx" // Default samplesheet path. Override with --samplesheet 
BN = "$baseDir/BN.RData"
params.outdir = "Gisaid_files/"
reference = "$baseDir/data/MN908947.3.fasta"
genelist = "$baseDir/data/genemap.csv"
FSDB = "$baseDir/data/FSDB.csv"


// Include processes
//include { DOWNLOAD_FILES } './modules/download.nf'
include { METADATA } from './modules/metadata.nf'
include { FASTA } from './modules/fasta.nf'
//include { FRAMESHIFT } from './modules/frameshift.nf'
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

    //reference = Channel.fromPath( params.reference )
    //genelist = Channel.fromPath( params.genelist )
    //FSDB = Channel.fromPath( params.FSDB ) 
    
    //METADATA(samplesheet, BN)
    //FASTA(samplesheet, METADATA.out.metadata_raw, METADATA.out.oppsett_details_final, FHI_fasta_1, FHI_fasta_2, MIK_fasta, Artic_fasta_1, Artic_fasta_2, Nano_fasta_1, Nano_fasta_2)
    
    // Split the multifasta from the FASTA process into single fasta files
    //NB: Denne fungerer om jeg setter inn en path til en fasta fil.
    // Men får problemer med å bruke FASTA.out..
    // Jeg kan prøve å bytte ut "emit" i fasta.nf med "into".
    Channel
        .fromPath("test.fa")
        .splitFasta(by: 1, file: true)
        .set { ch_fasta }
    
    // Run the FRAMESHIFT process on each fasta file
    ch_clean = FRAMESHIFT_DEV(ch_fasta, reference, genelist, FSDB)
    
    //FRAMESHIFT(FASTA.out.fasta_raw)

    // Collect all the FrameShift results into a file called collected_frameshift.csv
    ch_collect = ch_clean
       .collectFile(name: "collected_frameshift.csv", newLine: false)
    
    //CLEAN_UP(METADATA.out.metadata_raw, FASTA.out.fasta_raw, ch_collect)
    //CLEAN_UP(METADATA.out.metadata_raw, FASTA.out.fasta_raw, FRAMESHIFT.out.frameshift)
    
}
