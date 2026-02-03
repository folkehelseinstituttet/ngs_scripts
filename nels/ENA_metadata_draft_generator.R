###########################################################################
# ENA Metadata Draft Generator
#
# Purpose:
# - Identify paired FASTQ files (GA / ME; R1/R2 or 1P/2P)
# - Derive correct FHI_ID 
# - Join authoritative lab metadata from GbMetaFile.csv
# - Produce ENA-ready metadata (XLSX + TSV)
###########################################################################

suppressPackageStartupMessages({
  library(openxlsx)
  library(stringr)
})

# Accept year and run as input parameters (for Rscript), or use defaults for interactive use
args <- commandArgs(trailingOnly = TRUE)

if (length(args) >= 2) {
  year <- as.integer(args[1])
  run <- args[2]
}

# ------------------------------------------------------------------------
# PATHS
# ------------------------------------------------------------------------

base_dir <- file.path(
  "N:/NGS/4-SekvenseringsResultater",
  paste0(year, "-Resultater"),
  run
)


# Prefer TOPresults/fastq if present, otherwise fall back to run/fastq.
fastq_dir_candidates <- c(
  file.path(base_dir, "TOPresults", "fastq"),
  file.path(base_dir, "fastq")
)

fastq_dir <- fastq_dir_candidates[dir.exists(fastq_dir_candidates)][1]

if (is.na(fastq_dir)) {
  stop("No FASTQ directory found under: ", base_dir)
}

meta_csv <- "V:/Prod/FromSecure/Meta/GbMetaFile.csv"

output_xlsx <- file.path(
  Sys.getenv("USERPROFILE"),
  paste0(run, "_ENA_metadata.xlsx")
)

output_tsv <- file.path(
  Sys.getenv("USERPROFILE"),
  paste0(run, "_ENA_upload.tsv")
)

# ------------------------------------------------------------------------
# FASTQ DISCOVERY
# ------------------------------------------------------------------------

# Only match files with -GA- or -MK- followed by the standard Reflab ID format (e.g., 26GB000197, 26ME000001)
fastq_files <- list.files(
  fastq_dir,
  pattern = "-(GA|MK)-[0-9]{2}(GB|ME)[0-9]{6}.*\\.fastq\\.gz$",
  full.names = FALSE
)

if (length(fastq_files) == 0) {
  stop("No GA / ME FASTQ files found.")
}

# ------------------------------------------------------------------------
# FHI_ID EXTRACTION
# ------------------------------------------------------------------------
# Extract ONLY the Reflab-style ID: 25GB003157, 26GB000339, 26ME000001, etc.
extract_fhi_id <- function(x) {
  str_extract(x, "(?<=-(GA|ME|MK)-)[0-9]{2}(GB|ME)[0-9]{6}")
}

pair_df <- data.frame(
  file   = fastq_files,
  FHI_ID = extract_fhi_id(fastq_files),
  direction = ifelse(
    grepl("(_R1|_1P)", fastq_files), "forward",
    ifelse(grepl("(_R2|_2P)", fastq_files), "reverse", NA)
  ),
  stringsAsFactors = FALSE
)

if (any(is.na(pair_df$FHI_ID))) {
  stop(
    "Failed to extract FHI_ID from:\n",
    paste(pair_df$file[is.na(pair_df$FHI_ID)], collapse = "\n")
  )
}

# ------------------------------------------------------------------------
# PAIR VALIDATION
# ------------------------------------------------------------------------

paired_ids <- intersect(
  pair_df$FHI_ID[pair_df$direction == "forward"],
  pair_df$FHI_ID[pair_df$direction == "reverse"]
)

if (length(paired_ids) == 0) {
  stop("No valid paired FASTQ files found.")
}

rows <- lapply(paired_ids, function(id) {
  data.frame(
    FHI_ID = id,
    forward_file_name = pair_df$file[pair_df$FHI_ID == id & pair_df$direction == "forward"],
    reverse_file_name = pair_df$file[pair_df$FHI_ID == id & pair_df$direction == "reverse"],
    stringsAsFactors = FALSE
  )
})

metadata_df <- do.call(rbind, rows)

cat("Paired samples:", nrow(metadata_df), "\n")

# ------------------------------------------------------------------------
# READ GbMetaFile.csv
# ------------------------------------------------------------------------

gb_meta <- read.csv(
  meta_csv,
  sep = ";",
  stringsAsFactors = FALSE,
  na.strings = c("", "NA")
)

colnames(gb_meta) <- make.names(colnames(gb_meta))

# Only GAS / MK are relevant
gb_meta <- gb_meta[gb_meta$Agens %in% c("GAS", "MK"), ]

gb_meta$FHI_ID <- gb_meta$Reflab.ID

# ------------------------------------------------------------------------
# JOIN FASTQ + METADATA
# ------------------------------------------------------------------------

metadata_df <- merge(
  metadata_df,
  gb_meta,
  by = "FHI_ID",
  all.x = TRUE
)

missing_meta <- metadata_df$FHI_ID[is.na(metadata_df$Prøvetatt.dato)]

if (length(missing_meta) > 0) {
  cat(
    "WARNING: Missing metadata in GbMetaFile.csv for the following samples (will be excluded):\n",
    paste(missing_meta, collapse = "\n"),
    "\n\n"
  )
  # Filter out samples with missing metadata
  metadata_df <- metadata_df[!is.na(metadata_df$Prøvetatt.dato), ]
}

# ------------------------------------------------------------------------
# ISOLATION SOURCE LOOKUP
# ------------------------------------------------------------------------

materiale_lookup <- c(
  "A"   = "Abscess",
  "AP"  = "Aspirate",
  "B"   = "Blood",
  "BI"  = "Biopsy",
  "COA" = "Corneal scraping",
  "DV"  = "Dialysis fluid"
)

metadata_df$isolation_source <- materiale_lookup[metadata_df$Materiale]
metadata_df$isolation_source[is.na(metadata_df$isolation_source)] <- "not provided"


# ------------------------------------------------------------------------
# ENA REQUIRED / STANDARD FIELDS
# ------------------------------------------------------------------------

metadata_df$geographic_location            <- "Norway"
metadata_df$host_health_state              <- "not provided"
metadata_df$host_scientific_name           <- "Homo sapiens"
metadata_df$instrument_model               <- "NextSeq 1000"
metadata_df$library_source                 <- "GENOMIC"
metadata_df$library_selection              <- "RANDOM"
metadata_df$library_strategy               <- "WGS"
metadata_df$library_layout                 <- "PAIRED"
metadata_df$library_construction_protocol  <- "xGen DNA library prep IDT"
metadata_df$insert_size                    <- "550"
metadata_df$isolate                        <- metadata_df$FHI_ID
metadata_df$collection_date                <- substr(metadata_df$Prøvetatt.dato, 1, 4)


# ------------------------------------------------------------------------
# Additional ENA study/species fields
# Populate based on `Agens` from `GbMetaFile.csv` (GAS or MK)
metadata_df[["Species"]] <- ifelse(
  metadata_df$Agens == "GAS",
  "Streptococcus pyogenes",
  ifelse(metadata_df$Agens == "MK", "Neisseria meningitidis", NA)
)

metadata_df[["Tax ID"]] <- ifelse(
  metadata_df$Agens == "GAS",
  "1314",
  ifelse(metadata_df$Agens == "MK", "487", NA)
)

metadata_df[["Study Name"]] <- ifelse(
  metadata_df$Agens == "GAS",
  "NIPH - Streptococcus pyogenes norwegian isolates",
  ifelse(metadata_df$Agens == "MK", "NIPH - Neisseria meningitidis norwegian isolates", NA)
)

metadata_df[["Study Title"]] <- metadata_df[["Study Name"]]

abstract_text <- paste(
  "The Norwegian Institute of Public Health (NIPH) is national reference laboratory",
  "for a number of human pathogens. Next generation sequencing is used routinely to",
  "characterize the organisms causing disease in the Norwegian population. Broad",
  "availability of these data is central for public health action.")

metadata_df[["Abstract"]] <- ifelse(
  metadata_df$Agens %in% c("GAS", "MK"),
  abstract_text,
  NA
)

# Add sample_alias: prefix FHI_ID with "NIPH_"
metadata_df[["sample_alias"]] <- paste0("NIPH_", metadata_df$FHI_ID)

# ------------------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------------------
# Remove unwanted columns from final output
drop_cols <- c(
  "Run",
  "Agens",
  "Gruppenavn",
  "Prøvenr",
  "Ref.ab.ID",
  "Materiale",
  "Reflab.ID",
  "Prøvetatt.dato",
  "Mottatt.dato",
  "Godkjent.dato",
  "Rekvisisjonsnr",
  "Lokasjon",
  "Pasientstatus",
  "Rekvirentkode",
  "Rekvirent"
)

# Intersect with actual columns to avoid errors
drop_present <- intersect(drop_cols, colnames(metadata_df))

if (length(drop_present) > 0) {
  metadata_out <- metadata_df[, !(colnames(metadata_df) %in% drop_present), drop = FALSE]
} else {
  metadata_out <- metadata_df
}

write.xlsx(metadata_out, output_xlsx, rowNames = FALSE)

write.table(
  metadata_out,
  output_tsv,
  sep = "\t",
  row.names = FALSE,
  quote = FALSE,
  na = ""
)

cat("Written:\n", output_xlsx, "\n", output_tsv, "\n")