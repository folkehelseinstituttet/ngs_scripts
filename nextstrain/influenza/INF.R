# ---------------- Driver script (complete, corrected) ----------------

# Assign the arguments to variables
library(writexl)
source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/2526/BN FLU 25-26 Nextstrain.R")  # builds fludb, filtered_seq

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

# --- NEW: robust date parser (minimal, safe) -------------------------
parse_date_col <- function(x) {
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return(as.Date(x))
  if (is.numeric(x)) return(as.Date(as.numeric(x), origin = "1970-01-01"))
  if (is.character(x)) {
    y <- suppressWarnings(lubridate::parse_date_time(
      x,
      orders = c(
        "Ymd","Y-m-d","dmY","dmy","d.m.Y","d/m/Y",
        "mdY","mdy","m/d/Y",
        "Ymd HMS","Y-m-d H:M:S","d.m.Y H:M:S","d/m/Y H:M:S"
      ),
      tz = "UTC"
    ))
    return(as.Date(y))
  }
  # fallback
  suppressWarnings(as.Date(x))
}

# ---------------- Metadata ------------------------------------------
passage <- "Clinical Specimen"
host <- "Human"
Location <- "Norway"
sub_lab <- "Norwegian Institute of Public Health, Department of Virology"
address <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF"
GISAIDnr <- 3869  # Converting directly to numeric

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

# --- NEW: ensure dates are parsed BEFORE using month()/year() --------
# fludb comes from the sourced script
fludb$prove_tatt <- parse_date_col(fludb$prove_tatt)

# Proceed with data filtering and selection
fludb <- fludb %>%
  filter(ngs_sekvens_resultat != "") %>%               # Remove empty results
  filter(ngs_report == "" | is.na(ngs_report)) %>%     # Keep empty/NA reports
  filter(!(ngs_sekvens_resultat %in% c("NA", "N2", "N1")))  # Drop NA/N2/N1 “results”

# Now select the required columns
fludb <- fludb %>% select(
  "key", "ngs_sekvens_resultat", "pasient_fylke_nr", "pasient_alder",
  "prove_tatt", "pasient_kjnn", "prove_innsender_id", "pasient_fylke_name",
  "prove_kategori"
)

# Data cleaning and manipulation
fludb <- fludb %>%
  mutate(
    Subtype = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "H1N1",
      str_starts(ngs_sekvens_resultat, "A/H3N2") ~ "H3N2",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "B",
      TRUE ~ ""
    ),
    INFType = if_else(str_starts(ngs_sekvens_resultat, "A/"), "A", "B"),
    Lineage = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "pdm09",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "Victoria",
      TRUE ~ ""
    ),
    Host_Gender = if_else(toupper(pasient_kjnn) %in% c("M", "F"), toupper(pasient_kjnn), NA_character_),
    Year = lubridate::year(prove_tatt),     # <- works because we parsed dates
    age = pasient_alder,
    Uniq_nr = str_sub(key, start = 5, end = 9),
    Isolate_Name = ifelse(
      grepl("Ref", prove_kategori),
      key,
      paste(INFType, "Norway", Uniq_nr, Year, sep = "/")
    )
  )

# Merging with Lab_ID
merged_df <- merge(fludb, Lab_ID, by.x = "prove_innsender_id", by.y = "Innsender nr", all.x = TRUE)

# --- NEW: also ensure merged_df date column is Date ------------------
merged_df$prove_tatt <- parse_date_col(merged_df$prove_tatt)

# Replace NA and non-numeric values in GISAID_Nr column
merged_df$GISAID_Nr <- ifelse(is.na(merged_df$GISAID_Nr) | is.na(merged_df$GISAID_Nr), GISAIDnr, merged_df$GISAID_Nr)

################### FASTA FILE : ######################################
tmp <- merged_df %>%
  add_column(
    "Isolate_Id" = "",
    "Segment_Ids" = "",
    "Passage_History" = passage,
    "Host" = host,
    "Authors" = ifelse(grepl("Ref", merged_df$prove_kategori), NA, authors),
    "Location" = ifelse(grepl("Ref", merged_df$prove_kategori), NA, paste0("Europe / Norway / ", merged_df$pasient_fylke_name)),
    "province" = merged_df$pasient_fylke_name,
    "sub_province" = "",
    "Location_Additional_info" = "",
    "Host_Additional_info" = "",
    "Seq_Id (HA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "HA"], paste("HA", merged_df$key, sep = "|"), ""),
    "Seq_Id (NA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NA"], paste("NA", merged_df$key, sep = "|"), ""),
    "Seq_Id (PB1)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB1"], paste("PB1", merged_df$key, sep = "|"), ""),
    "Seq_Id (PB2)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB2"], paste("PB2", merged_df$key, sep = "|"), ""),
    "Seq_Id (PA)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PA"], paste("PA", merged_df$key, sep = "|"), ""),
    "Seq_Id (MP)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "MP"], paste("MP", merged_df$key, sep = "|"), ""),
    "Seq_Id (NS)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NS"], paste("NS", merged_df$key, sep = "|"), ""),
    "Seq_Id (NP)" = ifelse(merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NP"], paste("NP", merged_df$key, sep = "|"), ""),
    "Seq_Id (HE)" = "",
    "Seq_Id (P3)" = "",
    "Submitting_Sample_Id" = merged_df$key,
    "Originating_Lab" = merged_df$GISAID_Nr,
    "Originating_Sample_Id" = "",
    "Collection_Month" = lubridate::month(merged_df$prove_tatt),     # <- safe
    "Collection_Year"  = lubridate::year(merged_df$prove_tatt),      # <- safe
    "Collection_Date"  = format(as.Date(merged_df$prove_tatt), "%Y-%m-%d"),
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

# Add Isolate_Name to filtered_seq
filtered_seq <- filtered_seq %>%
  dplyr::left_join(tmp %>% select(key, Isolate_Name), by = "key")

# Desired column order
desired_order <- c(
  "Isolate_Name", "Isolate_Id", "Passage_History", "Location",
  "Authors", "Originating_Lab", "Collection_Date", "Submission_Date"
)

tmp_h1  <- tmp %>% filter(ngs_sekvens_resultat == "A/H1N1")
tmp_h3  <- tmp %>% filter(ngs_sekvens_resultat == "A/H3N2")
tmp_vic <- tmp %>% filter(ngs_sekvens_resultat == "B/Victoria")

rm(merged_df)

submission_h1  <- tmp_h1  %>% select(all_of(desired_order))
submission_h3  <- tmp_h3  %>% select(all_of(desired_order))
submission_vic <- tmp_vic %>% select(all_of(desired_order))

# Function to write filtered FASTA files and use Isolate_Name in headers
write_fasta <- function(output_path, filtered_data) {
  file_con <- file(output_path, open = "w")
  for (i in 1:nrow(filtered_data)) {
    header <- paste(filtered_data$experiment[i], filtered_data$Isolate_Name[i], sep = "|")
    if (filtered_data$experiment[i] == "HA") header <- gsub("^HA\\|", "", header)
    else if (filtered_data$experiment[i] == "NA") header <- gsub("^NA\\|", "", header)
    sequence <- filtered_data$sequence[i]
    cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
  }
  close(file_con)
}

############## Write CSV, XLS & FASTA #################
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain"
today_date <- format(Sys.Date(), "%Y-%m-%d")
parent_dir <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))
if (!dir.exists(parent_dir)) dir.create(parent_dir)

output_dir_h1  <- file.path(parent_dir, "H1")
output_dir_h3  <- file.path(parent_dir, "H3")
output_dir_vic <- file.path(parent_dir, "VIC")
dir.create(output_dir_h1,  recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_h3,  recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_vic, recursive = TRUE, showWarnings = FALSE)

write_xlsx(submission_h1,  file.path(output_dir_h1,  "metadata.xls"))
write_xlsx(submission_h3,  file.path(output_dir_h3,  "metadata.xls"))
write_xlsx(submission_vic, file.path(output_dir_vic, "metadata.xls"))

# Filter by Isolate_Name per group
filtered_h1  <- filtered_seq %>% filter(Isolate_Name %in% submission_h1$Isolate_Name)
filtered_h3  <- filtered_seq %>% filter(Isolate_Name %in% submission_h3$Isolate_Name)
filtered_vic <- filtered_seq %>% filter(Isolate_Name %in% submission_vic$Isolate_Name)

# Split by experiment
filtered_h1_ha  <- filtered_h1 %>% filter(experiment == "HA")
filtered_h1_na  <- filtered_h1 %>% filter(experiment == "NA")
filtered_h3_ha  <- filtered_h3 %>% filter(experiment == "HA")
filtered_h3_na  <- filtered_h3 %>% filter(experiment == "NA")
filtered_vic_ha <- filtered_vic %>% filter(experiment == "HA")
filtered_vic_na <- filtered_vic %>% filter(experiment == "NA")

# Output FASTA paths
output_fasta_h1_ha  <- file.path(output_dir_h1,  "raw_sequences_ha.fasta")
output_fasta_h1_na  <- file.path(output_dir_h1,  "raw_sequences_na.fasta")
output_fasta_h3_ha  <- file.path(output_dir_h3,  "raw_sequences_ha.fasta")
output_fasta_h3_na  <- file.path(output_dir_h3,  "raw_sequences_na.fasta")
output_fasta_vic_ha <- file.path(output_dir_vic, "raw_sequences_ha.fasta")
output_fasta_vic_na <- file.path(output_dir_vic, "raw_sequences_na.fasta")

# Write FASTA
write_fasta(output_fasta_h1_ha,  filtered_h1_ha)
write_fasta(output_fasta_h1_na,  filtered_h1_na)
write_fasta(output_fasta_h3_ha,  filtered_h3_ha)
write_fasta(output_fasta_h3_na,  filtered_h3_na)
write_fasta(output_fasta_vic_ha, filtered_vic_ha)
write_fasta(output_fasta_vic_na, filtered_vic_na)

# Copy to flu_nextstrain dir
flu_nextstrain_dir <- "N:/Virologi/NGS/tmp/flu_nextstrain"
if (!dir.exists(flu_nextstrain_dir)) dir.create(flu_nextstrain_dir, recursive = TRUE, showWarnings = FALSE)

copy_folder <- function(source_dir, target_dir) {
  if (dir.exists(source_dir)) {
    if (!dir.exists(target_dir)) dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
    files <- list.files(source_dir, full.names = TRUE, recursive = TRUE)
    for (file in files) {
      rel_path <- gsub(paste0("^", normalizePath(source_dir, winslash = "/")), "", normalizePath(file, winslash = "/"))
      target_file <- file.path(target_dir, rel_path)
      if (dir.exists(file)) {
        dir.create(target_file, recursive = TRUE, showWarnings = FALSE)
      } else {
        file.copy(file, target_file, overwrite = TRUE)
      }
    }
    cat("Copied folder:", source_dir, "to", target_dir, "\n")
  } else {
    cat("Source folder does not exist:", source_dir, "\n")
  }
}

copy_folder(output_dir_h1,  file.path(flu_nextstrain_dir, "H1"))
copy_folder(output_dir_h3,  file.path(flu_nextstrain_dir, "H3"))
copy_folder(output_dir_vic, file.path(flu_nextstrain_dir, "VIC"))

cat("All folders and their contents have been successfully copied to", flu_nextstrain_dir, "\n")
# ---------------- End driver script ---------------------------------
