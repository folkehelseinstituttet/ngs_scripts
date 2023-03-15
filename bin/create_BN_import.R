#!/usr/bin/env Rscript

# Load packages
library(tidyverse)

# NB: This script is based on the input from the cli3 gisaid uploader
to_BN_rest <- read_tsv(file = "/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_files/2023-03-15_submission.log", col_names = FALSE) %>% 
  # Remove already existing submissions - deal with these later
  filter(str_detect(X1, "error", negate = TRUE)) %>% 
  # Remove summary text
  filter(str_detect(X1, "submissions", negate = TRUE)) %>%
  # Remove much junk text and isolate the Key and EPI_ISL
  separate(X1, into = c("tmp1", "tmp2"), sep = ";") %>%
  separate(tmp1, into = c(NA, "tmp4"), sep = "Norway/") %>% 
  separate(tmp4, into = c("Key", "year"), sep = "/") %>% 
  # If there is a "-" in the Key
  separate(Key, into = c("Key", "version"), sep = "-") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  mutate(gisaid_epi_isl = str_sub(tmp2, 1, -3)) %>%
  # Remove leading white space
  mutate(gisaid_epi_isl = str_remove(gisaid_epi_isl, "^ ")) %>% 
  # Drop rows with NA
  filter(!is.na(Key)) %>% 
  # Re-create BN Key
  add_column("nr" = 25) %>% 
  # Left pad the Key with zeroes to a total of 5 digits
  mutate("Key" = str_pad(Key, width = 5, side = c("left"), pad = "0")) %>% 
  # Add the version number back, but with "_"
  unite("Key", c(Key, version), sep = "-", na.rm = TRUE) %>% 
  unite("tmp", c(nr, year, Key), sep = "") %>% 
  add_column("Platform" = NA) %>% 
  # Select final columns
  select("Key" = tmp, gisaid_epi_isl, Platform)

write.csv(to_BN_rest, 
          file = "/home/jonr/2023.03.15_3_BN_batch_import.csv",
          quote = TRUE,
          row.names = FALSE)

# Import failed/existing submissions from the cli3 uploader

tmp <- read_tsv(file = "/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_files/2023-03-15_submission.log", col_names = FALSE) %>% 
  # Remove already existing submissions - deal with these later
  filter(str_detect(X1, "exists", negate = FALSE)) %>% 
  # Remove summary text
  filter(str_detect(X1, "submissions", negate = TRUE)) %>%
  # Remove much junk text and isolate the Key and EPI_ISL
  separate(X1, into = c("tmp1", NA, "tmp2"), sep = ";") %>%
  separate(tmp1, into = c(NA, "tmp4"), sep = "Norway/") %>% 
  separate(tmp4, into = c("Key", "year"), sep = "/") %>%
  # If there is a "-" in the Key
  separate(Key, into = c("Key", "version"), sep = "-") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  mutate(gisaid_epi_isl = str_sub(tmp2, 1, -3)) %>%
  mutate(gisaid_epi_isl = str_extract(tmp2, "EPI_ISL_[0-9]+")) %>% 
  select(-tmp2) %>% 
  # Drop rows with NA
  filter(!is.na(Key)) %>% 
  # Re-create BN Key
  add_column("nr" = 25) %>% 
  # Left pad the Key with zeroes to a total of 5 digits
  mutate("Key" = str_pad(Key, width = 5, side = c("left"), pad = "0")) %>%
  # Add the version number back, but with "_"
  unite("Key", c(Key, version), sep = "-", na.rm = TRUE) %>% 
  unite("tmp", c(nr, year, Key), sep = "") %>% 
  add_column("Platform" = NA) %>% 
  # Select final columns
  select("Key" = tmp, gisaid_epi_isl, Platform)

write.csv(tmp, 
          file = "/home/jonr/2023.03.15_5_BN_batch_import.csv",
          quote = TRUE,
          row.names = FALSE)


# Import samples with frameshift to BN
# Loop through all frameshift results
Frameshift <- list.files(path = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon/",
           pattern = "frameshift_results.csv$",
           recursive = TRUE,
           full.names = TRUE) %>% 
  read_csv(col_names = FALSE) %>% 
  # Extract samples with frameshift
  filter(X5 == "NO") %>% 
  # Recreate BN Key
  separate(X1, into = c(NA, NA, "Key", "year"), sep = "/") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  add_column("nr" = 25) %>% 
  # Left pad the Key with zeroes to a total of 5 digits
  mutate("Key" = str_pad(Key, width = 5, side = c("left"), pad = "0")) %>% 
  unite("tmp", c(nr, year, Key), sep = "") %>% 
  add_column("Platform" = NA) %>% 
  add_column("gisaid_epi_isl" = "Frameshift") %>% 
  # Select final columns
  select("Key" = tmp, gisaid_epi_isl, Platform)

write.csv(Frameshift, 
          file = paste0("/home/jonr/", Sys.Date(), "_BN_Frameshift_import.csv"),
          quote = TRUE,
          row.names = FALSE)


# Old code that takes a tsv file downloaded from the Gisaid web:
# Download from Gisaid Sequencing Technology metadata

# Read the metadata file
gisaid_md <- read_tsv(file = "/home/jonr/Downloads/gisaid_hcov-19_2022_02_01_09.tsv")

to_BN_OUS <- gisaid_md %>% 
  select(`Virus name`, `Accession ID`, `Sequencing technology`) %>% 
  filter(str_detect(`Virus name`, "OUS")) %>% 
  separate(`Virus name`, into = c(NA, NA, "Key", NA), sep = "/") %>% 
  select(Key, 
         "gisaid_epi_isl" = `Accession ID`,
         "Platform" = `Sequencing technology`)

write.csv(to_BN_OUS, 
          file = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon/BN-import-filer/2022.02.01_MIK_batch_import.csv",
          quote = TRUE,
          row.names = FALSE)

to_BN_rest <- gisaid_md %>% 
  # Remove Ahus samples
  filter(str_detect(`Virus name`, "Ahus", negate = TRUE)) %>% 
  select(`Virus name`, `Accession ID`, `Sequencing technology`) %>% 
  # Remove OUS samples
  filter(str_detect(`Virus name`, "OUS", negate = TRUE)) %>% 
  separate(`Virus name`, into = c(NA, NA, "Key", "year"), sep = "/") %>%
  # Left pad the Key with zeroes to a total of 5 digits
  mutate("Key" = str_pad(Key, width = 5, side = c("left"), pad = "0")) %>% 
  # Replace "-" with "_" in Key
  mutate(Key = str_replace(Key, "-", "_")) %>% 
  add_column("nr" = 25) %>% 
  mutate("year" = str_sub(year, 3, 4)) %>% 
  unite("tmp", c(nr, year, Key), sep = "") %>% 
  select("Key" = tmp,
         "gisaid_epi_isl" = `Accession ID`,
         "Platform" = `Sequencing technology`)

write.csv(to_BN_rest, 
          file = "/mnt/N/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon/BN-import-filer/2022.02.01_BN_batch_import.csv",
          quote = TRUE,
          row.names = FALSE)