# Assign the arguments to variables

library(writexl)
source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/BN FLU 24-25 Nextstrain.R")


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
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF"
GISAIDnr <- 3869  # Converting directly to numeric

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

source("N:/Virologi/Influensa/RARI/BN FLU 24-25 Nextstrain.R")


# Proceed with data filtering and selection
fludb <- fludb %>%
  filter(ngs_sekvens_resultat != "") %>%             # Remove empty results
  filter(ngs_report == "" | is.na(ngs_report)) %>%             # Remove empty results
  filter(!(ngs_sekvens_resultat %in% c("NA", "N2", "N1")))  # Keep rows that are NOT NA, N2, or N1



# Now select the required columns
fludb <- fludb %>% select("key", "ngs_sekvens_resultat", "pasient_fylke_nr", "pasient_alder", "prove_tatt", "tessy_variable", "pasient_kjonn", "prove_innsender_id", "pasient_fylke_name", "prove_kategori")

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
    Isolate_Name = key  # Creating Isolate_Name
  )

# Merging with Lab_ID
merged_df <- merge(fludb, Lab_ID, by.x = "prove_innsender_id", by.y = "Innsender nr", all.x = TRUE)

# Replace NA and non-numeric values in GISAID_Nr column
merged_df$GISAID_Nr <- ifelse(is.na(merged_df$GISAID_Nr) | is.na(merged_df$GISAID_Nr), GISAIDnr, merged_df$GISAID_Nr)

#rm(fludb)



################### FASTA FILE :
tmp <- merged_df %>%
  add_column(
    "Isolate_Id" = "",
    "Segment_Ids" = "",
    "Passage_History" = passage,
    "Host" = host,
    "Authors" = ifelse(grepl("Ref", merged_df$prove_kategori), NA, authors),
    "Location" = ifelse(grepl("Ref", merged_df$prove_kategori), NA, paste0("Europe / Norway / ",merged_df$pasient_fylke_name)),
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
    "Originating_Lab" = merged_df$GISAID_Nr,
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
    "PMID" = "",
    "Submission_Date" = ""
    
  )

# Define the desired column order
desired_order <- c(
  "Isolate_Name",
  "Isolate_Id",
  "Passage_History",
  "Location",
  "Authors",
  "Originating_Lab",
  "Collection_Date",
  "Submission_Date"
)


tmp_h1 <- tmp %>%
  filter(ngs_sekvens_resultat == "A/H1N1")

tmp_h3 <- tmp %>%
  filter(ngs_sekvens_resultat == "A/H3N2")

tmp_vic <- tmp %>%
  filter(ngs_sekvens_resultat == "B/Victoria")

rm(merged_df)

submission_h1 <- tmp_h1 %>%
  select(all_of(desired_order))

submission_h3 <- tmp_h3 %>%
  select(all_of(desired_order))

submission_vic <- tmp_vic %>%
  select(all_of(desired_order))


# Function to write filtered FASTA files and remove HA| or NA| from headers
write_fasta <- function(output_path, filtered_data) {
  # Open the file in write mode
  file_con <- file(output_path, open = "w")
  
  # Loop through each row in the filtered data and write the FASTA entry
  for (i in 1:nrow(filtered_data)) {
    header <- paste(filtered_data$experiment[i], filtered_data$key[i], sep = "|")
    
    # Remove "HA|" from HA sequences and "NA|" from NA sequences
    if (filtered_data$experiment[i] == "HA") {
      header <- gsub("^HA\\|", "", header)
    } else if (filtered_data$experiment[i] == "NA") {
      header <- gsub("^NA\\|", "", header)
    }
    
    sequence <- filtered_data$sequence[i]
    cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
  }
  
  # Close the file connection
  close(file_con)
}

############## Write CSV, XLS & FASTA #################

# Define the output directory and filename for CSVs
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain"
today_date <- format(Sys.Date(), "%Y-%m-%d")
parent_dir <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))

# Create the parent directory if it doesn't exist
if (!dir.exists(parent_dir)) dir.create(parent_dir)

# Define the output directories for each type
output_dir_h1 <- file.path(parent_dir, "H1")
output_dir_h3 <- file.path(parent_dir, "H3")
output_dir_vic <- file.path(parent_dir, "VIC")

# Create directories if they don't exist
dir.create(output_dir_h1, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_h3, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_vic, recursive = TRUE, showWarnings = FALSE)

# Write the XLS files for each type
write_xlsx(submission_h1, file.path(output_dir_h1, "metadata.xls"))
write_xlsx(submission_h3, file.path(output_dir_h3, "metadata.xls"))
write_xlsx(submission_vic, file.path(output_dir_vic, "metadata.xls"))

# Step 1: Filter `filtered_seq` by Isolate_Name for each group (H1, H3, VIC)
filtered_h1 <- filtered_seq %>% filter(key %in% submission_h1$Isolate_Name)
filtered_h3 <- filtered_seq %>% filter(key %in% submission_h3$Isolate_Name)
filtered_vic <- filtered_seq %>% filter(key %in% submission_vic$Isolate_Name)

# Step 2: Filter HA and NA sequences for each group

# For H1
filtered_h1_ha <- filtered_h1 %>% filter(experiment == "HA")
filtered_h1_na <- filtered_h1 %>% filter(experiment == "NA")

# For H3
filtered_h3_ha <- filtered_h3 %>% filter(experiment == "HA")
filtered_h3_na <- filtered_h3 %>% filter(experiment == "NA")

# For VIC
filtered_vic_ha <- filtered_vic %>% filter(experiment == "HA")
filtered_vic_na <- filtered_vic %>% filter(experiment == "NA")

# Step 3: Define the output directories for H1, H3, and VIC
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain"
today_date <- format(Sys.Date(), "%Y-%m-%d")
parent_dir <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))

# Create the parent directory if it doesn't exist
if (!dir.exists(parent_dir)) dir.create(parent_dir)

# Define the output directories for each group (H1, H3, VIC)
output_dir_h1 <- file.path(parent_dir, "H1")
output_dir_h3 <- file.path(parent_dir, "H3")
output_dir_vic <- file.path(parent_dir, "VIC")

# Create directories if they don't exist
dir.create(output_dir_h1, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_h3, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_vic, recursive = TRUE, showWarnings = FALSE)

# Step 4: Define the output FASTA file paths for HA and NA for each group

# For H1
output_fasta_h1_ha <- file.path(output_dir_h1, "raw_sequences_ha.fasta")
output_fasta_h1_na <- file.path(output_dir_h1, "raw_sequences_na.fasta")

# For H3
output_fasta_h3_ha <- file.path(output_dir_h3, "raw_sequences_ha.fasta")
output_fasta_h3_na <- file.path(output_dir_h3, "raw_sequences_na.fasta")

# For VIC
output_fasta_vic_ha <- file.path(output_dir_vic, "raw_sequences_ha.fasta")
output_fasta_vic_na <- file.path(output_dir_vic, "raw_sequences_na.fasta")

# Step 5: Write the HA and NA sequences to FASTA files for each group

# Write H1 FASTA files
write_fasta(output_fasta_h1_ha, filtered_h1_ha)
write_fasta(output_fasta_h1_na, filtered_h1_na)

# Write H3 FASTA files
write_fasta(output_fasta_h3_ha, filtered_h3_ha)
write_fasta(output_fasta_h3_na, filtered_h3_na)

# Write VIC FASTA files
write_fasta(output_fasta_vic_ha, filtered_vic_ha)
write_fasta(output_fasta_vic_na, filtered_vic_na)
