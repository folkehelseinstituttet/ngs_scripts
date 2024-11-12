# Capture command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Assign the arguments to variables

SID <- args[1] #RunID from argument
submitter <- args[2] #submitter from argument

# Function to write filtered FASTA files and remove HA| or NA| from headers
write_fasta <- function(output_path, filtered_data, rsvdb) {
  # Open the file in write mode
  file_con <- file(output_path, open = "w")
  
  # Loop through each row in the filtered data and write the FASTA entry
  for (i in 1:nrow(filtered_data)) {
    # Lookup the Isolate_Name in rsvdb by matching the key
    isolate_name <- rsvdb$Isolate_Name[rsvdb$key == filtered_data$key[i]]
    
    # If Isolate_Name is found, use it as the header; otherwise, use the default header
    if (length(isolate_name) > 0) {
      header <- isolate_name
    } else {
      header <- paste(filtered_data$experiment[i], filtered_data$key[i], sep = "|")
    }
    
    # Remove "HA|" or "NA|" from headers if necessary
    if (filtered_data$experiment[i] == "Genome") {
      header <- gsub("^Genome\\|", "", header)
    }
    
    sequence <- filtered_data$sequence[i]
    cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
  }
  
  # Close the file connection
  close(file_con)
}



source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/BN RSV 24-25 Nextstrain.R")

library(lubridate)
library(tidyverse)
library(writexl)
library(stringr)
library(stringi)
library(tsibble)
library(officer)
library(magrittr)
library(dplyr)
library(tidyr)
library(tibble)
library(openxlsx)
library(readxl)
library(base64enc)
library(purrr)


# Define metadata
passage <- "Clinical Specimen"
host <- "Human"
Location <- "Norway"
sub_lab <- "Norwegian Institute of Public Health, Department of Virology"
address <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors <- "Bragstad, K; Hungnes, O; Riis, R; Fossum E."
GISAIDnr <- 3869  # Converting directly to numeric
Sequencing_Technology <- "Oxford Nanopore"
Assembly_Method <- "IRMA FLU-minion"
Sequencing_Strategy <- "Targeted-amplification "

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")


# Proceed with data filtering and selection
rsvdb <- fludb %>%
  filter(ngs_run_id == SID) %>%                      # Ensure SID is defined and matches the column
  filter(ngs_sekvens_resultat != "") %>%             # Remove empty results
  filter(prove_kategori != "Ref")              # Remove references


# Now select the required columns
rsvdb <- rsvdb %>% select("key", "ngs_sekvens_resultat", "pasient_alder","prove_tatt", "pasient_kjonn", "prove_innsender_id", "pasient_fylke_name",
                          "ngs_coverage", "prove_innsender_adresse", "prove_innsender_navn", "pasient_status", "prove_kategori")
                                                  
# Data cleaning and manipulation
rsvdb <- rsvdb %>% 
  mutate(
    Subtype = case_when(  # Creating Subtype column
      str_starts(ngs_sekvens_resultat, "RSVA") ~ "A",
      str_starts(ngs_sekvens_resultat, "RSVB") ~ "B",
      TRUE ~ ""
    ),
    Host_Gender = if_else(toupper(pasient_kjonn) %in% c("M", "F"), toupper(pasient_kjonn), NA_character_),  # Creating Host_Gender column
    Year = year(as.Date(prove_tatt)),  # Extracting year from Sampledate
    age = pasient_alder, 
    Uniq_nr = str_sub(key, start = 5, end = 9),  # Extracting unique number
    Isolate_Name = paste("hRSV",Subtype, "Norway", Uniq_nr, Year, sep = "/")  # Creating Isolate_Name
  )

# Merging with Lab_ID
merged_df <- merge(rsvdb, Lab_ID, by.x = "prove_innsender_id", by.y = "Innsender nr", all.x = TRUE)

# Replace NA and non-numeric values in GISAID_Nr column
merged_df$GISAID_Nr <- ifelse(is.na(merged_df$GISAID_Nr) | is.na(merged_df$GISAID_Nr), GISAIDnr, merged_df$GISAID_Nr)



################### FASTA FILE :
submission <- merged_df %>%
  transmute(
    "submitter" = submitter,
    "virus_name" = merged_df$Isolate_Name,
    "subtype" = merged_df$Subtype,
    "passage" = passage,
    "collection_date" = merged_df$prove_tatt,
    "location" = "Europe / Norway",
    "add_location" = "",
    "host" = host,
    "add_host_info" = "",
        "sampling_strategy" = ifelse(merged_df$prove_kategori == "P1_", 
                               "Sentinel surveillance (ARI)", 
                               ifelse(merged_df$pasient_status == "Inneliggende", 
                                      "Non-sentinel surveillance (hospital)", 
                                      ifelse(merged_df$prove_kategori == "P2_" & merged_df$pasient_status == "Poliklinisk", 
                                             "Non-sentinel surveillance (outpatient)", 
                                             ""))),
    "gender" = merged_df$Host_Gender,
    "patient_age" = merged_df$age,
    "patient_status" = "unknown",
    "specimen" = "",
    "outbreak" = "",
    "last_vaccinated" = "",
    "treatment" = "",
    "seq_technology" = Sequencing_Technology,
    "assembly_method" = Assembly_Method,
    "coverage" = "",
    "orig_lab" = merged_df$prove_innsender_navn,
    "orig_lab_addr" =merged_df$prove_innsender_adresse,
    "provider_sample_id" = "",
    "subm_lab" = sub_lab,
    "subm_lab_addr" = address,
    "subm_sample_id" = "",
    "authors" = authors,
    "comment" = "", 
    "comment_type" = ""

  )
    
# Define the output file path and filename
output_dir <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/10-GISAID"
output_filename_excel <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".xlsx")
output_path_excel <- file.path(output_dir, output_filename_excel)

# Write the submission dataframe to an Excel file
write.xlsx(submission, output_path_excel, rownames = FALSE)

# Set the output file path and filename for CSV
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/10-GISAID"
output_filename_csv <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".csv")
output_path_csv <- file.path(output_dir_csv, output_filename_csv)

# Write the submission dataframe to a CSV file
write.csv(submission, output_path_csv, row.names = FALSE, fileEncoding = "UTF-8")


# Step 1: Filter `filtered_seq` by Isolate_Name 
filtered_seq <- filtered_seq %>% filter(key %in% merged_df$key)


# Create the output filename for the FASTA file
output_filename_fasta <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".fasta")
output_path_fasta <- file.path(output_dir_csv, output_filename_fasta)

write_fasta(output_path_fasta, filtered_seq, rsvdb)

