# Capture command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Assign the arguments to variables
SID <- args[1] #RunID from argument

source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/2526/BN FLU 25-26.R")

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
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; ,Dieseth MS"
GISAIDnr <- 3869  # Converting directly to numeric
Sequencing_Technology <- "Oxford Nanopore"
Assembly_Method <- "IRMA FLU-minion"
Sequencing_Strategy <- "Targeted-amplification "

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

source("N:/Virologi/Influensa/RARI/2526/BN FLU 25-26.R")


# Proceed with data filtering and selection
fludb <- fludb %>%
  filter(ngs_run_id == SID) %>%                      # Ensure SID is defined and matches the column
  filter(ngs_sekvens_resultat != "") %>%             # Remove empty results
  filter(!(ngs_sekvens_resultat %in% c("NA", "N2", "N1"))) %>%   # Keep rows that are NOT NA, N2, or N1
  filter(is.na(gisaid_kommentar) | gisaid_kommentar == "")



# Now select the required columns
fludb <- fludb %>% select("key", "ngs_sekvens_resultat", "pasient_fylke_nr", "pasient_alder", "prove_tatt", "tessy_variable", "pasient_kjonn", 
                          "prove_innsender_id", "pasient_fylke_name", "pasient_status", "prove_kategori", "prove_material", "ngs_reads_ha",
                          "ngs_reads_na", "ngs_reads_m", "ngs_reads_ns", "ngs_reads_np", "ngs_reads_pa", "ngs_reads_pb1", "ngs_reads_pb2")

# Data cleaning and manipulation
fludb <- fludb %>% 
  mutate(
    Subtype = case_when(  # Creating Subtype column
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "H1N1",
      str_starts(ngs_sekvens_resultat, "A/H3N2") ~ "H3N2",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "B",
      TRUE ~ ""
    ),
    INFType = if_else(str_starts(ngs_sekvens_resultat, "A/"), "A", "B"),  # Creating INFType column
    Lineage = case_when(  # Creating Lineage column
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "pdm09",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "Victoria",
      TRUE ~ ""
    ),
    Host_Gender = if_else(toupper(pasient_kjonn) %in% c("M", "F"), toupper(pasient_kjonn), NA_character_),  # Creating Host_Gender column
    Year = year(as.Date(prove_tatt)),  # Extracting year from Sampledate
    age = pasient_alder, 
    Uniq_nr = str_sub(key, start = 5, end = 9),  # Extracting unique number
    Isolate_Name = paste(INFType, "Norway", Uniq_nr, Year, sep = "/"),  # Creating Isolate_Name
    Specimen_Source = case_when(  # Creating Specimen_Source column
      str_starts(prove_material, "SEKRET") ~ "",
      str_starts(prove_material, "NAPHSEKR") ~ "nasopharyngeal swab",
      TRUE ~ ""
    ),
    Coverage = rowMeans(across(contains("reads"), ~ as.numeric(replace_na(.x, 0))), na.rm = TRUE)  # Calculating average coverage
  )


# Merging with Lab_ID
merged_df <- merge(fludb, Lab_ID, by.x = "prove_innsender_id", by.y = "Innsender nr", all.x = TRUE)

# Replace NA and non-numeric values in GISAID_Nr column
merged_df$GISAID_Nr <- ifelse(is.na(merged_df$GISAID_Nr) | is.na(merged_df$GISAID_Nr), GISAIDnr, merged_df$GISAID_Nr)

rm(fludb)

################### FASTA FILE :
tmp <- merged_df %>%
  add_column(
    "Isolate_Id" = "",
    "Segment_Ids" = "",
    "Passage_History" = passage,
    "Host" = host,
    "Authors" = authors,
    "Location" = "Norway",
    "province" = merged_df$pasient_fylke_name,
    "sub_province" = "",
    "Location_Additional_info" = "",
    "Host_Additional_info" = "",
    "Seq_Id (HA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "HA"],
                           paste("HA", merged_df$key, sep = "|"), ""),
    "Seq_Id (NA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NA"],
                           paste("NA", merged_df$key, sep = "|"), ""),
    "Seq_Id (PB1)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB1"],
                            paste("PB1", merged_df$key, sep = "|"), ""),
    "Seq_Id (PB2)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB2"],
                            paste("PB2", merged_df$key, sep = "|"), ""),
    "Seq_Id (PA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PA"],
                           paste("PA", merged_df$key, sep = "|"), ""),
    "Seq_Id (MP)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "MP"],
                           paste("MP", merged_df$key, sep = "|"), ""),
    "Seq_Id (NS)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NS"],
                           paste("NS", merged_df$key, sep = "|"), ""),
    "Seq_Id (NP)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NP"],
                           paste("NP", merged_df$key, sep = "|"), ""),
    "Seq_Id (HE)" = "",
    "Seq_Id (P3)" = "",
    "Submitting_Sample_Id" = merged_df$key,
    "Originating_Lab_Id" = merged_df$GISAID_Nr,
    "Originating_Sample_Id" = "",
    "Collection_Month" = month(merged_df$prove_tatt),
    "Collection_Year" = year(merged_df$prove_tatt),
    "Collection_Date" = format(as.Date(merged_df$prove_tatt), "%Y-%m-%d"),
    "Antigen_Character" = "",
    "Adamantanes_Resistance_geno" = "",
    "Oseltamivir_Resistance_geno" = "",
    "Zanamivir_Resistance_geno" = "",
    "Peramivir_Resistance_geno" = "",
    "Other_Resistance_geno" = "",
    "Adamantanes_Resistance_pheno" = "",
    "Oseltamivir_Resistance_pheno" = "",
    "Zanamivir_Resistance_pheno" = "",
    "Peramivir_Resistance_pheno" = "",
    "Other_Resistance_pheno" = "",
    "Host_Age" = merged_df$pasient_alder,
    "Host_Age_Unit" = "Y",
    "Health_Status" = "",
    "Note" = "",
    "provider_sample_id" = "",
    "Sampling_Strategy" = ifelse(merged_df$prove_kategori == "P1_", 
                               "Sentinel surveillance (ARI)", 
                               ifelse(merged_df$pasient_status == "Inneliggende", 
                                      "Non-sentinel surveillance (hospital)", 
                                      ifelse(merged_df$prove_kategori == "P2_" & merged_df$pasient_status == "Poliklinisk", 
                                             "Non-sentinel surveillance (outpatient)", 
                                             ""))),
    "Sequencing_Technology" = Sequencing_Technology,
    "Assembly_Method" = Assembly_Method,
    "Sequencing_Strategy" = Sequencing_Strategy
    
  )

# Define the desired column order
desired_order <- c(
  "Isolate_Id",
  "Segment_Ids",
  "Isolate_Name",
  "Subtype",
  "Lineage",
  "Passage_History",
  "Location",
  "province",
  "sub_province",
  "Location_Additional_info",
  "Host",
  "Host_Additional_info",
  "Specimen_Source",
  "Sampling_Strategy",
  "Sequencing_Strategy",
  "Sequencing_Technology",
  "Assembly_Method",
  "Coverage",
  "Seq_Id (HA)",
  "Seq_Id (NA)",
  "Seq_Id (PB1)",
  "Seq_Id (PB2)",
  "Seq_Id (PA)",
  "Seq_Id (MP)",
  "Seq_Id (NS)",
  "Seq_Id (NP)",
  "Seq_Id (HE)",
  "Seq_Id (P3)",
  "Submitting_Sample_Id",
  "Authors",
  "Originating_Lab_Id",
  "Originating_Sample_Id",
  "Collection_Month",
  "Collection_Year",
  "Collection_Date",
  "Antigen_Character",
  "Adamantanes_Resistance_geno",
  "Oseltamivir_Resistance_geno",
  "Zanamivir_Resistance_geno",
  "Peramivir_Resistance_geno",
  "Other_Resistance_geno",
  "Adamantanes_Resistance_pheno",
  "Oseltamivir_Resistance_pheno",
  "Zanamivir_Resistance_pheno",
  "Peramivir_Resistance_pheno",
  "Other_Resistance_pheno",
  "Host_Age",
  "Host_Age_Unit",
  "Host_Gender",
  "Health_Status",
  "Note",
  "provider_sample_id"
)

rm(merged_df)

submission <- tmp %>%
  select(all_of(desired_order))

# Define the output file path and filename
output_dir <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/10-GISAID"
output_filename_excel <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".xlsx")
output_path_excel <- file.path(output_dir, output_filename_excel)

# Write the submission dataframe to an Excel file
#write.xlsx(tmp, output_path_excel, rownames = FALSE)

# Set the output file path and filename for CSV
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/10-GISAID"
output_filename_csv <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".csv")
output_path_csv <- file.path(output_dir_csv, output_filename_csv)

# Write the submission dataframe to a CSV file
write.csv(submission, output_path_csv, row.names = FALSE, fileEncoding = "UTF-8")

# Create the output filename for the FASTA file
output_filename_fasta <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".fasta")
output_path_fasta <- file.path(output_dir_csv, output_filename_fasta)

# Create the FASTA file
file_con <- file(output_path_fasta, open = "w") # Open the file in write mode

# Loop through each row in filtered_seq to create the FASTA entries and write to file
for (i in 1:nrow(filtered_seq)) {
  header <- paste(filtered_seq$experiment[i], filtered_seq$key[i], sep = "|")
  sequence <- filtered_seq$sequence[i]
  
  # Write the header and sequence to file
  cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
}

# Close the file connection
close(file_con)
