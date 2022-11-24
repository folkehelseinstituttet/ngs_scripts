#!/usr/bin/env Rscript

# Load packages
library(optparse)
library(tidyverse)
library(readxl)
library(stringr)
library(lubridate)

# Load sample sheet
args = commandArgs(trailingOnly=TRUE)
if (length(args) < 2) {
    stop("Usage: metadata.R <samplesheet> <BN>", call.=FALSE)
}

# Read the sample sheet from the first argument
sample_sheet <- read_xlsx(args[1]) %>% 
  # Remove rows starting with "#"
  filter(str_detect(platform, "^#", negate = TRUE))

# Load the BN object from the second argument
# load("/home/jonr/Prosjekter/FHI_Gisaid/BN.RData")
load(args[2])

# Open connection to log file
log_file <- file(paste0(Sys.Date(), "_metadata_raw.log"), open = "a")


# Set fixed information ------------------------------------
type <- "betacoronavirus"
passage <- "original"
host <- "Human"
gender <- "Unknown"
age <- "Unknown"
status <- "Unknown"
covv_subm_sample_id <- "Unknown"
covv_outbreak <- "Unknown"
covv_add_host_info <- "Unknown"
covv_add_location <- "Unknown"
covv_provider_sample_id <- "Unknown"
covv_last_vaccinated <- "Unknown"
covv_treatment <- "Unknown"
specimen <- "Unknown"

# Create empty objects to populate ----------------------------------------
metadata_final <- tibble(
  submitter = character(),
  fn  = character(),
  covv_virus_name = character(),
  covv_type = character(),
  covv_passage = character(),
  covv_collection_date = ymd(),
  covv_location = character(),
  covv_host = character(),
  covv_gender = character(),
  covv_sampling_strategy = character(),
  covv_patient_age = character(),
  covv_patient_status = character(),
  covv_specimen = character(), 
  covv_seq_technology = character(), 
  covv_assembly_method = character(),
  covv_orig_lab = character(), 
  covv_orig_lab_addr = character(), 
  covv_subm_lab = character(),
  covv_subm_lab_addr = character(), 
  covv_authors = character(), 
  covv_subm_sample_id = character(),
  covv_outbreak = character(), 
  covv_add_host_info = character(), 
  covv_add_location = character(),
  covv_provider_sample_id = character(), 
  covv_last_vaccinated = character(),
  covv_treatment = character(),
  covv_coverage = character()
)

# Read data from BioNumerics ----------------------------------------------
# Convert empty strings to NA
BN <- BN %>% mutate_all(list(~na_if(.,"")))

# Initial filtering and cleaning
tmp <- BN %>%
  # Remove previously submitted samples
  filter(is.na(GISAID_EPI_ISL)) %>% 
  # Fjerne evt positiv controll
  filter(str_detect(KEY, "pos", negate = TRUE)) %>%
  # Endre Trøndelag til Trondelag
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "Tr\xf8ndelag", "Trondelag")) %>%
  # Endre Møre og Romsdal
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "M\xf8re", "More")) %>%
  # Endre Sør
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "S\xf8r", "Sor")) %>%
  # Change "Ukjent" in FYLKENAVN to NA
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "Ukjent")) %>% 
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "ukjent")) %>% 
  # Fix date format
  mutate("PROVE_TATT" = ymd(PROVE_TATT)) %>%
  # Drop samples witout collection date
  filter(!is.na(PROVE_TATT))

# Set originating labs and adresses ---------------------------------------
lab_lookup_table <- tribble(
  ~`Lab code`, ~`Lab`, ~`Lab address`,
  0,	"Norwegian Institute of Public Health, Department of Virology",	"P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  1,	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  2,	"Akershus University Hospital, Department for Microbiology and Infectious Disease Control",	"P.O.Box 1000, N-1478 Loerenskog, Norway",
  3,	"Oslo University Hospital, Department of Microbiology",	"P.O.Box 4956 Nydalen, N-0424 Oslo, Norway",
  4,	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  5,	"Innlandet Hospital Trust, Division Lillehammer, Department for Medical Microbiology", "P.O.Box 990, N-2629 Lillehammer, Norway",
  6,	"Medical Microbiology Unit, Department for Laboratory Medicine, Drammen Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  7,	"Vestfold Hospital, Toensberg, Department of Microbiology",	"P.O.Box 2168, N-3103 Toensberg, Norway",
  8,	"Unilabs Laboratory Medicine", "Leirvollen 19, N-3736 Skien, Norway",
  9, NA, NA,
  10,	"Hospital of Southern Norway - Kristiansand, Department of Medical Microbiology",	"P.O.Box 416 Lundsiden, N-4604 Kristiansand, Norway",
  11,	"Dept. of Medical Microbiology, Stavanger University Hospital, Helse Stavanger HF", "P.O.Box 8100, N-4068 Stavanger, Norway",
  12,	"Haukeland University Hospital, Dept. of Microbiology",	"P.O.Box 1400, N-5021 Bergen, Norway",
  13,	"Haugesund Hospital, laboratory for Medical Microbiology", "P.O.Box 2170, N-5504 Haugesund, Norway",
  14,	"Foerde Hospital, Department of Microbiology", "P.O.Box 1000, N-6807 Foerde, Norway",
  15,	"Department of Medical Microbiology - section Molde, Molde Hospital",	"Parkveien 84, N-6407 Molde, Norway",
  16,	"Department of Medical Microbiology, St. Olavs hospital",	"P.O.box 3250 Torgarden, N-7006 Trondheim, Norway",
  17,	"Levanger Hospital, laboratory for Medical Microbiology", "P.O.box 333, N-7601 Levanger, Norway",
  18,	"Nordland Hospital - Bodo, Laboratory Department, Molecular Biology Unit", "P.O.Box 1480, N-8092 Bodo, Norway",
  19,	"University Hospital of Northern Norway, Department for Microbiology and Infectious Disease Control",	"P.O.Box 56, N-9038 Tromsoe, Norway",
  20, "Norwegian Institute of Public Health, Department of Virology",	"P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  21,	NA, NA,
  22,	"Department of medical microbiology, section Aalesund, Aalesund Hospital", "N-6026 Aalesund, Norway",
  23,	NA, NA,
  24, "Department of Medical Microbiology, Baerum Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  25,	"Telemark Hospital Trust – Skien, Dept. of Medical Microbiology",	"P.O.Box 2900 Kjørbekk, N-3710 Skien",
  26,	"Unilabs Laboratory Medicine", "Silurveien 2 B, N-0380 Oslo, Norway",
  27,	"Oslo Helse", "Hegdehaugsveien 36, 0352 Oslo"
) %>%
  mutate(`Lab code` = as.character(`Lab code`))

#############################################
## Define functions
#############################################

# Define lookup function to decide originating lab and adress ------------
lookup_function <- function(metadata) {
  for (row in seq_along(metadata$INNSENDER)) {
    if (metadata[row,]$INNSENDER == 0){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[1,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[1,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 1){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[2,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[2,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 2){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[3,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[3,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 3){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[4,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[4,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 4){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[5,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[5,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 5){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[6,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[6,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 6){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[7,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[7,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 7){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[8,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[8,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 8){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[9,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[9,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 9){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[10,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[10,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 10){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[11,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[11,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 11){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[12,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[12,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 12){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[13,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[13,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 13){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[14,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[14,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 14){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[15,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[15,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 15){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[16,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[16,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 16){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[17,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[17,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 17){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[18,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[18,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 18){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[19,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[19,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 19){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[20,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[20,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 20){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[21,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[21,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 21){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[22,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[22,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 22){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[23,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[23,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 23){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[24,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[24,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 24){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[25,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[25,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 25){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[26,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[26,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 26){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[27,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[27,]$`Lab address`
    } else if (metadata[row,]$INNSENDER == 27){
      metadata[row,]$covv_orig_lab <- lab_lookup_table[28,]$Lab
      metadata[row,]$covv_orig_lab_addr <- lab_lookup_table[28,]$`Lab address`
    }
  }
  return(metadata)
}

# Define filter function --------------------------------------------------
filter_BN <- function() {
    if (sample_sheet$platform[i] == "Artic_Illumina") {
      oppsett_details <- tmp %>%
        filter(str_detect(SAMPLE_CATEGORY, sample_sheet$oppsett[i])) %>%
        # Behold bare de som er meldt smittesporing. Disse skal da være godkjent.
        filter(!is.na(MELDT_SMITTESPORING)) %>%
        # Filtrer på coverage >= 94%
        filter(Dekning_Artic >=94) %>%
        mutate(SEARCH_COLUMN = RES_CDC_INFB_CT) %>%
        rename("COVERAGE" = RES_CDC_INFA_RX)
    } else if (sample_sheet$platform[i] == "Artic_Nanopore") {
      oppsett_details <- tmp %>%
        filter(str_detect(SEKV_OPPSETT_NANOPORE, sample_sheet$oppsett[i])) %>%
        # Behold bare de som er meldt smittesporing. Disse skal da være godkjent.
        filter(!is.na(MELDT_SMITTESPORING)) %>%
        # Filtrer på coverage >= 94%
        filter(Dekning_Nano >=94) %>%
        mutate(SEARCH_COLUMN = SEQUENCEID_NANO29) %>%
        rename("COVERAGE" = COVARAGE_DEPTH_NANO)
    } else if (sample_sheet$platform[i] == "Swift_FHI") {
      oppsett_details <- tmp %>%
        filter(str_detect(SEKV_OPPSETT_SWIFT7, sample_sheet$oppsett[i])) %>%
        # Behold bare de som er meldt smittesporing. Disse skal da være godkjent.
        filter(!is.na(MELDT_SMITTESPORING)) %>%
        # Filtrer på coverage >= 94%
        filter(Dekning_Swift >=94) %>%
        # Create column for looping through later
        mutate(SEARCH_COLUMN = SEQUENCEID_SWIFT) %>%
        rename("COVERAGE" = COVERAGE_DEPTH_SWIFT)
    } else if (sample_sheet$platform[i] == "Swift_MIK") {
      oppsett_details <- tmp %>%
        filter(str_detect(SEKV_OPPSETT_SWIFT7, sample_sheet$oppsett[i])) %>%
        # Filtrer på coverage >= 94%
        filter(Dekning_Swift >=94) %>%
        # Remove "OUS-" from Sequence ID
        mutate(SEQUENCE_ID_TRIMMED = str_remove(SEQUENCEID_SWIFT, "OUS-")) %>%
        # Create column for looping through later
        mutate(SEARCH_COLUMN = SEQUENCEID_SWIFT) %>%
        rename("COVERAGE" = COVERAGE_DEPTH_SWIFT)
    }

  # Drop samples with missing data
  oppsett_details_final <- oppsett_details
  if (sample_sheet$platform[i] == "Artic_Illumina" || sample_sheet$platform[i] == "Artic_Nanopore" || sample_sheet$platform[i] == "Swift_FHI") {
    for (x in seq_along(oppsett_details$INNSENDER)){
      if (is.na(oppsett_details$INNSENDER[x]) && is.na(oppsett_details$FYLKENAVN[x])){
        # Check both
        cat(paste0("Key: ", oppsett_details$KEY[x], ", ", "had no Innsender and no Fylke in BN\n"),
            file = log_file)
        # Remove from submission
        #oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
      } else if (is.na(oppsett_details$INNSENDER[x])){
        # Check INNSENDER
        cat(paste0("Key: ", oppsett_details$KEY[x], ", ", "had no Innsender info in BN - removed from submission\n"),
            file = log_file)
        # Remove from submission
        oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
      } else if (is.na(oppsett_details$FYLKENAVN[x])) {
        # Check Fylkenavn
        cat(paste0("Key: ", oppsett_details$KEY[x], ", ", "had no Fylkenavn info in BN\n"),
            file = log_file)
        # Remove from submission
        #oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
      } else if (str_detect(oppsett_details$FYLKENAVN[x], "kjent")) {
        cat(paste0("Key: ", oppsett_details$KEY[x], ", ", "had Ukjent in Fylkenavn in BN - removed from submission\n"),
            file = log_file)
        # Remove from submission
        oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
      } 
    }
  } else if (sample_sheet$platform[i] == "Swift_MIK") {
        for (x in seq_along(oppsett_details$INNSENDER)){
          # Check Fylkenavn
          if (is.na(oppsett_details$FYLKENAVN[x])) {
            cat(paste0("oppsett: ", oppsett_details$SEKV_OPPSETT_SWIFT7[x], ", Key: ", oppsett_details$KEY[x], ", ", "had no Fylkenavn info in BN\n"),
                file = log_file)
            # Remove from submission
            #oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
          } else if (str_detect(oppsett_details$FYLKENAVN[x], "kjent")) {
            cat(paste0("oppsett: ", oppsett_details$SEKV_OPPSETT_SWIFT7[x], ", Key: ", oppsett_details$KEY[x], ", ", "had Ukjent in Fylkenavn in BN\n"),
                file = log_file)
            # Remove from submission
            #oppsett_details_final <- oppsett_details_final[-grep(oppsett_details$KEY[x], oppsett_details_final$KEY),]
          }
        }
      }
  return(oppsett_details_final)
}

# Define metadata function ------------------------------------------------
create_metadata <- function(oppsett_details_final) {

  metadata <- oppsett_details_final %>%
    # Lage kolonne for "year"
    separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>% 
    # Add info on sentinel sample (Fyrtårn)
    mutate("covv_sampling_strategy" = case_when(
              P == "1" ~ "Sentinel surveillance (ARI)",
              P != "1" ~ "Unknown"
          )
    )

  if (sample_sheet$platform[i] == "Swift_MIK") {
    metadata <- metadata %>%
      # For OUS bruke hele KEY som stammenr
      mutate("Uniq_nr" = str_sub(KEY, start = 1, end = -1))
  } else {
    metadata <- metadata %>%
      # Trekke ut sifrene fra 5 og til det siste fra BN KEY
      mutate("Uniq_nr" = str_sub(KEY, start = 5, end = -1)) %>%
      # Fjerne ledende nuller fra stammenavnet
      mutate("Uniq_nr" = str_remove(Uniq_nr, "^0+"))
  }

    metadata <- metadata %>%
      # Legge til kolonner med fast informasjon for å lage "Virus name" senere
      add_column("Separator" = "/",
                 "GISAID_prefix" = "hCoV-19/",
                 "Country" = "Norway/",
                 "Continent" = "Europe/") %>%
      # Make "Virus name" column
      unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
      # Lage Location-kolonne
      unite("covv_location", c(Continent, Country, FYLKENAVN), sep = "", remove = FALSE) %>%
      # Legge til faste kolonner
      add_column("submitter" = sample_sheet$submitter[i],
                 "fn" = sample_sheet$fasta_filename[i],
                 "covv_type" = type,
                 "covv_passage" = passage,
                 "covv_host" = host,
                 "covv_gender" = gender,
                 "covv_patient_age" = age,
                 "covv_patient_status" = status,
                 "covv_specimen" = specimen,
                 "covv_seq_technology" = sample_sheet$seq_tech[i],
                 "covv_assembly_method" = sample_sheet$ass_method[i],
                 "covv_orig_lab" = sample_sheet$orig_lab[i],
                 "covv_orig_lab_addr" = sample_sheet$orig_adr[i],
                 "covv_subm_lab" = sample_sheet$sub_lab[i],
                 "covv_subm_lab_addr" = sample_sheet$address[i],
                 "covv_authors" = sample_sheet$authors[i],
                 "covv_subm_sample_id" = covv_subm_sample_id,
                 "covv_outbreak" = covv_outbreak,
                 "covv_add_host_info" = covv_add_host_info,
                 "covv_add_location" = covv_add_location,
                 "covv_provider_sample_id" = covv_provider_sample_id,
                 "covv_last_vaccinated" = covv_last_vaccinated,
                 "covv_treatment" = covv_treatment) %>%
      # Beholde endelige kolonner og rekkefølge
      select("submitter",
             "fn",
             "covv_virus_name",
             "covv_type",
             "covv_passage",
             "covv_collection_date" = PROVE_TATT,
             "covv_location",
             "covv_host",
             "covv_gender",
             "covv_patient_age",
             "covv_patient_status",
             "covv_specimen",
             "covv_seq_technology",
             "covv_assembly_method",
             "covv_orig_lab",
             "covv_orig_lab_addr",
             "covv_subm_lab",
             "covv_subm_lab_addr",
             "covv_authors",
             "covv_subm_sample_id",
             "covv_outbreak",
             "covv_add_host_info",
             "covv_add_location",
             "covv_provider_sample_id",
             "covv_last_vaccinated",
             "covv_treatment",
             "covv_coverage" = COVERAGE,
             "INNSENDER",
             "covv_sampling_strategy")

  if (sample_sheet$platform[i] == "Swift_MIK") {
    # Remove column INNSENDER
    metadata <- metadata %>% select(-INNSENDER)
  } else {
    # Legge inn orig lab og adresse
    metadata <- lookup_function(metadata)

    # Remove column INNSENDER
    metadata <- metadata %>% select(-INNSENDER)
  }
  return(metadata)
}

#############################################
## Start script
#############################################

# Start script ------------------------------------------------------------
for (i in seq_along(sample_sheet$platform)) {
  print(paste("Processing", sample_sheet$oppsett[i]))
  # Remove old objects
  suppressWarnings(rm(metadata_clean))

  #### Trekke ut prøver ####
  oppsett_details_final <- filter_BN()
  
  if (nrow(oppsett_details_final > 0)){
    #### Lage metadata ####
    metadata <- create_metadata(oppsett_details_final)

  # Join metatada per setup together
    if (exists("metadata")){
      if (nrow(metadata) > 0){
        metadata_final <- bind_rows(metadata_final, metadata)
      }
    } 
  }
}
  
# Write final objects
if (nrow(metadata_final) > 0){
  save(oppsett_details_final, file = "oppsett_details_final.RData")
  write_csv(metadata_final, file = paste0(Sys.Date(), "_raw.csv"))
} else {
  print("Nothing to save. Check the log file")
}

close(log_file)
