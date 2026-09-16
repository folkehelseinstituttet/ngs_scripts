  ## How to start avian fasta workflow on ngs4 (proxmox-server)
  
  1) Export FASTA-file with avian seqeunces (alle 8 segments if available) at - N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\12-Export\2026 in its own folder. 
  
  2) Log in on ngs4 and naviagte to $HOME, logged in as ngs-user.
	
	Log in to ngs4:
	az ssh arc --subscription "FILL IN" --resource-group "FILL IN" --name "up-ngs-4"
	
	Change user to ngs:
	sudo -u ngs /bin/bash

	Naviagte to $HOME:
	cd $HOME
	
  3) Start script with this command:
	 bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh   -r RUNNAME   -a avian   -s SesXXXX   -y YEAR
	 
	 RUNNAME = the name of the folder with the FASTA-file on N
	 XXXX = the season number; for example 2526
	 YEAR = this indigates which folder on N the results will be saved in (2026, 2025...)
	 
	 Example command:
	 bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh   -r 20260915TEST   -a avian   -s Ses2526   -y 2026

  
  ## What the workflow does

  It analyses existing consensus sequences in FASTA format. It organises records by sample, assesses sequence completeness, generates classifications and
  annotations, and combines results into reports. It does not assemble consensus sequences from raw reads.

  ## Software requirements

  The current wrapper depends on:

  - Bash and flock.
  - Conda, with an environment named NEXTFLOW.
  - Nextflow and Docker.
  - Git, Python 3, and Perl.
  - smbclient and access to the configured network share.
  - Locally available helper scripts and reference resources.

  You can inspect its interface without starting analysis:

  bash /home/rasmuskopperud.riis/Coding/flu-wrappers/avianseq_fasta_wrapper.sh --help

  Current status: shell checks passed, but the complete workflow remains unverified. Version pinning, shared-reference isolation, and upload recovery remain
  unresolved. Validation mode uploads report CSVs—it is not a dry run.

  ## What each module does

  ### Sample organisation

   Module                      Purpose
  ━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   EMIT_FASTA_RECORD           Writes individual sequence records with internal identifiers.
  ──────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   WRITE_ID_MAP                Records the relationship between internal identifiers and original sample names.
  ──────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   REHEADER_TO_UID             Standardises selected sequence headers using internal identifiers.
  ──────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   FASTA_CONFIGURATIONFASTA    Prepares sequence formats for the different analysis tools.
  ──────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   REFERENCE_PROVENANCE        Records reference-file checksums for traceability.

  ### Quality and classification

   Module               Purpose
  ━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   SEGMENTIFENTIFIER    Identifies influenza genome segments.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   SUBTYPEFINDER        Produces subtype assignments and supporting status information.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   COVERAGE             Assesses consensus-sequence completeness; this is different from sequencing read depth.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   GENOTYPING           Produces reference-based genotype assignments.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   NEXTCLADE            Produces clade assignments and sequence-analysis summaries.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   REASSORTMENT         Summarises evidence about differences in segment ancestry.
  ───────────────────  ─────────────────────────────────────────────────────────────────────────────────────────
   GENIN2               Produces an additional genotype assessment.

  ### Biological annotations

   Module                   Purpose
  ━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   AMINOACIDTRANSLATION     Produces protein-sequence representations.
  ───────────────────────  ──────────────────────────────────────────────────────────────────────────────
   MUTATION                 Produces annotations from comparisons with reference sequences.
  ───────────────────────  ──────────────────────────────────────────────────────────────────────────────
   TABLELOOKUP              Adds reference annotations concerning antiviral resistance.
  ───────────────────────  ──────────────────────────────────────────────────────────────────────────────
   TABLELOOKUP_MAMMALIAN    Adds reference annotations concerning mammalian adaptation.
  ───────────────────────  ──────────────────────────────────────────────────────────────────────────────
   FLUMUT                   Produces influenza marker annotations and associated literature information.

  ### Reporting

   Module                  Purpose
  ━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   FLUMUT_CONVERSION       Converts FluMut output into the pipeline’s reporting format.
  ──────────────────────  ──────────────────────────────────────────────────────────────────────────────────────
   SLIM_GENIN2_REPORT      Selects GENIN2 columns used in combined reporting.
  ──────────────────────  ──────────────────────────────────────────────────────────────────────────────────────
   SURVEILLANCE_SUMMARY    Combines quality, classification, and annotation evidence into structured summaries.
  ──────────────────────  ──────────────────────────────────────────────────────────────────────────────────────
   REPORTAVIANFASTA        Builds the combined avian FASTA CSV report.


For detailed  column description look here - https://github.com/RasmusKoRiis/nf-core-fluseq/blob/infrastructure/docs/avian_fasta_report_columns.md
