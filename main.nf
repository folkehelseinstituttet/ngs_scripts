nextflow.enable.dsl=2

// Define parameters
samplesheet = "$baseDir/Gisaid_sample_sheet.xlsx" // Default samplesheet path. Override with --samplesheet 
BN = "$baseDir/BN.RData"
params.outdir = "Gisaid_files/"

// Include processes
include { METADATA } from './modules/metadata.nf'
include { FASTA } from './modules/fasta.nf'

// Workflow
workflow {
    METADATA(samplesheet, BN)
    FASTA(samplesheet, METADATA.out.metadata_raw, METADATA.out.oppsett_details_final)
}

