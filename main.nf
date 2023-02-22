nextflow.enable.dsl=2

// Include processes
include { METADATA   } from './modules/metadata.nf'
include { FASTA      } from './modules/fasta.nf'
include { FRAMESHIFT } from './modules/frameshift.nf'
include { CLEAN_UP   } from './modules/clean_up.nf'

// Workflow
workflow {

    //
    // Create the initial metadata file
    METADATA(params.BN, params.submitter)
    
    //
    // Find and rename fasta files
    // Paths to search folders are converted to channels for input into the process

    ch_FHI_fasta_1   = Channel.fromPath( params.FHI_fasta_1 )
    ch_FHI_fasta_2   = Channel.fromPath( params.FHI_fasta_2 )
    ch_FHI_fasta_3   = Channel.fromPath( params.FHI_fasta_3 )
    ch_MIK_fasta     = Channel.fromPath( params.MIK_fasta )
    ch_Artic_fasta_1 = Channel.fromPath( params.Artic_fasta_1 )
    ch_Artic_fasta_2 = Channel.fromPath( params.Artic_fasta_2 )
    ch_Nano_fasta_1  = Channel.fromPath( params.Nano_fasta_1 )
    ch_Nano_fasta_2  = Channel.fromPath( params.Nano_fasta_2 )
    ch_Nano_fasta_3  = Channel.fromPath( params.Nano_fasta_3 )
    
    FASTA(METADATA.out.metadata_raw, 
          ch_FHI_fasta_1, 
          ch_FHI_fasta_2, 
          ch_FHI_fasta_3, 
          ch_MIK_fasta, 
          ch_Artic_fasta_1, 
          ch_Artic_fasta_2, 
          ch_Nano_fasta_1, 
          ch_Nano_fasta_2,
          ch_Nano_fasta_3)
    
    //
    // Run frameshift analysis
    // Split the multifasta from the FASTA process into single fasta files
    FASTA.out.fasta_raw
        .splitFasta(by: 1, file: true)
        .set { ch_fasta }
    
    // Run the FRAMESHIFT process on each fasta file
    ch_clean = FRAMESHIFT(ch_fasta, params.reference, params.genelist, params.FSDB)

    // Collect all the FrameShift results into a file called collected_frameshift.csv
    ch_collect = ch_clean
       .collectFile(name: "collected_frameshift.csv", newLine: false)
    
    //
    // Create final metadata and fasta files
    //
    CLEAN_UP(METADATA.out.metadata_raw, FASTA.out.fasta_raw, ch_collect)
}
