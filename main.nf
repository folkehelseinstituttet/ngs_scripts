nextflow.enable.dsl=2

// Define parameters
samplesheet = "$baseDir/Gisaid_sample_sheet.xlsx" // Default samplesheet path. Override with --samplesheet 
BN = "$baseDir/BN.RData"
params.outdir = "Gisaid_files/"

// Hardcode parameters for fasta.nf - should perhaps be put in a credentials/config file later
params.FHI_fasta_1 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2021/"
params.FHI_fasta_2 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2022/"
params.MIK_fasta = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_MIK"
params.Artic_fasta_1 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2021"
params.Artic_fasta_2 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2022"
params.Nano_files_1 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2021"
params.Nano_files_2 = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2022"

// Include processes
include { METADATA } from './modules/metadata.nf'
include { FASTA } from './modules/fasta.nf'

// Workflow
workflow {
    METADATA(samplesheet, BN)
    FASTA(samplesheet, METADATA.out.metadata_raw, METADATA.out.oppsett_details_final)
}

