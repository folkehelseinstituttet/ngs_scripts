#!/usr/bin/env Rscript

# Load packages
library(optparse)
library(tidyverse)
library(phylotools)

args = commandArgs(trailingOnly=TRUE)

# Open connection to log file
log_file           <- file(paste0(Sys.Date(), "_clean_up.log"), open = "a")

metadata_raw       <- read_csv(args[1])
fasta_raw          <- as_tibble(phylotools::read.fasta(args[2]))
frameshift_results <- args[3]

# Open connection to log file
log_file           <- file(paste0(Sys.Date(), "_clean_up.log"), open = "a")

## Extract OK samples and create final metadata
FS_OK <- read_csv(frameshift_results, col_names = FALSE) %>%
  dplyr::rename("Sample" = X1,
         "Deletions" = X2,
         "Frameshift" = X3,
         "Insertions" = X4,
         "Ready" = X5,
         "Comments" = X6) %>%
  dplyr::filter(Ready == "YES") %>%
  dplyr::rename("covv_virus_name" = "Sample")

metadata_clean <- left_join(FS_OK, metadata_raw, by = "covv_virus_name") %>%
  select(-Deletions, -Frameshift, -Insertions, -Ready, -Comments)

## Extract OK fastas and create final fasta file
FS_NO <- read_csv(frameshift_results, col_names = FALSE) %>%
  dplyr::rename("Sample" = X1,
         "Deletions" = X2,
         "Frameshift" = X3,
         "Insertions" = X4,
         "Ready" = X5,
         "Comments" = X6) %>%
  filter(Ready == "NO")

# Rename navn til å matche navn i fastas
# Join fastas with FS to keep
if (nrow(FS_OK > 0)){
  fastas_clean <- left_join(FS_OK, fasta_raw, by = c("covv_virus_name" = "seq.name")) %>%
    dplyr::select(`seq.name` = covv_virus_name, 
           `seq.text`)
} 

if (nrow(FS_NO > 0)) {
  frameshift <- FS_NO %>% pull(Sample)
  cat(paste0("These sequences had frameshift: ", frameshift),
      file = log_file)    
}

## Write final files
if (nrow(metadata_clean) > 0){
  dat2fasta(fastas_clean, outfile = paste0(Sys.Date(), ".fasta"))
  write_csv(metadata_clean, file = paste0(Sys.Date(), ".csv"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)

