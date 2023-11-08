library(tidyverse)

# Download sequencing technology metadata from Gisaid

gisaid <- read_tsv("/home/jonr/Downloads/gisaid_hcov-19_2023_11_08_16.tsv")

BN <- gisaid %>% 
  # Remove Ahus
  filter(str_detect(`Virus name`, "Ahus", negate = TRUE)) %>% 
  select(`Virus name`, `Accession ID`) %>% 
  # Re-create the Key
  add_column("nr" = 25) %>% 
  separate(`Virus name`, into = c(NA, NA, "Key", "year"), sep = "/", remove = F) %>% 
  # If there is a "-" in the Key
  separate(Key, into = c("Key", "version"), sep = "-") %>% 
  mutate(year = str_sub(year, 3, 4)) %>% 
  # Drop rows with NA
  filter(!is.na(Key)) %>% 
  # Left pad the Key with zeroes to a total of 5 digits
  mutate("Key" = str_pad(Key, width = 5, side = c("left"), pad = "0")) %>% 
  # Add the version number back, but with "_"
  unite("Key", c(Key, version), sep = "_", na.rm = TRUE) %>% 
  unite("tmp", c(nr, year, Key), sep = "") %>% 
  add_column("Platform" = NA) %>% 
  # Select final columns
  select("Key" = tmp, "gisaid_epi_isl" = `Accession ID`, Platform, "GISAID_ISOLAT_NAVN" = `Virus name`)

# Write file
write.csv(BN, 
          file = paste0("/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_files/", format(Sys.Date(), format = "%Y.%m.%d"), "_BN_import.csv"),
          quote = TRUE,
          row.names = FALSE)
