#!/usr/bin/env Rscript

# Load packages
library()


pacman::p_load(optparse, phylotools, tidyverse, readxl, stringr, lubridate)

# Load metadata
args = commandArgs(trailingOnly=TRUE)
metadata <- read_xlsx(args[1]) 

# Open connection to log file
log_file <- file(paste0(Sys.Date(), ".log"), open = "a")

# Create empty objects to populate ----------------------------------------
fastas_final <- tibble(
  "seq.name" = character(),
  "seq.text" = character()
)

# Read data from BioNumerics ----------------------------------------------
BN <- load(args[2])
# Convert empty strings to NA
BN <- BN %>% mutate_all(list(~na_if(.,"")))


#############################################
## Define functions
#############################################

# Find sequences on N: and create fasta object ----------------------------
find_sequences <- function(platform, oppsett) {
  if (platform == "Swift_FHI"){
    # Search the N: disk for consensus sequences
    #try(dirs_fhi <- c(list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2021/", recursive = FALSE), list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2022/", recursive = FALSE)))
    try(dirs_fhi <- c(list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2021/", recursive = FALSE),
                      list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_FHI/2022/", recursive = FALSE)))

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
    # dirs_fhi <- list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_MIK", recursive = FALSE)
    try(dirs_fhi <- list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina_NSC_MIK", recursive = FALSE))
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
    #try(dirs_fhi <- c(list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2021", recursive = FALSE), list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2022", recursive = FALSE)))
    try(dirs_fhi <- c(list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2021", recursive = FALSE),
                      list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Illumina/2022", recursive = FALSE)))

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
    #try(dirs_fhi <- c(list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2021", recursive = FALSE), list.dirs("/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2022", recursive = FALSE)))
    try(dirs_fhi <- c(list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2021", recursive = FALSE),
                      list.dirs("/home/docker/N/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/1-Nanopore/2022", recursive = FALSE)))

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
  suppressWarnings(rm(metadata_clean))
  suppressWarnings(rm(fastas_clean))

  #### Trekke ut prøver ####
  oppsett_details_final <- filter_BN()
  
  if (nrow(oppsett_details_final > 0)){
    #### Lage metadata ####
    metadata <- create_metadata(oppsett_details_final)
    
    #### Find sequences on N: ####
    fastas <- find_sequences(sample_sheet$platform[i], sample_sheet$oppsett[i])
    
    #### Run Frameshift analysis ####
    if (nrow(fastas) > 0) {
      FS(fastas)
    } else {
      cat(paste0("No fastas found for oppsett ", sample_sheet$oppsett[i]),
          file = log_file)
    }
    
    fastas_clean <- remove_FS_fasta(fastas)
    
    if (exists("fastas_clean")){
      metadata_clean <- remove_FS_metadata(metadata)
    }
    
  } else {
    cat(paste0("Oppsett: ", sample_sheet$oppsett[i], " had no samples to submit\n"),
        file = log_file)
  }
  
  # Join final metadata and fastas with final objects
  if (exists("metadata_clean")){
    if (nrow(metadata_clean) > 0){
      metadata_final <- bind_rows(metadata_final, metadata_clean)
      fastas_final <- bind_rows(fastas_final, fastas_clean)
      # Clean up files
      if (sample_sheet$platform[i] == "Artic_Nanopore"){
        name <- str_replace(sample_sheet$oppsett[i], "/", "_")
        file.rename("/home/docker/Fastq/Frameshift/FrameShift_tmp.xlsx", paste0("/home/docker/Fastq/FrameShift_", name, ".xlsx"))
      } else {
        file.rename("/home/docker/Fastq/Frameshift/FrameShift_tmp.xlsx", paste0("/home/docker/Fastq/FrameShift_", sample_sheet$oppsett[i], ".xlsx"))
      }
    } 
  }

}
  
# Write final objects

if (nrow(metadata_final) > 0){
  dat2fasta(fastas_final, outfile = paste0("/home/docker/Fastq/", Sys.Date(), ".fasta"))
  write_csv(metadata_final, file = paste0("/home/docker/Fastq/", Sys.Date(), ".csv"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)
