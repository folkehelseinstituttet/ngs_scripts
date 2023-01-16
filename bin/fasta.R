#!/usr/bin/env Rscript

# Load packages
library(optparse)
library(phylotools)
library(tidyverse)
library(stringr)
library(lubridate)
library(readxl)

# Load metadata
args = commandArgs(trailingOnly=TRUE)
if (length(args) < 9) {
    stop("Usage: fasta.R <csv> <FHI_1> <FHI_2> <MIK> <Artic_1> <Artic_2> <Nano_1> <Nano_2> <RData>", call.=FALSE)
}

# sample_sheet <- read_xlsx("/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_sample_sheet.xlsx") %>% filter(str_detect(platform, "^#", negate = TRUE))

#sample_sheet <- read_xlsx(args[1]) %>% 
#  # Remove rows starting with "#"
#  filter(str_detect(platform, "^#", negate = TRUE))
#
metadata      <- read_csv(args[1]) 

FHI_files_1   <- args[2] # FHI_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2021/"
FHI_files_2   <- args[3] # FHI_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2022/"
MIK_files     <- args[4] # MIK_files <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_MIK"
Artic_files_1 <- args[5] # Artic_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2021"
Artic_files_2 <- args[6] # Artic_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2022"
Nano_files_1  <- args[7] # Nano_files_1 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2021"
Nano_files_2  <- args[8] # Nano_files_2 <- "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2022"

# Get oppsett_details_final object
load(args[9]) # load("/home/jonr/Prosjekter/FHI_Gisaid/oppsett_details_final.RData")

# Open connection to log file
log_file <- file(paste0(Sys.Date(), "_fasta_raw.log"), open = "a")

# Create empty objects to populate ----------------------------------------
fastas_final <- tibble(
  "seq.name" = character(),
  "seq.text" = character()
)

# Start to list directories first
dirs_fhi  <- c(list.dirs(FHI_files_1, recursive = FALSE), list.dirs(FHI_files_2, recursive = FALSE))
dirs_mik  <- list.dirs(MIK_files, recursive = FALSE))
dirs_ill  <- c(list.dirs(Artic_files_1, recursive = FALSE), list.dirs(Artic_files_2, recursive = FALSE))
dirs_nano <- c(list.dirs(Nano_files_1, recursive = FALSE), list.dirs(Nano_files_2, recursive = FALSE))

# Find sequences on N: and create fasta object ----------------------------
# First create empty data frame to fill
suppressWarnings(rm(fastas)) # Remove old objects
fastas <- data.frame(seq.name = character(),
                     seq.text = character())
for (i in 1:nrow(metadata)) {
  if (metadata$code[i] == "FHI"){
    # Pick our the relevant oppsett
    dir <- dirs_fhi[grep(paste0(metadata$SETUP[i], "\\b"), dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)
    samples <- gsub("_.*", "", basename(filepaths))

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    if (length(fasta) > 0) {
      dummy <- read.fasta(fasta) 
      # Convert to tibble for easier manipulation
      dummy <- as_tibble(dummy)
      
      # Set virus name as fasta header
      dummy[1,1] <- metadata$covv_virus_name[i]

      # Add fasta file to dataframe
      fastas <- rbind(fastas, dummy)

    } else {
      cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "could not find the sequence\n"),
      file = log_file)
    }

  } else if (metadata$code[i] == "MIK") {
    # Pick our the relevant oppsett
    dir <- dirs_mik[grep(paste0(metadata$SETUP[i], "\\b"), dirs_mik)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    samples <- gsub("_.*","", gsub(".*/","", filepaths))

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    if (length(fasta) > 0) {
      dummy <- read.fasta(fasta) 
      # Convert to tibble for easier manipulation
      dummy <- as_tibble(dummy)
      
      # Set virus name as fasta header
      dummy[1,1] <- metadata$covv_virus_name[i]

      # Add fasta file to dataframe
      fastas <- rbind(fastas, dummy)
    } else {
      cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "could not find the sequence\n"),
      file = log_file)
    }


  } else if (metadata$code[i] == "Artic_Ill") {
    # Pick our the relevant oppsett
    dir <- dirs_ill[grep(metadata$SETUP[i], dirs_ill)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    # Dropper det siste tallet.
    samples <- gsub("_.*", "", basename(filepaths))
    #samples <- str_sub(gsub("Artic", "", gsub("_.*","", gsub(".*/","", filepaths))), start = 1, end = -2)

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    if (length(fasta) > 0) {
      dummy <- read.fasta(fasta) 
      # Convert to tibble for easier manipulation
      dummy <- as_tibble(dummy)
      
      # Set virus name as fasta header
      dummy[1,1] <- metadata$covv_virus_name[i]

      # Add fasta file to dataframe
      fastas <- rbind(fastas, dummy)
    } else {
      cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "could not find the sequence\n"),
      file = log_file)
    }


  } else if (platform == "Artic_Nano") {

    # Pick our the relevant oppsett
    oppsett <- gsub("Nr", "", (gsub("/Nano", "", metadata$SETUP[i])))
    dir <- dirs_nano[grep(paste0(metadata$SETUP[i]), dirs_nano)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fasta$",
                            full.names = TRUE,
                            recursive = TRUE)

    fasta <- filepaths[grep(metadata$SEARCH_COLUMN[i], filepaths)]
    if (length(fasta) > 0) {
      dummy <- read.fasta(fasta) 
      # Convert to tibble for easier manipulation
      dummy <- as_tibble(dummy)
      
      # Set virus name as fasta header
      dummy[1,1] <- metadata$covv_virus_name[i]

      # Add fasta file to dataframe
      fastas <- rbind(fastas, dummy)
    } else {
      cat(paste0("sequence_id: ", metadata$SEARCH_COLUMN[i], ", ", "could not find the sequence\n"),
      file = log_file)
    }
  }
}

if (nrow(fastas) > 0){
  dat2fasta(fastas, outfile = paste0(Sys.Date(), "_raw.fasta"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)
