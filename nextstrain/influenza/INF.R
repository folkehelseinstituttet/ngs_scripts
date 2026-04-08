# ---------------- Driver script (complete, fixed) ----------------

suppressPackageStartupMessages({
  library(writexl)
  library(lubridate)
  library(tidyverse)
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
})

source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R")
source("N:/Virologi/Influensa/RARI/2526/BN FLU 25-26 Nextstrain.R")  # builds fludb, filtered_seq

# --- Robust date parser ------------------------------------------
parse_date_col <- function(x) {
  if (inherits(x, c("Date", "POSIXct", "POSIXlt"))) return(as.Date(x))
  
  if (is.numeric(x)) {
    return(as.Date(as.numeric(x), origin = "1970-01-01"))
  }
  
  if (is.character(x)) {
    y <- suppressWarnings(
      lubridate::parse_date_time(
        x,
        orders = c(
          "Ymd", "Y-m-d", "dmY", "dmy", "d.m.Y", "d/m/Y",
          "mdY", "mdy", "m/d/Y",
          "Ymd HMS", "Y-m-d H:M:S", "d.m.Y H:M:S", "d/m/Y H:M:S"
        ),
        tz = "UTC"
      )
    )
    return(as.Date(y))
  }
  
  suppressWarnings(as.Date(x))
}

# --- Rebuild county names from county number ---------------------
# This avoids all mojibake / encoding problems completely.
county_from_nr <- function(nr, fallback = NULL) {
  nr_chr <- trimws(as.character(nr))
  
  county_map <- c(
    "03" = "Oslo",
    "11" = "Rogaland",
    "15" = "M\u00F8re og Romsdal",
    "18" = "Nordland",
    "31" = "\u00D8stfold",
    "32" = "Akershus",
    "33" = "Buskerud",
    "34" = "Innlandet",
    "39" = "Vestfold",
    "40" = "Telemark",
    "42" = "Agder",
    "46" = "Vestland",
    "50" = "Tr\u00F8ndelag",
    "55" = "Troms",
    "56" = "Finnmark"
  )
  
  out <- unname(county_map[nr_chr])
  
  if (!is.null(fallback)) {
    fallback <- as.character(fallback)
    out[is.na(out) | out == "NA"] <- fallback[is.na(out) | out == "NA"]
  }
  
  out[is.na(out)] <- "Unknown"
  out
}

# ---------------- Metadata ---------------------------------------
passage   <- "Clinical Specimen"
host      <- "Human"
Location  <- "Norway"
sub_lab   <- "Norwegian Institute of Public Health, Department of Virology"
address   <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors   <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF"
GISAIDnr  <- 3869

# ---------------- Input checks -----------------------------------
if (!exists("fludb")) stop("Object 'fludb' was not created by sourced script.")
if (!exists("filtered_seq")) stop("Object 'filtered_seq' was not created by sourced script.")

required_fludb_cols <- c(
  "key", "ngs_sekvens_resultat", "pasient_fylke_nr", "pasient_alder",
  "prove_tatt", "pasient_kjnn", "prove_innsender_id", "pasient_fylke_name",
  "prove_kategori"
)

missing_fludb_cols <- setdiff(required_fludb_cols, names(fludb))
if (length(missing_fludb_cols) > 0) {
  stop("Missing required columns in fludb: ", paste(missing_fludb_cols, collapse = ", "))
}

required_filtered_cols <- c("key", "experiment", "sequence")
missing_filtered_cols <- setdiff(required_filtered_cols, names(filtered_seq))
if (length(missing_filtered_cols) > 0) {
  stop("Missing required columns in filtered_seq: ", paste(missing_filtered_cols, collapse = ", "))
}

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

if (!"Innsender nr" %in% names(Lab_ID)) {
  stop("Column 'Innsender nr' not found in Lab_ID file.")
}

if (!"GISAID_Nr" %in% names(Lab_ID)) {
  stop("Column 'GISAID_Nr' not found in Lab_ID file.")
}

# ---------------- Clean fludb ------------------------------------
fludb$prove_tatt <- parse_date_col(fludb$prove_tatt)

fludb <- fludb %>%
  filter(!is.na(ngs_sekvens_resultat), ngs_sekvens_resultat != "") %>%
  # filter(ngs_report == "" | is.na(ngs_report)) %>%
  filter(!(ngs_sekvens_resultat %in% c("NA", "N2", "N1"))) %>%
  select(all_of(required_fludb_cols)) %>%
  mutate(
    key = as.character(key),
    prove_innsender_id = trimws(as.character(prove_innsender_id)),
    pasient_fylke_nr = stringr::str_pad(as.character(pasient_fylke_nr), width = 2, side = "left", pad = "0"),
    pasient_fylke_name = county_from_nr(pasient_fylke_nr, pasient_fylke_name)
  )

# Clean join key in Lab_ID
Lab_ID <- Lab_ID %>%
  mutate(
    `Innsender nr` = trimws(as.character(as.integer(`Innsender nr`)))
  )

# Data cleaning and manipulation
fludb <- fludb %>%
  mutate(
    Original_Key = as.character(key),
    
    Subtype = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1")     ~ "H1N1",
      str_starts(ngs_sekvens_resultat, "A/H3N2")     ~ "H3N2",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "B",
      TRUE                                           ~ ""
    ),
    
    INFType = case_when(
      str_starts(ngs_sekvens_resultat, "A/") ~ "A",
      str_starts(ngs_sekvens_resultat, "B/") ~ "B",
      TRUE                                   ~ ""
    ),
    
    Lineage = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1")     ~ "pdm09",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "Victoria",
      TRUE                                           ~ ""
    ),
    
    Host_Gender = if_else(
      toupper(pasient_kjnn) %in% c("M", "F"),
      toupper(pasient_kjnn),
      NA_character_
    ),
    
    Year = lubridate::year(prove_tatt),
    age  = pasient_alder,
    Uniq_nr = sub("^[0-9]{4}", "", Original_Key),
    
    Isolate_Name = if_else(
      grepl("Ref", prove_kategori),
      Original_Key,
      paste(INFType, "Norway", Uniq_nr, Year, sep = "/")
    )
  )

# ---------------- Merge with Lab_ID -------------------------------
merged_df <- fludb %>%
  left_join(Lab_ID, by = c("prove_innsender_id" = "Innsender nr"))

merged_df$prove_tatt <- parse_date_col(merged_df$prove_tatt)

merged_df <- merged_df %>%
  mutate(
    GISAID_Nr = if_else(
      is.na(GISAID_Nr) | GISAID_Nr == "",
      as.character(GISAIDnr),
      as.character(GISAID_Nr)
    )
  )

################### FASTA / METADATA TABLE #########################
filtered_seq <- filtered_seq %>%
  mutate(
    key = as.character(key),
    experiment = as.character(experiment),
    sequence = as.character(sequence)
  )

segment_present <- function(seg) {
  merged_df$key %in% filtered_seq$key[filtered_seq$experiment == seg]
}

tmp <- merged_df %>%
  mutate(
    Isolate_Id                   = "",
    Segment_Ids                  = "",
    Passage_History              = passage,
    Host                         = host,
    Authors                      = if_else(grepl("Ref", prove_kategori), NA_character_, authors),
    Location                     = if_else(
      grepl("Ref", prove_kategori),
      NA_character_,
      paste0("Europe / Norway / ", pasient_fylke_name)
    ),
    province                     = pasient_fylke_name,
    sub_province                 = "",
    Location_Additional_info     = "",
    Host_Additional_info         = "",
    `Seq_Id (HA)`                = if_else(segment_present("HA"),  paste("HA",  key, sep = "|"), ""),
    `Seq_Id (NA)`                = if_else(segment_present("NA"),  paste("NA",  key, sep = "|"), ""),
    `Seq_Id (PB1)`               = if_else(segment_present("PB1"), paste("PB1", key, sep = "|"), ""),
    `Seq_Id (PB2)`               = if_else(segment_present("PB2"), paste("PB2", key, sep = "|"), ""),
    `Seq_Id (PA)`                = if_else(segment_present("PA"),  paste("PA",  key, sep = "|"), ""),
    `Seq_Id (MP)`                = if_else(segment_present("MP"),  paste("MP",  key, sep = "|"), ""),
    `Seq_Id (NS)`                = if_else(segment_present("NS"),  paste("NS",  key, sep = "|"), ""),
    `Seq_Id (NP)`                = if_else(segment_present("NP"),  paste("NP",  key, sep = "|"), ""),
    `Seq_Id (HE)`                = "",
    `Seq_Id (P3)`                = "",
    Submitting_Sample_Id         = as.character(key),
    Originating_Lab              = as.character(GISAID_Nr),
    Originating_Sample_Id        = "",
    Collection_Month             = lubridate::month(prove_tatt),
    Collection_Year              = lubridate::year(prove_tatt),
    Collection_Date              = format(as.Date(prove_tatt), "%Y-%m-%d"),
    Antigen_Character            = "",
    Adamantanes_Resistance_geno  = "",
    Oseltamivir_Resistance_geno  = "",
    Zanamivir_Resistance_geno    = "",
    Peramivir_Resistance_geno    = "",
    Other_Resistance_geno        = "",
    Adamantanes_Resistance_pheno = "",
    Oseltamivir_Resistance_pheno = "",
    Zanamivir_Resistance_pheno   = "",
    Peramivir_Resistance_pheno   = "",
    Other_Resistance_pheno       = "",
    Host_Age                     = pasient_alder,
    Host_Age_Unit                = "Y",
    Health_Status                = "",
    Note                         = "",
    PMID                         = "",
    Submission_Date              = ""
  )

# ---------------- Add Isolate_Name to filtered_seq ----------------
filtered_seq <- filtered_seq %>%
  select(-any_of("Isolate_Name")) %>%
  left_join(tmp %>% select(key, Isolate_Name), by = "key")

# ---------------- Submission subsets ------------------------------
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
  filter(str_starts(ngs_sekvens_resultat, "A/H1N1"))

tmp_h3 <- tmp %>%
  filter(str_starts(ngs_sekvens_resultat, "A/H3N2"))

tmp_vic <- tmp %>%
  filter(str_starts(ngs_sekvens_resultat, "B/Victoria"))

submission_h1  <- tmp_h1  %>% select(all_of(desired_order))
submission_h3  <- tmp_h3  %>% select(all_of(desired_order))
submission_vic <- tmp_vic %>% select(all_of(desired_order))

for (nm in c("submission_h1","submission_h3","submission_vic")) assign(nm, get(nm) %>% mutate(across(where(is.character), ~ gsub("MÃ¸re og Romsdal", paste0("M", intToUtf8(248), "re og Romsdal"), gsub("TrÃ¸ndelag", paste0("Tr", intToUtf8(248), "ndelag"), gsub("Ãstfold", paste0(intToUtf8(216), "stfold"), .x, fixed = TRUE), fixed = TRUE), fixed = TRUE))), envir = .GlobalEnv)


# ---------------- FASTA writer ------------------------------------
write_fasta <- function(output_path, filtered_data) {
  con <- file(output_path, open = "w")
  on.exit(close(con), add = TRUE)
  
  if (nrow(filtered_data) == 0) {
    message("No sequences to write: ", output_path)
    return(invisible(NULL))
  }
  
  for (i in seq_len(nrow(filtered_data))) {
    header <- paste(filtered_data$experiment[i], filtered_data$Isolate_Name[i], sep = "|")
    
    if (filtered_data$experiment[i] == "HA") {
      header <- sub("^HA\\|", "", header)
    } else if (filtered_data$experiment[i] == "NA") {
      header <- sub("^NA\\|", "", header)
    }
    
    sequence <- filtered_data$sequence[i]
    cat(">", header, "\n", sequence, "\n", file = con, sep = "")
  }
  
  invisible(NULL)
}

############## Write XLSX & FASTA ##################################
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain"
today_date     <- format(Sys.Date(), "%Y-%m-%d")
parent_dir     <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))

dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)

output_dir_h1  <- file.path(parent_dir, "H1")
output_dir_h3  <- file.path(parent_dir, "H3")
output_dir_vic <- file.path(parent_dir, "VIC")

dir.create(output_dir_h1,  recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_h3,  recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_vic, recursive = TRUE, showWarnings = FALSE)

write_xlsx(submission_h1,  file.path(output_dir_h1,  "metadata.xlsx"))
write_xlsx(submission_h3,  file.path(output_dir_h3,  "metadata.xlsx"))
write_xlsx(submission_vic, file.path(output_dir_vic, "metadata.xlsx"))

# Filter by Isolate_Name per group
filtered_h1  <- filtered_seq %>% filter(Isolate_Name %in% submission_h1$Isolate_Name)
filtered_h3  <- filtered_seq %>% filter(Isolate_Name %in% submission_h3$Isolate_Name)
filtered_vic <- filtered_seq %>% filter(Isolate_Name %in% submission_vic$Isolate_Name)

# Split by experiment
filtered_h1_ha  <- filtered_h1  %>% filter(experiment == "HA")
filtered_h1_na  <- filtered_h1  %>% filter(experiment == "NA")
filtered_h3_ha  <- filtered_h3  %>% filter(experiment == "HA")
filtered_h3_na  <- filtered_h3  %>% filter(experiment == "NA")
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

# ---------------- Copy to flu_nextstrain dir ----------------------
flu_nextstrain_dir <- "N:/Virologi/NGS/tmp/flu_nextstrain"
dir.create(flu_nextstrain_dir, recursive = TRUE, showWarnings = FALSE)

copy_folder <- function(source_dir, target_dir) {
  if (!dir.exists(source_dir)) {
    cat("Source folder does not exist:", source_dir, "\n")
    return(invisible(FALSE))
  }
  
  dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
  
  files <- list.files(source_dir, full.names = TRUE, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  
  if (length(files) == 0) {
    cat("No files found in:", source_dir, "\n")
    return(invisible(TRUE))
  }
  
  for (src in files) {
    if (dir.exists(src)) next
    
    rel_path <- substring(
      normalizePath(src, winslash = "/", mustWork = FALSE),
      nchar(normalizePath(source_dir, winslash = "/", mustWork = FALSE)) + 2
    )
    
    dest <- file.path(target_dir, rel_path)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(src, dest, overwrite = TRUE)
  }
  
  cat("Copied folder:", source_dir, "to", target_dir, "\n")
  invisible(TRUE)
}

copy_folder(output_dir_h1,  file.path(flu_nextstrain_dir, "H1"))
copy_folder(output_dir_h3,  file.path(flu_nextstrain_dir, "H3"))
copy_folder(output_dir_vic, file.path(flu_nextstrain_dir, "VIC"))

cat("All folders and their contents have been successfully copied to", flu_nextstrain_dir, "\n")
# ---------------- End driver script -------------------------------
