###########################################################################
# ENA Metadata Draft Generator
#
# This script scans a run's FASTQ directory for paired files ("GA" or "ME" and "R1"/"R2" or "1P"/"2P"),
# and generates a draft ENA metadata Excel file with prefilled and placeholder fields.
#
# Usage (from command line):
#   Rscript ENA_metadata_draft_generator.R <year> <run>
# Example:
#   Rscript ENA_metadata_draft_generator.R 2025 NGS_SEQ-20251205-01
#
# The output file will be written to:
#   N:/NGS/4-SekvenseringsResultater/ENA-metadata/<run>_ENA_metadata.xlsx
#
# The script can also be run interactively by setting the 'year' and 'run' variables manually.
###########################################################################

library(openxlsx)
library(stringr)

# Accept year and run as input parameters (for Rscript), or use defaults for interactive use
args <- commandArgs(trailingOnly = TRUE)

if (length(args) >= 2) {
  year <- as.integer(args[1])
  run <- args[2]
}

# ---- PATHS ----
fastq_dir <- file.path("N:/NGS/4-SekvenseringsResultater", paste0(year, "-Resultater"), run, "fastq")
output_xlsx <- file.path("N:/NGS/4-SekvenseringsResultater/ENA-metadata", paste0(run, "_ENA_metadata.xlsx"))

# ---- FIND FASTQ FILES ----
fastq_files <- list.files(fastq_dir, pattern = "(GA|ME).*.fastq.gz$", full.names = FALSE)

if (length(fastq_files) == 0) {
  stop("No matching FASTQ files found.")
}


# ---- PAIR FILES ----
 # Support paired files with _R1, _R2, _1P, or _2P followed by _ or . or end of string
base_names <- str_replace(fastq_files, "(_R1|_R2|_1P|_2P)(_|\\.|$).*", "")
pair_df <- data.frame(
  base = base_names,
  file = fastq_files,
  is_fwd = grepl("(_R1|_1P)", fastq_files),
  is_rev = grepl("(_R2|_2P)", fastq_files),
  stringsAsFactors = FALSE
)

# Only keep base names that have both a forward and reverse file
paired_basenames <- intersect(pair_df$base[pair_df$is_fwd], pair_df$base[pair_df$is_rev])

rows <- lapply(paired_basenames, function(b) {
  fwd <- pair_df$file[pair_df$base == b & pair_df$is_fwd]
  rev <- pair_df$file[pair_df$base == b & pair_df$is_rev]
  data.frame(
    sample_alias = "FILL_IN",
    study_accession = "FILL_IN",
    instrument_model = "FILL_IN",
    library_name = "FILL_IN",
    library_source = "GENOMIC",
    library_selection = "other",
    library_strategy = "WGS",
    library_layout = "paired",
    forward_file_name = fwd,
    forward_file_md5 = "FILL_IN",
    reverse_file_name = rev,
    reverse_file_md5 = "FILL_IN",
    library_construction_protocol = "FILL_IN",
    design_description = "FILL_IN",
    insert_size = "FILL_IN",
    stringsAsFactors = FALSE
  )
})

metadata_df <- do.call(rbind, rows)

# ---- WRITE XLSX ----
write.xlsx(metadata_df, output_xlsx, rowNames = FALSE)

cat("Draft metadata file written to:", output_xlsx, "\n")
