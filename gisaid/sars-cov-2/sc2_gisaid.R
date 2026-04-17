# Capture command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Assign the arguments to variables
SID <- "SAR026"
submitter <- "RasmusKRiis"

source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/2526/BN SC2 25-26.R")

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

# Repair common UTF-8/latin1 mojibake from upstream DB (e.g. "MÃ¸re" -> "Møre")
fix_mojibake_utf8 <- function(x) {
  x <- as.character(x)
  needs_fix <- !is.na(x) & grepl("Ã|Â|â", x, useBytes = TRUE)
  out <- x

  out[needs_fix] <- vapply(x[needs_fix], function(s) {
    codepoints <- utf8ToInt(s)
    if (length(codepoints) == 0L || any(codepoints > 255L)) return(s)

    repaired <- tryCatch(rawToChar(as.raw(codepoints)), error = function(e) s)
    validated <- iconv(repaired, from = "UTF-8", to = "UTF-8", sub = "")

    if (is.na(validated)) s else validated
  }, FUN.VALUE = character(1))

  out
}

# Extract robust isolate number from key
# Preferred: last 6 digits
# Fallback: remove first 4 digits if possible
extract_unique_number <- function(x) {
  x <- as.character(x)

  out <- ifelse(
    str_detect(x, "[0-9]{6}$"),
    str_extract(x, "[0-9]{6}$"),
    NA_character_
  )

  fallback_idx <- is.na(out) & !is.na(x) & str_detect(x, "^[0-9]{5,}$")
  out[fallback_idx] <- str_remove(x[fallback_idx], "^[0-9]{4}")

  out
}

# Define metadata
passage <- "Clinical Specimen"
host <- "Human"
Location <- "Norway"
sub_lab <- "Norwegian Institute of Public Health, Department of Virology"
address <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF"
GISAIDnr <- 3869
Sequencing_Technology <- "Oxford Nanopore - GridION"
Assembly_Method <- "IRMA CoV-minion-long-reads"
Sequencing_Strategy <- "Targeted-amplification"

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

lab_lookup_table <- tribble(
  ~`Lab code`, ~`Lab`, ~`Lab_address`,
  "FHI-SMLV", "Norwegian Institute of Public Health, Department of Virology", "P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  "Sykehuset Østfold HF Kalnes", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MEDMIKR", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "MOLLEBYEN-LS", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MIKR", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MIKRGENINF", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "Sykehuset Østfold HF", "Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "AHUS-MIKR", "Akershus University Hospital, Department for Microbiology and Infectious Disease Control", "P.O.Box 1000, N-1478 Loerenskog, Norway",
  "ULLEV-MIKRVIR", "Oslo University Hospital, Department of Microbiology", "P.O.Box 4956 Nydalen, N-0424 Oslo, Norway",
  "BANKGÅRDEN LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "BJØLSEN LEGESENTER AS", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FAGERNES LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FORSAND LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FURST-MIKRSER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GILDESKÅL LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GJERDRUM LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GRATANGEN LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GRINI MØLLE LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "HELSETORGET LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "HØVDINGGÅRDEN LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "ILADALEN LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LEGENE I GRØNLANDSLEIRET", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LEGENE PÅ BRYGGEN", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LILLESAND LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "OVERHALLA LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "PRESTFOSS LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "RØSTAD LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SIO HELSE BLINDERN", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SJØGATA MEDICAL", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SOLVANG LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STABEKK LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STANGE LEGESENTER", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STAVERN LEGEKONTOR", "Furst Medical Laboratory", "Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LILLEH-MIKR", "Innlandet Hospital Trust, Division Lillehammer, Department for Medical Microbiology", "P.O.Box 990, N-2629 Lillehammer, Norway",
  "DRAM-MIKR", "Medical Microbiology Unit, Department for Laboratory Medicine, Drammen Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  "TONSBERG-MIKR", "Vestfold Hospital, Toensberg, Department of Microbiology", "P.O.Box 2168, N-3103 Toensberg, Norway",
  "SKIEN-MIKR", "Unilabs Laboratory Medicine", "Leirvollen 19, N-3736 Skien, Norway",
  "KRSAND-MIKR", "Hospital of Southern Norway - Kristiansand, Department of Medical Microbiology", "P.O.Box 416 Lundsiden, N-4604 Kristiansand, Norway",
  "STAVANG-MIKR", "Dept. of Medical Microbiology, Stavanger University Hospital, Helse Stavanger HF", "P.O.Box 8100, N-4068 Stavanger, Norway",
  "HAUKE-MIKR", "Haukeland University Hospital, Dept. of Microbiology", "P.O.Box 1400, N-5021 Bergen, Norway",
  "HAUKE-MIKRVIR", "Haukeland University Hospital, Dept. of Microbiology", "P.O.Box 1400, N-5021 Bergen, Norway",
  "HAUGESU-MIKR", "Haugesund Hospital, laboratory for Medical Microbiology", "P.O.Box 2170, N-5504 Haugesund, Norway",
  "FORDE-MIKR", "Foerde Hospital, Department of Microbiology", "P.O.Box 1000, N-6807 Foerde, Norway",
  "MOLDE-MIKR", "Department of Medical Microbiology - section Molde, Molde Hospital", "Parkveien 84, N-6407 Molde, Norway",
  "STOLAV-MIKR", "Department of Medical Microbiology, St. Olavs hospital", "P.O.box 3250 Torgarden, N-7006 Trondheim, Norway",
  "LEVANG-MIKR", "Levanger Hospital, laboratory for Medical Microbiology", "P.O.box 333, N-7601 Levanger, Norway",
  "BODO-MIKR", "Nordland Hospital - Bodo, Laboratory Department, Molecular Biology Unit", "P.O.Box 1480, N-8092 Bodo, Norway",
  "TROMSO-MIKR", "University Hospital of Northern Norway, Department for Microbiology and Infectious Disease Control", "P.O.Box 56, N-9038 Tromsoe, Norway",
  "BODO-MIKR", NA, NA,
  "AALESUND-MIKR", "Department of medical microbiology, section Aalesund, Aalesund Hospital", "N-6026 Aalesund, Norway",
  "BYGDELEGENE-RAKKESTAD", NA, NA,
  "ETNE LEGEKONTOR", NA, NA,
  "BAERUM-MIKR", "Department of Medical Microbiology, Baerum Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  "UNILABS-MIKR-SKIEN", "Telemark Hospital Trust – Skien, Dept. of Medical Microbiology", "P.O.Box 2900 Kjørbekk, N-3710 Skien"
) %>%
  mutate(`Lab code` = as.character(`Lab code`))

# Proceed with data filtering and selection
sarsdb <- sarsdb %>%
  filter(ngs_run_id == SID) %>%
  filter(is.na(gisaid_kommentar) | gisaid_kommentar == "") %>%
  filter(nc_coverage >= 0.75)

# Use join to add the labs and addresses
sarsdb <- sarsdb %>%
  left_join(
    lab_lookup_table,
    by = c("prove_innsender_navn" = "Lab code")
  )

# Now select the required columns
sarsdb <- sarsdb %>%
  select(
    key,
    prove_tatt,
    pasient_fylke_name,
    pasient_kjnn,
    prove_material,
    pasient_alder,
    prove_kategori,
    pasient_fylke_nr,
    prove_innsender_id,
    pasient_status,
    ngs_depth,
    ngs_primer_vers,
    nc_coverage,
    Lab,
    Lab_address
  )

# Normalize county names before they are used in output fields
sarsdb$pasient_fylke_name <- fix_mojibake_utf8(sarsdb$pasient_fylke_name)

# Data cleaning and manipulation
sarsdb <- sarsdb %>%
  mutate(
    Host_Gender = if_else(
      toupper(pasient_kjnn) %in% c("M", "F"),
      toupper(pasient_kjnn),
      NA_character_
    ),
    Year = year(as.Date(prove_tatt)),
    age = pasient_alder,
    Uniq_nr = extract_unique_number(key),
    Isolate_Name = if_else(
      !is.na(Uniq_nr) & !is.na(Year),
      paste("hCoV-19", "Norway", Uniq_nr, Year, sep = "/"),
      paste("hCoV-19", "Norway", as.character(key), Year, sep = "/")
    ),
    Specimen_Source = case_when(
      str_starts(prove_material, "NAPHSEKR") ~ "nasopharyngeal swab",
      str_starts(prove_material, "SEKRET") ~ "",
      TRUE ~ ""
    ),
    Primer_vers = case_when(
      str_starts(ngs_primer_vers, "VM.3") ~ "Midnight version 3",
      TRUE ~ NA_character_
    )
  )

# Optional safety check
bad_keys <- sarsdb %>% filter(is.na(Uniq_nr))
if (nrow(bad_keys) > 0) {
  warning("Some keys did not produce a valid Uniq_nr. Falling back to full key in Isolate_Name for those rows.")
}

# Merge submitter/lab ID info
merged_df <- merge(
  sarsdb,
  Lab_ID,
  by.x = "prove_innsender_id",
  by.y = "Innsender nr",
  all.x = TRUE
)

# Replace missing GISAID_Nr
merged_df$GISAID_Nr <- ifelse(
  is.na(merged_df$GISAID_Nr),
  GISAIDnr,
  merged_df$GISAID_Nr
)

################### SUBMISSION
tmp <- merged_df %>%
  mutate(
    submitter = submitter,
    fn = "tmp",
    covv_virus_name = Isolate_Name,
    covv_type = "betacoronavirus",
    covv_passage = passage,
    covv_collection_date = format(as.Date(prove_tatt), "%Y-%m-%d"),
    covv_location = paste("Europe", "Norway", pasient_fylke_name, sep = "/"),
    covv_host = "Human",
    covv_gender = Host_Gender,
    covv_patient_age = "Unknown",
    covv_patient_status = "Unknown",
    covv_specimen = "Unknown",
    covv_seq_technology = if_else(
      is.na(Primer_vers) | Primer_vers == "",
      Sequencing_Technology,
      paste(Sequencing_Technology, Primer_vers, sep = " - ")
    ),
    covv_assembly_method = Assembly_Method,
    covv_orig_lab = Lab,
    covv_orig_lab_addr = Lab_address,
    covv_subm_lab = "Norwegian Institute of Public Health, Department of Virology",
    covv_subm_lab_addr = "P.O.Box 222 Skoyen, 0213 Oslo, Norway",
    covv_authors = authors,
    covv_outbreak = "Unknown",
    covv_add_host_info = "Unknown",
    covv_add_location = "Unknown",
    covv_provider_sample_id = "Unknown",
    covv_last_vaccinated = "Unknown",
    covv_treatment = "Unknown",
    covv_coverage = ngs_depth,
    covv_sampling_strategy = case_when(
      prove_kategori == "P1_" ~ "Sentinel surveillance (ARI)",
      pasient_status == "Inneliggende" ~ "Non-sentinel surveillance (hospital)",
      prove_kategori == "P2_" & pasient_status == "Poliklinisk" ~ "Non-sentinel surveillance (outpatient)",
      TRUE ~ ""
    )
  )

covv_cols <- c(
  "submitter",
  "fn",
  "covv_virus_name",
  "covv_type",
  "covv_passage",
  "covv_collection_date",
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
  "covv_outbreak",
  "covv_add_host_info",
  "covv_add_location",
  "covv_provider_sample_id",
  "covv_last_vaccinated",
  "covv_treatment",
  "covv_coverage",
  "covv_sampling_strategy"
)

desired_order <- intersect(covv_cols, names(tmp))
submission <- tmp %>% dplyr::select(dplyr::all_of(desired_order))

# Define the output file path and filename
output_dir <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon"
output_filename_excel <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".xlsx")
output_path_excel <- file.path(output_dir, output_filename_excel)

# Write the submission dataframe to an Excel file
# write.xlsx(submission, output_path_excel, rownames = FALSE)

# Set the output file path and filename for CSV
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon"
output_filename_csv <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".csv")
output_path_csv <- file.path(output_dir_csv, output_filename_csv)

# Write the submission dataframe to a CSV file
write.csv(submission, output_path_csv, row.names = FALSE, fileEncoding = "UTF-8")

# Create the output filename for the FASTA file
output_filename_fasta <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".fasta")
output_path_fasta <- file.path(output_dir_csv, output_filename_fasta)

# --- Build name map and write FASTA with covv_virus_name headers ---

# 1) Map key -> covv_virus_name
name_map <- tmp %>%
  dplyr::select(key, covv_virus_name) %>%
  dplyr::distinct()

# 2) Attach names to filtered_seq
fasta_df <- filtered_seq %>%
  dplyr::select(key, sequence) %>%
  dplyr::left_join(name_map, by = "key")

# 3) Sanity check: any missing names?
missing_names <- fasta_df %>% dplyr::filter(is.na(covv_virus_name))
if (nrow(missing_names) > 0) {
  warning(sprintf(
    "Missing covv_virus_name for %d sequences. Falling back to key for those headers.",
    nrow(missing_names)
  ))
  fasta_df <- fasta_df %>%
    dplyr::mutate(covv_virus_name = dplyr::coalesce(covv_virus_name, as.character(key)))
}

# 4) Write FASTA using covv_virus_name as header
file_con <- file(output_path_fasta, open = "w")

for (i in seq_len(nrow(fasta_df))) {
  header <- as.character(fasta_df$covv_virus_name[i])
  sequence <- gsub("\\s+", "", as.character(fasta_df$sequence[i]))
  cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
}

close(file_con)
