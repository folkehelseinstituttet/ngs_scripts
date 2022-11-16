#!/usr/bin/env Rscript

# Load packages
library(optparse)
library(phylotools)
library(tidyverse)
library(stringr)
library(lubridate)

# Load metadata
args = commandArgs(trailingOnly=TRUE)
if (length(args) < 2) {
    stop("Usage: fasta.R <metadata_raw> <BN>", call.=FALSE)
}

sample_sheet <- read_xlsx(args[1]) %>% 
  # Remove rows starting with "#"
  filter(str_detect(platform, "^#", negate = TRUE))

metadata <- read_csv(args[2]) 

FHI_files_1 <- args[3]
FHI_files_2 <- args[4]
MIK_files <- args[5]
Artic_files_1 <- args[6]
Artic_files_2 <- args[7]
Nano_files_1 <- args[8]
Nano_files_2 <- args[9]

# Get oppsett_details_final object
load(args[10])

# Open connection to log file
log_file <- file(paste0(Sys.Date(), "fasta_raw.log"), open = "a")

# Create empty objects to populate ----------------------------------------
fastas_final <- tibble(
  "seq.name" = character(),
  "seq.text" = character()
)

#############################################
## Define functions
#############################################

# Find sequences on N: and create fasta object ----------------------------
find_sequences <- function(platform, oppsett) {
  if (platform == "Swift_FHI"){
    # Search the N: disk for consensus sequences
    try(dirs_fhi <- c(list.dirs(FHI_files_1, recursive = FALSE),
                      list.dirs(FHI_files_2, recursive = FALSE)))

    # Pick our the relevant oppsett
    dir <- dirs_fhi[grep(paste0(oppsett, "\\b"), dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)
    samples <- gsub("_.*", "", basename(filepaths))

  } else if (platform == "Swift_MIK") {
    # Search the N: disk for consensus sequences.
    try(dirs_fhi <- list.dirs(MIK_files, recursive = FALSE))
    # Pick our the relevant oppsett
    dir <- dirs_fhi[grep(paste0(oppsett, "\\b"), dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "ivar\\.consensus\\.masked_Nremoved\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    samples <- gsub("_.*","", gsub(".*/","", filepaths))
  } else if (platform == "Artic_Illumina") {
    # Search the N: disk for consensus sequences.
    try(dirs_fhi <- c(list.dirs(Artic_files_1, recursive = FALSE),
                      list.dirs(Artic_files_2, recursive = FALSE)))

    # Pick our the relevant oppsett
    dir <- dirs_fhi[grep(oppsett, dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fa$",
                            full.names = TRUE,
                            recursive = TRUE)

    # Dropper det siste tallet.
    samples <- gsub("_.*", "", basename(filepaths))
    #samples <- str_sub(gsub("Artic", "", gsub("_.*","", gsub(".*/","", filepaths))), start = 1, end = -2)
  } else if (platform == "Artic_Nanopore") {
    # Search the N: disk for consensus sequences.
    try(dirs_fhi <- c(list.dirs(Nano_files_1, recursive = FALSE),
                      list.dirs(Nano_files_2, recursive = FALSE)))

    # Pick our the relevant oppsett
    oppsett <- gsub("Nr", "", (gsub("/Nano", "", oppsett)))
    dir <- dirs_fhi[grep(paste0(oppsett), dirs_fhi)]

    # List the files
    filepaths <- list.files(path = dir,
                            pattern = "consensus\\.fasta$",
                            full.names = TRUE,
                            recursive = TRUE)
  }

  # Find which filepaths to keep
  #keep <- vector("character", length = length(oppsett_details_final$SEARCH_COLUMN))
  keep <- vector("character")
  for (y in seq_along(oppsett_details_final$SEARCH_COLUMN)){
    if (length(grep(oppsett_details_final$SEARCH_COLUMN[y], filepaths)) == 0){
      cat(paste0("sequence_id: ", oppsett_details_final$SEARCH_COLUMN[y], ", ", "had no sequence, probably wrong folder name in BN\n"),
          file = log_file)
    } else {
      keep[y] <- filepaths[grep(oppsett_details_final$SEARCH_COLUMN[y], filepaths)] 
    }
  }
  # Drop empty elements in keep (where no sequence file was found for the sequence id)
  keep <- keep[!is.na(keep)]
  # Read each fasta file and combine them to create one file
  # First create empty data frame to fill
  fastas <- data.frame(seq.name = character(),
                       seq.text = character())
  
  # Read the fasta sequences
  if (length(keep) > 0){
    for (f in seq_along(keep)){
      tmp <- read.fasta(keep[f])      # read the file
      fastas <- rbind(fastas, tmp)    # append the current file
    }
    # Convert to tibble for easier manipulation
    fastas <- as_tibble(fastas)
    
    # Fix names to match KEY
    if (platform == "Swift_FHI") {
      # Fix names to match SEQUENCEID_SWIFT
      fastas <- fastas %>%
        mutate(SEQUENCEID_SWIFT = str_remove(seq.name, "_ivar_masked"))
    } else if (platform == "Swift_MIK") {
      # Fix names to match SEQUENCEID_SWIFT
      fastas <- fastas %>%
        mutate("tmp" = str_remove(seq.name, "_ivar_masked")) %>%
        mutate(SEQUENCE_ID_TRIMMED = gsub(".*OUS-", "", .$tmp))
    } else if (platform == "Artic_Illumina") {
      fastas <- fastas %>%
        rename("RES_CDC_INFB_CT" = `seq.name`)
    } else if (platform == "Artic_Nanopore") {
      # Fix names to match SEQUENCEID_NANO29
      fastas <- fastas %>%
        separate("seq.name", into = c("SEQUENCEID_NANO29", NA, NA), sep = "/", remove = F)
    }
    
    # Sett Virus name som fasta header
    # Først lage en mapping mellom KEY og virus name
    if (platform == "Swift_FHI") {
      SEQUENCEID_virus_mapping <- oppsett_details_final %>%
        # Trenger også å lage Virus name
        # Lage kolonne for "year"
        separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>%
        # Trekke ut sifrene fra 5 og til det siste fra BN KEY
        mutate("Uniq_nr" = str_sub(KEY, start = 5, end = -1)) %>%
        # Fjerne ledende nuller fra stammenavnet
        mutate("Uniq_nr" = str_remove(Uniq_nr, "^0+")) %>%
        # Legge til kolonner med fast informasjon for å lage "Virus name" senere
        add_column("Separator" = "/",
                   "GISAID_prefix" = "hCoV-19/",
                   "Country" = "Norway/",
                   "Continent" = "Europe/") %>%
        # Make "Virus name" column
        unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
        select(KEY, SEQUENCEID_SWIFT, covv_virus_name)
      
      fastas <- left_join(fastas, SEQUENCEID_virus_mapping, by = "SEQUENCEID_SWIFT") %>%
        select(`seq.name` = covv_virus_name,
               seq.text)
      
    } else if (platform == "Swift_MIK") {
      KEY_virus_mapping <- oppsett_details_final %>%
        # Lage kolonne for "year"
        separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>%
        # Trekke ut sifrene fra 5 og til det siste fra BN KEY
        mutate("Uniq_nr" = str_sub(KEY, start = 1, end = -1)) %>%
        # Legge til kolonner med fast informasjon for å lage "Virus name" senere
        add_column("Separator" = "/",
                   "GISAID_prefix" = "hCoV-19/",
                   "Country" = "Norway/",
                   "Continent" = "Europe/") %>%
        # Make "Virus name" column
        unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
        select(SEQUENCEID_SWIFT, KEY, covv_virus_name, SEQUENCE_ID_TRIMMED)
      
      
      fastas <- left_join(fastas, KEY_virus_mapping, by = "SEQUENCE_ID_TRIMMED") %>%
        select(`seq.name` = covv_virus_name,
               seq.text)
    } else if (platform == "Artic_Illumina") {
      SEQUENCEID_virus_mapping <- oppsett_details_final %>%
        # Trenger også å lage Virus name
        # Lage kolonne for "year"
        separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>%
        # Trekke ut sifrene fra 5 og til det siste fra BN KEY
        mutate("Uniq_nr" = str_sub(KEY, start = 5, end = -1)) %>%
        # Fjerne ledende nuller fra stammenavnet
        mutate("Uniq_nr" = str_remove(Uniq_nr, "^0+")) %>%
        # Legge til kolonner med fast informasjon for å lage "Virus name" senere
        add_column("Separator" = "/",
                   "GISAID_prefix" = "hCoV-19/",
                   "Country" = "Norway/",
                   "Continent" = "Europe/") %>%
        # Make "Virus name" column
        unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
        select(KEY, RES_CDC_INFB_CT, covv_virus_name)
      
      fastas <- left_join(fastas, SEQUENCEID_virus_mapping, by = "RES_CDC_INFB_CT") %>%
        select(`seq.name` = covv_virus_name,
               seq.text)
      
    } else if (platform == "Artic_Nanopore") {
      SEQUENCEID_virus_mapping <- oppsett_details_final %>%
        # Trenger også å lage Virus name
        # Lage kolonne for "year"
        separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>%
        # Trekke ut sifrene fra 5 og til det siste fra BN KEY
        mutate("Uniq_nr" = str_sub(KEY, start = 5, end = -1)) %>%
        # Fjerne ledende nuller fra stammenavnet
        mutate("Uniq_nr" = str_remove(Uniq_nr, "^0+")) %>%
        # Legge til kolonner med fast informasjon for å lage "Virus name" senere
        add_column("Separator" = "/",
                   "GISAID_prefix" = "hCoV-19/",
                   "Country" = "Norway/",
                   "Continent" = "Europe/") %>%
        # Make "Virus name" column
        unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
        select(KEY, SEQUENCEID_NANO29, covv_virus_name)
      
      fastas <- left_join(fastas, SEQUENCEID_virus_mapping, by = "SEQUENCEID_NANO29") %>%
        select(`seq.name` = covv_virus_name,
               seq.text)
    }
  } else {
    print(paste("No fasta files found for", oppsett))
  }

  return(fastas)
}

#############################################
## Start script
#############################################

# Start script ------------------------------------------------------------
for (i in seq_along(sample_sheet$platform)) {
  print(paste("Processing", sample_sheet$oppsett[i]))
  # Remove old objects
  suppressWarnings(rm(fastas))
  
  if (nrow(oppsett_details_final > 0)){
    
    #### Find sequences on N: ####
    fastas <- find_sequences(sample_sheet$platform[i], sample_sheet$oppsett[i])
  }

# Write final objects

if (nrow(metadata_final) > 0){
  dat2fasta(fastas_final, outfile = paste0("/home/docker/Fastq/", Sys.Date(), "_raw.fasta"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)
