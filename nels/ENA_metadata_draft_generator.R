###########################################################################
# ENA Metadata Draft Generator
#
# This script scans a run's FASTQ directory for paired files ("GA" or "ME" and "R1"/"R2" or "1P"/"2P"),
# and generates a draft ENA metadata Excel file with FHI_ID and file names.
#
# Usage (from command line):
#   Rscript ENA_metadata_draft_generator.R <year> <run>
# Example:
#   Rscript ENA_metadata_draft_generator.R 2025 NGS_SEQ-20251205-01
#
# The output file will be written to:
#   C:\Users\<username>\<run>_ENA_metadata.xlsx
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
# Prefer TOPresults/fastq if present, otherwise fall back to run/fastq.
fastq_dir_top <- file.path("N:/NGS/4-SekvenseringsResultater", paste0(year, "-Resultater"), run, "TOPresults", "fastq")
fastq_dir_plain <- file.path("N:/NGS/4-SekvenseringsResultater", paste0(year, "-Resultater"), run, "fastq")

if (dir.exists(fastq_dir_top)) {
  fastq_dir <- fastq_dir_top
} else if (dir.exists(fastq_dir_plain)) {
  fastq_dir <- fastq_dir_plain
} else {
  # Try case-insensitive match for any directory named like 'topresults' under the run folder
  run_dir <- file.path("N:/NGS/4-SekvenseringsResultater", paste0(year, "-Resultater"), run)
  if (dir.exists(run_dir)) {
    candidates <- list.dirs(run_dir, full.names = TRUE, recursive = FALSE)
    tr_idx <- grep("topresults", basename(candidates), ignore.case = TRUE)
    if (length(tr_idx) > 0) {
      candidate_top <- file.path(candidates[tr_idx[1]], "fastq")
      if (dir.exists(candidate_top)) {
        fastq_dir <- candidate_top
      } else {
        stop("No TOPresults/fastq or run/fastq directory found under: ", run_dir)
      }
    } else {
      stop("No TOPresults/fastq or run/fastq directory found under: ", run_dir)
    }
  } else {
    stop("Run directory does not exist: ", run_dir)
  }
}

output_xlsx <- file.path(Sys.getenv("USERPROFILE"), paste0(run, "TEMP_ENA_metadata.xlsx"))

# ---- FIND FASTQ FILES ----
# Only match files with -GA- or -ME- (not MK files that happen to contain ME in sample ID)
fastq_files <- list.files(fastq_dir, pattern = "-(GA|ME)-.*\\.fastq\\.gz$", full.names = FALSE)

if (length(fastq_files) == 0) {
  stop("No matching FASTQ files found.")
}

# ---- EXTRACT FHI_ID ----
# FHI_ID pattern: (GA|ME)-<string>_merged  e.g. "GA-25GB003157" from "2653253-GA-25GB003157_merged_1P.fastq.gz"
extract_fhi_id <- function(filename) {
  match <- str_extract(filename, "(GA|ME)-[^_]+(?=_merged)")
  return(match)
}

# ---- PAIR FILES ----
# Support paired files with _R1, _R2, _1P, or _2P followed by _ or . or end of string
pair_df <- data.frame(
  file = fastq_files,
  fhi_id = sapply(fastq_files, extract_fhi_id, USE.NAMES = FALSE),
  is_fwd = grepl("(_R1|_1P)", fastq_files),
  is_rev = grepl("(_R2|_2P)", fastq_files),
  stringsAsFactors = FALSE
)

# Check for files where FHI_ID could not be extracted
missing_id <- pair_df$file[is.na(pair_df$fhi_id)]
if (length(missing_id) > 0) {
  warning("Could not extract FHI_ID from the following files:\n  ", paste(missing_id, collapse = "\n  "))
}

# Remove files with missing FHI_ID
pair_df <- pair_df[!is.na(pair_df$fhi_id), ]

# Only keep FHI_IDs that have both a forward and reverse file
paired_ids <- intersect(pair_df$fhi_id[pair_df$is_fwd], pair_df$fhi_id[pair_df$is_rev])

# Check for unpaired files
unpaired_fwd <- setdiff(pair_df$fhi_id[pair_df$is_fwd], paired_ids)
unpaired_rev <- setdiff(pair_df$fhi_id[pair_df$is_rev], paired_ids)
if (length(unpaired_fwd) > 0) {
  warning("Forward files without matching reverse:\n  ", paste(unpaired_fwd, collapse = "\n  "))
}
if (length(unpaired_rev) > 0) {
  warning("Reverse files without matching forward:\n  ", paste(unpaired_rev, collapse = "\n  "))
}

if (length(paired_ids) == 0) {
  stop("No valid paired FASTQ files found.")
}

rows <- lapply(paired_ids, function(id) {
  fwd <- pair_df$file[pair_df$fhi_id == id & pair_df$is_fwd]
  rev <- pair_df$file[pair_df$fhi_id == id & pair_df$is_rev]
  fwd_id <- extract_fhi_id(fwd)
  rev_id <- extract_fhi_id(rev)
  
  # Validate that FHI_ID matches between forward and reverse

if (fwd_id != rev_id) {
    warning("FHI_ID mismatch for pair: ", fwd, " (", fwd_id, ") vs ", rev, " (", rev_id, ")")
  }
  
  data.frame(
    FHI_ID = id,
    forward_file_name = fwd,
    reverse_file_name = rev,
    stringsAsFactors = FALSE
  )
})

metadata_df <- do.call(rbind, rows)

cat("Found", nrow(metadata_df), "valid paired samples.\n")

# ---- WRITE XLSX ----
write.xlsx(metadata_df, output_xlsx, rowNames = FALSE)

cat("Draft metadata file written to:", output_xlsx, "\n")
