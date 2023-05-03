#!/usr/bin/env Rscript

# Load packages
library(tidyverse)
library(optparse)

# Read input arguments
args = commandArgs(trailingOnly=TRUE)

if (length(args) < 2) {
  stop("Usage: create_BN_import.R <submission_log_file> <frameshift_result_file>", call. = FALSE)
}

log <- args[1]
fs  <- args[2]

# NB: This script is based on the input from the cli3 gisaid uploader
OUS <- read_tsv(file = log, col_names = FALSE) %>% 
  # Remove already existing submissions - deal with these later
  filter(str_detect(X1, "error", negate = TRUE)) %>% 
  # Remove summary text
  filter(str_detect(X1, "submissions", negate = TRUE)) %>%
  # Remove much junk text and isolate the Key and EPI_ISL
  separate(X1, into = c("tmp1", "tmp2"), sep = ";") %>%
  separate(tmp1, into = c(NA, "tmp4"), sep = "Norway/", remove = F) %>% 
  separate(tmp4, into = c("Key", "year"), sep = "/") %>% 
  mutate(gisaid_epi_isl = str_extract(tmp2, "EPI_ISL_[0-9]+")) %>% 
  # Drop rows with NA
  filter(!is.na(Key)) %>% 
  # Extract OUS
  filter(str_detect(Key, "OUS")) %>% 
  add_column("Platform" = NA) %>% 
  # Extract the Virus name
  separate(tmp1, into = c(NA, NA, NA, NA, NA, NA, NA, "v_name"), sep = "\"") %>% 
  # Select final columns
  select(Key, gisaid_epi_isl, Platform, "GISAID_ISOLAT_NAVN" = v_name)

BN_rest <- read_tsv(file = log, col_names = FALSE) %>% 
  # Remove already existing submissions - deal with these later
  filter(str_detect(X1, "error", negate = TRUE)) %>% 
  # Remove summary text
  filter(str_detect(X1, "submissions", negate = TRUE)) %>%
  # Remove much junk text and isolate the Key and EPI_ISL
  separate(X1, into = c("tmp1", "tmp2"), sep = ";") %>%
  separate(tmp1, into = c(NA, "tmp4"), sep = "Norway/", remove = F) %>% 
  separate(tmp4, into = c("Key", "year"), sep = "/") %>% 
  # If there is a "-" in the Key
  separate(Key, into = c("Key", "version"), sep = "-") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  mutate(gisaid_epi_isl = str_extract(tmp2, "EPI_ISL_[0-9]+")) %>% 
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
  # Extract the Virus name
  separate(tmp1, into = c(NA, NA, NA, NA, NA, NA, NA, "v_name"), sep = "\"") %>% 
  # Select final columns
  select("Key" = tmp, gisaid_epi_isl, Platform, "GISAID_ISOLAT_NAVN" = v_name)

# Import failed/existing submissions from the cli3 uploader
fail_ext <- read_tsv(file = log, col_names = FALSE) %>% 
  # Remove already existing submissions - deal with these later
  filter(str_detect(X1, "exists", negate = FALSE)) %>% 
  # Remove summary text
  filter(str_detect(X1, "submissions", negate = TRUE)) %>%
  # Remove much junk text and isolate the Key and EPI_ISL
  separate(X1, into = c("tmp1", "tmp2"), sep = ";", remove = F) %>%
  separate(tmp1, into = c(NA, "tmp4"), sep = "Norway/", remove = F) %>% 
  separate(tmp4, into = c("Key", "year"), sep = "/", remove = F) %>% 
  # If there is a "-" in the Key
  separate(Key, into = c("Key", "version"), sep = "-") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  mutate(gisaid_epi_isl = str_extract(X1, "EPI_ISL_[0-9]+")) %>% 
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
  # Extract the Virus name
  separate(tmp1, into = c(NA, NA, NA, NA, NA, NA, NA, "v_name"), sep = "\"") %>% 
  # Select final columns
  select("Key" = tmp, gisaid_epi_isl, Platform, "GISAID_ISOLAT_NAVN" = v_name)

# Import samples with frameshift to BN
frameshift <- read_csv(fs, col_names = F) %>% 
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
  select("Key" = tmp, gisaid_epi_isl, Platform) %>% 
  distinct() %>% 
  add_column("GISAID_ISOLAT_NAVN" = NA)

# Combine everything
df <- bind_rows(
  OUS,
  BN_rest,
  fail_ext,
  frameshift
)

# Write file
write.csv(df, 
          file = paste0(format(Sys.Date(), format = "%Y.%m.%d"), "_BN_import.csv"),
          quote = TRUE,
          row.names = FALSE)
