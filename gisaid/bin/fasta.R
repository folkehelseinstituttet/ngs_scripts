#!/usr/bin/env Rscript

# Load packages
library(optparse)
library(phylotools)
library(tidyverse)
library(stringr)
library(lubridate)
library(readxl)

# Load metadata
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 11) {
    stop("Usage: fasta.R <csv> <FHI_1> <FHI_2> <FHI_3> <MIK> <Artic_1> <Artic_2> <Nano_1> <Nano_2> <Nano_3> <Nano_4>", call. = FALSE)
}

# sample_sheet <- read_xlsx("/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_sample_sheet.xlsx") %>% filter(str_detect(platform, "^#", negate = TRUE))

#sample_sheet <- read_xlsx(args[1]) %>%
#  # Remove rows starting with "#"
#  filter(str_detect(platform, "^#", negate = TRUE))
#
metadata      <- read_csv(args[1])

FHI_files_1   <- args[2] # FHI_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2021/"
FHI_files_2   <- args[3] # FHI_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2022/"
FHI_files_3   <- args[4] # FHI_files_3 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2023/"
MIK_files     <- args[5] # MIK_files <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_MIK"
Artic_files_1 <- args[6] # Artic_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2021"
Artic_files_2 <- args[7] # Artic_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2022"
Nano_files_1  <- args[8] # Nano_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2021"
Nano_files_2  <- args[9] # Nano_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2022"
Nano_files_3  <- args[10] # Nano_files_3 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2023"
Nano_files_4  <- args[11] # Nano_files_4 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2024"

# Open connection to log file
log_file <- file(paste0(Sys.Date(), "_fasta_raw.log"), open = "a")

# Create empty objects to populate ----------------------------------------
fastas_final <- tibble(
  "seq.name" = character(),
  "seq.text" = character()
)

# Start to list directories first
dirs_fhi  <- c(list.dirs(FHI_files_1, recursive = FALSE), list.dirs(FHI_files_2, recursive = FALSE), list.dirs(FHI_files_3, recursive = FALSE))
dirs_mik  <- list.dirs(MIK_files, recursive = FALSE)
dirs_ill  <- c(list.dirs(Artic_files_1, recursive = FALSE), list.dirs(Artic_files_2, recursive = FALSE))
dirs_nano <- c(list.dirs(Nano_files_1, recursive = FALSE), list.dirs(Nano_files_2, recursive = FALSE), list.dirs(Nano_files_3, recursive = FALSE), list.dirs(Nano_files_4, recursive = FALSE))

# Find sequences on N: and create fasta object ----------------------------
# First create empty data frame to fill
suppressWarnings(rm(fastas)) # Remove old objects
fastas <- data.frame(seq.name = character(),
                     seq.text = character())
pb <- txtProgressBar(min = 0, max = nrow(metadata), initial = 0)
for (i in 1:nrow(metadata)) {
  setTxtProgressBar(pb, i)
  # Remove the fasta object for each passage
  try(rm(fasta))
  if (metadata$code[i] == "FHI") {
    # Pick our the relevant oppsett
    dir <- dirs_fhi[grep(paste0(metadata$SETUP[i], "\\b"), dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)
    
    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    # Skip the dash for NSC samples
    #fasta <- filepaths[grep(str_remove(metadata$SEARCH_COLUMN[i], "-"), filepaths)]

  } else if (metadata$code[i] == "MIK") {
    # Pick our the relevant oppsett
    dir <- dirs_mik[grep(paste0(metadata$SETUP[i], "\\b"), dirs_mik)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]

  } else if (metadata$code[i] == "Artic_Ill") {
    # Pick our the relevant oppsett
    dir <- dirs_ill[grep(metadata$SETUP[i], dirs_ill)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]

  } else if (metadata$code[i] == "Artic_Nano") {

    # Pick our the relevant oppsett
    oppsett <- gsub("Nr", "", (gsub("/Nano", "", metadata$SETUP[i])))
    # Activate this for new sequence IDs
    #oppsett <- str_split(oppsett, "/", simplify = TRUE)[,1]
    dir <- dirs_nano[grep(oppsett, dirs_nano)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fasta$",
                            full.names = TRUE,
                            recursive = TRUE)

    # change dash to underscore for new sequence ids:
    fasta <- filepaths[grep(str_replace(metadata$SEARCH_COLUMN[i], "-", "_"), filepaths)]
    
    if (length(fasta) == 0) {
      fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    }
  }

  # Read fasta sequence and change name to Gisaid virus name
  if (exists("fasta")) {
    if (length(fasta) == 1) {
      dummy <- read.fasta(fasta) 
      # Convert to tibble for easier manipulation
      dummy <- as_tibble(dummy)

      # Set virus name as fasta header
      dummy[1, 1] <- metadata$covv_virus_name[i]

      # Add fasta file to dataframe
      fastas <- rbind(fastas, dummy)
    } else if (length(fasta > 1)) {
      cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "found more than one matching sequence id\n"),
          file = log_file)
    }
  } else {
    cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "could not find the sequence\n"),
        file = log_file)
  }
}

if (nrow(fastas) > 0) {
  dat2fasta(fastas, outfile = paste0(Sys.Date(), "_raw.fasta"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)
