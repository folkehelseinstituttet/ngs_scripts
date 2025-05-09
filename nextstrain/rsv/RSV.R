# Assign the arguments to variables

library(writexl)
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
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF"
GISAIDnr <- 3869  # Converting directly to numeric

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")




# Proceed with data filtering and selection
rsvdb <- rsvdb %>%
  #filter(ngs_run_id == SID) %>%                      # Ensure SID is defined and matches the column
  #filter(ngs_sekvens_resultat != "") %>%             # Remove empty results
  filter(ngs_report == "" | is.na(ngs_report))  %>%             # Remove empty results
  filter(nc_id != "") 




# Now select the required columns
#fludb <- fludb %>% select("key", "ngs_sekvens_resultat", "pasient_fylke_nr", "pasient_alder", "prove_tatt", "tessy_variable", "pasient_kjonn", "prove_innsender_id", "pasient_fylke_name", "prove_kategori")
merged_df <- rsvdb %>% select("nc_id", "pasient_fylke_name", "ngs_clade", "prove_tatt", "ngs_coverage", "prove_innsender_navn", "prove_region", "prove_country", "ngs_clade", "ngs_coverage", "nc_qc_overall_score", "nc_qc_overall_status",
                              "nc_alignment_start", "nc_alignment_end","ngs_sekvens_resultat", "pasient_landsdel")

merged_df <- merged_df %>% filter(ngs_coverage > 0.6)

# Filter data for RSVA and RSVB
merged_df_rsva <- merged_df %>% filter(ngs_sekvens_resultat == "RSVA")
merged_df_rsvb <- merged_df %>% filter(ngs_sekvens_resultat == "RSVB")



################### FASTA FILE :

# Assuming merged_df is your original dataframe
tmp_rsva <- merged_df_rsva %>%
  transmute(
    accession = gsub("\\.", "_", nc_id),
    genbank_accession_rev = "",
    strain = nc_id,
    date = format(as.Date(prove_tatt), "%Y-%m-%d"),
    region = prove_region,
    country = prove_country,
    division = pasient_fylke_name,
    location = pasient_landsdel,
    host = "Human",
    date_submitted = "",
    sra_accession = "",
    abbr_authors = "",
    authors = "",
    institution = "",
    clade = ngs_clade,
    G_clade = "",
    qc.overallScore = nc_qc_overall_score,
    qc.overallStatus = nc_qc_overall_status,
    alignmentScore = "",
    alignmentStart = nc_alignment_start,
    alignmentEnd = nc_alignment_end,
    genome_coverage = ngs_coverage,
    G_coverage = "0.4",
    F_coverage = "0.4",  
    missing_data = 0
  )

tmp_rsvb <- merged_df_rsvb %>%
  transmute(
    accession = gsub("\\.", "_", nc_id),
    genbank_accession_rev = "",
    strain = nc_id,
    date = format(as.Date(prove_tatt), "%Y-%m-%d"),
    region = prove_region,
    country = prove_country,
    division = pasient_fylke_name,
    location = "",
    host = "Human",
    date_submitted = "",
    sra_accession = "",
    abbr_authors = "",
    authors = "",
    institution = "",
    clade = ngs_clade,
    G_clade = "",
    qc.overallScore = nc_qc_overall_score,
    qc.overallStatus = nc_qc_overall_status,
    alignmentScore = "",
    alignmentStart = nc_alignment_start,
    alignmentEnd = nc_alignment_end,
    genome_coverage = ngs_coverage,
    G_coverage = "0.4",
    F_coverage = "0.4",
    missing_data = 0
  )


# Define the desired column order
desired_order <- c(
  "accession",
  "genbank_accession_rev",
  "strain",
  "date",
  "region",
  "country",
  "division",
  "location",
  "host",
  "division",
  "date_submitted",
  "sra_accession",
  "abbr_authors",
  "authors",
  "institution",
  "clade",
  "G_clade",
  "qc.overallScore",
  "qc.overallStatus",
  "alignmentScore",
  "alignmentStart",
  "alignmentEnd",
  "genome_coverage",
  "G_coverage",
  "F_coverage",
  "missing_data"
)


submission_rsva <- tmp_rsva %>%
  select(all_of(desired_order))

submission_rsvb <- tmp_rsvb %>%
  select(all_of(desired_order))

# Function to write filtered FASTA file with nc_id as header
write_fasta <- function(output_path, filtered_data) {
  # Open the file in write mode
  file_con <- file(output_path, open = "w")
  
  # Loop through each row in the filtered data and write the FASTA entry
  for (i in 1:nrow(filtered_data)) {
    header <- paste(filtered_data$experiment[i], filtered_data$nc_id[i], sep = "|")  # Use nc_id instead of key
    
    # Remove "Genome|" from sequences if applicable
    if (filtered_data$experiment[i] == "Genome") {
      header <- gsub("^Genome\\|", "", header)
    }
    
    sequence <- filtered_data$sequence[i]
    cat(">", header, "\n", sequence, "\n", file = file_con, sep = "")
  }
  
  # Close the file connection
  close(file_con)
}

############## Write CSV, XLS & FASTA #################

# Define the output directory and filename for CSVs
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/11-Nextstrain"
today_date <- format(Sys.Date(), "%Y-%m-%d")
parent_dir <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))


# Create the parent directory if it doesn't exist
if (!dir.exists(parent_dir)) dir.create(parent_dir)

# Define the output directories for each type
output_dir_A <- file.path(parent_dir, "virus_RSV_A")
# Define the output directories for each type
output_dir_B <- file.path(parent_dir, "virus_RSV_B")


# Create directories if they don't exist
dir.create(output_dir_A, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir_B, recursive = TRUE, showWarnings = FALSE)




# Write the XLS files for each type
write_xlsx(submission_rsva, file.path(output_dir_A, "metadata.xls"))
# Write the TSV file for the dataframe
write.table(submission_rsva, file.path(output_dir_A, "metadata.tsv"), sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
# Write the XLS files for each type
write_xlsx(submission_rsvb, file.path(output_dir_B, "metadata.xls"))
# Write the TSV file for the dataframe
write.table(submission_rsvb, file.path(output_dir_B, "metadata.tsv"), sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)


# Add `nc_id` to `filtered_seq` by joining with `rsvdb` on `key`
filtered_seq <- filtered_seq %>%
  left_join(rsvdb %>% select(key, nc_id), by = "key")


# Filter `filtered_seq` based on `nc_id`
#filtered_seq <- filtered_seq %>% filter(nc_id %in% submission_id)
filtered_seq <- filtered_seq %>% filter(experiment == "Genome")


# Step 3: Define the output directory
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/RSV/11-Nextstrain"
today_date <- format(Sys.Date(), "%Y-%m-%d")
parent_dir <- file.path(output_dir_csv, paste0(today_date, "_Nextstrain_Build"))

# Create the parent directory if it doesn't exist
if (!dir.exists(parent_dir)) dir.create(parent_dir)


# Step 4: Define the output FASTA file 

output_fasta_A <- file.path(output_dir_A, "sequences.fasta")
output_fasta_B <- file.path(output_dir_B, "sequences.fasta")

write_fasta(output_fasta_A, filtered_seq)
write_fasta(output_fasta_B, filtered_seq)

