nextflow.enable.dsl=2

// Define parameters
samplesheet = "$baseDir/Gisaid_sample_sheet.xlsx" // Default samplesheet path. Override with --samplesheet 
BN = "$baseDir/BN.RData"
params.outdir = "Gisaid_files/"

// Include processes
include { METADATA } from './modules/metadata.nf'
include { FASTA } from './modules/fasta.nf'
include { FRAMESHIFT } from './modules/frameshift.nf'
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
    
    METADATA(samplesheet, BN)
    FASTA(samplesheet, METADATA.out.metadata_raw, METADATA.out.oppsett_details_final, FHI_fasta_1, FHI_fasta_2, MIK_fasta, Artic_fasta_1, Artic_fasta_2, Nano_fasta_1, Nano_fasta_2)
    FRAMESHIFT(FASTA.out.fasta_raw)
    CLEAN_UP(METADATA.out.metadata_raw, FASTA.out.fasta_raw, FRAMESHIFT.out.frameshift)
}

