# For testing. Should take input argument
min_date <- "2024-01-01"
submitter <- "jonbra"

Sys.setlocale("LC_CTYPE", "nb_NO.UTF-8")  # For Norwegian Bokmål

# Load packages
library(odbc)
library(tidyverse)
library(stringr)
library(lubridate)
library(base64enc)
library(seqinr)

# Connect to BN
con <- dbConnect(odbc(),
                 Driver = "SQL Server",
                 Server = "sql-bn-covid19",
                 Database = "BN_Covid19")

# Get all data
BN <- tbl(con, "ENTRYTABLE") %>% 
  # Keep all columns
  rename("Dekning_Artic" = PROSENTDEKNING_GENOM,
         "Dekning_Swift" = COVERAGE_BREADTH_SWIFT,
         "Dekning_Nano" = DEKNING_NANOPORE,
         "Dekning_Eksterne" = COVERAGE_BREATH_EKSTERNE) %>% 
  # Collect will actually retrieve the data and store it as a local tibble
  collect()

# Filter BN and collect samples for submission

# Initial filtering and cleaning
tmp <- BN %>%
  # Remove previously submitted samples, keep samples with Frameshift for re-analysis
  filter(str_detect(GISAID_EPI_ISL, "^EPI", negate = TRUE) | GISAID_EPI_ISL == "Frameshift") %>% 
  # Fjerne evt positiv controll
  filter(str_detect(KEY, "pos", negate = TRUE)) %>% 
  # Fjerne hvis manglende INNSENDER
  mutate_at("INNSENDER", ~na_if(., '')) %>% # first convert empty strings to NA
  filter(!is.na(INNSENDER)) %>%
  # Endre Trøndelag til Trondelag
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "Tr\xf8ndelag", "Trondelag")) %>%
  # Endre Møre og Romsdal
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "M\xf8re", "More")) %>%
  # Endre Sør
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "S\xf8r", "Sor")) %>%
  # Change "Ukjent" in FYLKENAVN to NA
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "Ukjent")) %>%
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "ukjent")) %>%
  # Fix date format
  mutate("PROVE_TATT" = ymd(PROVE_TATT)) %>% 
  # Drop samples without collection date
  filter(!is.na(PROVE_TATT)) %>%
  mutate(Dekning_Swift = as.numeric(Dekning_Swift),
         Dekning_Artic = as.numeric(Dekning_Artic),
         Dekning_Nano = as.numeric(Dekning_Nano)) %>% 
  # Add column stating whether coverage is sufficient or not
  mutate("COV_OK" = case_when(
    Dekning_Swift >= 94 ~ "YES",
    Dekning_Swift < 94  ~ "NO",
    Dekning_Artic >= 94 ~ "YES",
    Dekning_Artic < 94  ~ "NO",
    Dekning_Nano >= 94  ~ "YES",
    Dekning_Nano < 94   ~ "NO"
  )) %>%
  # Only keep sequences with sufficient coverage
  filter(COV_OK == "YES") %>% 
  # Keep sequences sucessfully called with pangolin
  filter(!is.na(PANGOLIN_NOM)) %>%
  filter(str_detect(PANGOLIN_NOM, "konklu", negate = TRUE)) %>%
  filter(str_detect(PANGOLIN_NOM, "komment", negate = TRUE)) %>%
  # Replace , with . and convert to numeric
  mutate(COVERAGE_DEPTH_SWIFT = str_replace(COVERAGE_DEPTH_SWIFT, ",", "."),
         COVARAGE_DEPTH_NANO = str_replace(COVARAGE_DEPTH_NANO, ",", ".")) %>% 
  mutate(COVERAGE_DEPTH_SWIFT = as.numeric(COVERAGE_DEPTH_SWIFT),
         COVARAGE_DEPTH_NANO = as.numeric(COVARAGE_DEPTH_NANO)) %>% 
  # Keep only necessary columns
  select(KEY,
         SEQUENCEID_NANO29,
         SEQUENCEID_SWIFT,
         SEKV_OPPSETT_NANOPORE,
         SEKV_OPPSETT_SWIFT7,
         SAMPLE_CATEGORY,
         COVERAGE_DEPTH_SWIFT,
         RES_CDC_INFB_CT,
         RES_CDC_INFA_RX,
         COVARAGE_DEPTH_NANO,
         PROVE_TATT,
         FYLKENAVN,
         INNSENDER,
         MELDT_SMITTESPORING,
         P)

# Keep samples taken after min_date
tmp <- tmp %>% filter(PROVE_TATT >= min_date)

## Create metadata

# Convert empty strings to NA
tmp <- tmp %>% 
  mutate_at("SEKV_OPPSETT_SWIFT7", ~na_if(., '')) %>% 
  mutate_at("SAMPLE_CATEGORY", ~na_if(., '')) %>% 
  mutate_at("SEKV_OPPSETT_NANOPORE", ~na_if(., '')) 

# Gather all samples that should be submitted and keep relevant info
# Adding a "code" column used to distinguish between Artic Illumina, Nanopore, NSC, etc. 
# Adding a "SETUP" column that contains the name for the sequencing "oppsett"
try(rm(df))
df <- tibble()
pb <- txtProgressBar(min = 1, max = nrow(tmp))
for (i in 1:nrow(tmp)) {
  setTxtProgressBar(pb, i)
  try(rm(dummy))
  # Check if there is not NA in SEKV_OPPSETT_SWIFT7 - i.e. this is an NSC sample
  if (!is.na(tmp$SEKV_OPPSETT_SWIFT7[i])) {
    # Check if FHI sample
    if (str_detect(tmp$SEKV_OPPSETT_SWIFT7[i], "FHI") | str_detect(tmp$SEKV_OPPSETT_SWIFT7[i], "EXT")) {
      dummy <- tmp[i,] %>% 
        # Create common columns for looping through later
        mutate(SEARCH_COLUMN = SEQUENCEID_SWIFT) %>%
        rename("COVERAGE" = COVERAGE_DEPTH_SWIFT) %>% 
        mutate(SETUP = SEKV_OPPSETT_SWIFT7) %>%
        # Create a column to join with "code" later
        add_column("code" = "FHI")
    # Check if MIK sample
    } else if (grepl("MIK", tmp$SEKV_OPPSETT_SWIFT7[i])) { # MIK samples
      dummy <- tmp[i,] %>% 
        # Create common columns for looping through later
        mutate(SEARCH_COLUMN = SEQUENCEID_SWIFT) %>%
        rename("COVERAGE" = COVERAGE_DEPTH_SWIFT) %>% 
        mutate(SETUP = SEKV_OPPSETT_SWIFT7) %>% 
        # Create a column to join with "code" later
        add_column("code" = "MIK")
    }
  # Then check if this is a sample sequenced internally with Artic and Illumina
  } else if (!is.na(tmp$SAMPLE_CATEGORY[i])) { # Artic_Illumina sample
    dummy <- tmp[i,] %>% 
      # Create common columns for looping through later
      mutate(SEARCH_COLUMN = RES_CDC_INFB_CT) %>%
      rename("COVERAGE" = RES_CDC_INFA_RX) %>% 
      mutate(SETUP = SAMPLE_CATEGORY) %>% 
      # Create a column to join with "code" later
      add_column("code" = "Artic_Ill")
  # Then check if this is a sample sequenced internally with Artic and Nanopore
  } else if (!is.na(tmp$SEKV_OPPSETT_NANOPORE[i])) { # Artic_Nanopore sample
    dummy <- tmp[i,] %>% 
      # Create common columns for looping through later
      mutate(SEARCH_COLUMN = SEQUENCEID_NANO29) %>%
      rename("COVERAGE" = COVARAGE_DEPTH_NANO) %>% 
      mutate(SETUP = SEKV_OPPSETT_NANOPORE) %>% 
      # Create a column to join with "code" later
      add_column("code" = "Artic_Nano")
  } 
  try(df <- bind_rows(df, dummy))
}

# Keep only sequence IDs with SC2 - i.e. the new format
df <- df %>% 
  filter(str_detect(SEARCH_COLUMN, "SC2")) %>% 
  # Endre underscore til bindestrek
  mutate(SEARCH_COLUMN = str_replace(SEARCH_COLUMN, "_", "-")) %>% 
  distinct()

# Further filtering
df_2 <- df %>% 
  # Remove failed or inconclusive samples
  filter(str_detect(SEARCH_COLUMN, "ailed", negate = TRUE)) %>% 
  filter(str_detect(SEARCH_COLUMN, "nkonklusiv", negate = TRUE)) %>% 
  # Lage kolonne for "year"
  separate(PROVE_TATT, into = c("Year", NA, NA), sep = "-", remove = FALSE) %>% 
  # Add info on sentinel sample (Fyrtårn)
  mutate("covv_sampling_strategy" = case_when(
    P == "1" ~ "Sentinel surveillance (ARI)",
    P != "1" ~ "Unknown"
  )
  )

# Modify the KEY to create Virus name
# This has code to deal with MIK (Ullevål) samples separately
try(rm(df_3))
df_3 <- tibble()
pb <- txtProgressBar(min = 1, max = nrow(df_2))
for (i in 1:nrow(df_2)) {
  setTxtProgressBar(pb, i)
  if (str_detect(df_2$SETUP[i], "MIK")) {
    dummy <- df_2[i,] %>% 
      # For OUS bruke hele KEY som stammenr
      mutate("Uniq_nr" = str_sub(KEY, start = 1, end = -1))
  } else {
    dummy <- df_2[i,] %>% 
      # Trekke ut sifrene fra 5 og til det siste fra BN KEY
      mutate("Uniq_nr" = str_sub(KEY, start = 5, end = -1)) %>%
      # Fjerne ledende nuller fra stammenavnet
      mutate("Uniq_nr" = str_remove(Uniq_nr, "^0+"))
  }
  df_3 <- bind_rows(df_3, dummy)
}

df_4 <- df_3 %>% 
  # Legge til kolonner med fast informasjon for å lage "Virus name" senere
  add_column("Separator" = "/",
             "GISAID_prefix" = "hCoV-19/",
             "Country" = "Norway/",
             "Continent" = "Europe/") %>%
  # Make "Virus name" column
  unite("covv_virus_name", c(GISAID_prefix, Country, Uniq_nr, Separator, Year), sep = "", remove = FALSE) %>%
  # Replace "_" with "-" in virus name
  mutate("covv_virus_name" = str_replace(covv_virus_name, "_", "-")) %>% 
  # Lage Location-kolonne
  unite("covv_location", c(Continent, Country, FYLKENAVN), sep = "", remove = FALSE) %>%
  # Legge til faste kolonner
  add_column("submitter" = submitter,
             "fn" = "tmp",
             "covv_type" = "betacoronavirus",
             "covv_passage" = "original",
             "covv_host" = "Human",
             "covv_gender" = "Unknown",
             "covv_patient_age" = "Unknown",
             "covv_patient_status" = "Unknown",
             "covv_specimen" = "Unknown",
             "covv_subm_sample_id" = "Unknown",
             "covv_outbreak" = "Unknown",
             "covv_add_host_info" = "Unknown",
             "covv_add_location" = "Unknown",
             "covv_provider_sample_id" = "Unknown",
             "covv_last_vaccinated" = "Unknown",
             "covv_treatment" = "Unknown")

# Add sequencing technology, addresses and authors

# Set originating labs and addresses --------------------------------------
lab_lookup_table <- tribble(
  ~`Lab code`, ~`Lab`, ~`Lab address`,
  0,	"Norwegian Institute of Public Health, Department of Virology",	"P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  1,	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  2,	"Akershus University Hospital, Department for Microbiology and Infectious Disease Control",	"P.O.Box 1000, N-1478 Loerenskog, Norway",
  3,	"Oslo University Hospital, Department of Microbiology",	"P.O.Box 4956 Nydalen, N-0424 Oslo, Norway",
  4,	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  5,	"Innlandet Hospital Trust, Division Lillehammer, Department for Medical Microbiology", "P.O.Box 990, N-2629 Lillehammer, Norway",
  6,	"Medical Microbiology Unit, Department for Laboratory Medicine, Drammen Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  7,	"Vestfold Hospital, Toensberg, Department of Microbiology",	"P.O.Box 2168, N-3103 Toensberg, Norway",
  8,	"Unilabs Laboratory Medicine", "Leirvollen 19, N-3736 Skien, Norway",
  9, NA, NA,
  10,	"Hospital of Southern Norway - Kristiansand, Department of Medical Microbiology",	"P.O.Box 416 Lundsiden, N-4604 Kristiansand, Norway",
  11,	"Dept. of Medical Microbiology, Stavanger University Hospital, Helse Stavanger HF", "P.O.Box 8100, N-4068 Stavanger, Norway",
  12,	"Haukeland University Hospital, Dept. of Microbiology",	"P.O.Box 1400, N-5021 Bergen, Norway",
  13,	"Haugesund Hospital, laboratory for Medical Microbiology", "P.O.Box 2170, N-5504 Haugesund, Norway",
  14,	"Foerde Hospital, Department of Microbiology", "P.O.Box 1000, N-6807 Foerde, Norway",
  15,	"Department of Medical Microbiology - section Molde, Molde Hospital",	"Parkveien 84, N-6407 Molde, Norway",
  16,	"Department of Medical Microbiology, St. Olavs hospital",	"P.O.box 3250 Torgarden, N-7006 Trondheim, Norway",
  17,	"Levanger Hospital, laboratory for Medical Microbiology", "P.O.box 333, N-7601 Levanger, Norway",
  18,	"Nordland Hospital - Bodo, Laboratory Department, Molecular Biology Unit", "P.O.Box 1480, N-8092 Bodo, Norway",
  19,	"University Hospital of Northern Norway, Department for Microbiology and Infectious Disease Control",	"P.O.Box 56, N-9038 Tromsoe, Norway",
  20, "Norwegian Institute of Public Health, Department of Virology",	"P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  21,	NA, NA,
  22,	"Department of medical microbiology, section Aalesund, Aalesund Hospital", "N-6026 Aalesund, Norway",
  23,	NA, NA,
  24, "Department of Medical Microbiology, Baerum Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  25,	"Telemark Hospital Trust – Skien, Dept. of Medical Microbiology",	"P.O.Box 2900 Kjørbekk, N-3710 Skien",
  26,	"Unilabs Laboratory Medicine", "Silurveien 2 B, N-0380 Oslo, Norway",
  27,	"Oslo Helse", "Hegdehaugsveien 36, 0352 Oslo"
) %>%
  mutate(`Lab code` = as.character(`Lab code`))

# Use join to add the labs and addresses
df_4 <- df_4 %>% 
  left_join(lab_lookup_table,
            by = c("INNSENDER" = "Lab code")) 


# Add author information and sequencing technology

# Set seq tech and authors ------------------------------------------------
seq_tech_authors_lookup_table <- tribble(
  ~`code`, ~`seq_tech`, ~`assembly`, ~`authors`,
  "FHI",	"Illumina Swift Amplicon SARS-CoV-2 protocol at Norwegian Sequencing Centre",	"Assembly by reference based mapping using Bowtie2 with iVar majority rules consensus", "Kathrine Stene-Johansen, Andreas Rohringer, Kamilla Heddeland Instefjord, Hilde Elshaug, Garcia Llorente Ignacio, Jon Bråte, Engebretsen Serina Beate, Pedersen Benedikte Nevjen, Debech Nadia, Atiya R Ali, Marie Paulsen Madsen, Rasmus Riis Kopperud, Hilde Vollan, Karoline Bragstad, Olav Hungnes",
  "MIK",	"Illumina Swift Amplicon SARS-CoV-2 protocol at Norwegian Sequencing Centre", "Assembly by reference based mapping using Bowtie2 with iVar majority rules consensus", "Mona Holberg-Petersen, Lise Andresen, Cathrine Fladeby, Mariann Nilsen, Teodora Plamenova Ribarska, Pål Marius Bjørnstad, Gregor D. Gilfillan, Arvind Yegambaram Meenakshi Sundaram, Kathrine Stene-Johansen, Kamilla Heddeland Instefjord, Hilde Elshaug, Garcia Llorente Ignacio, Jon Bråte, Pedersen Benedikte Nevjen, Line Victoria Moen, Rasmus Riis Kopperud, Hilde Vollan, Olav Hungnes, Karoline Bragstad",
  "Artic_Ill",	"Illumina MiSeq, modified ARTIC protocol with V4.1 primers",	"Assembly by reference based mapping using Tanoti with iVar majority rules consensus", "Kathrine Stene-Johansen, Andreas Rohringer, Kamilla Heddeland Instefjord, Hilde Elshaug, Garcia Llorente Ignacio, Jon Bråte, Engebretsen Serina Beate, Pedersen Benedikte Nevjen, Line Victoria Moen, Debech Nadia, Atiya R Ali, Marie Paulsen Madsen, Rasmus Riis Kopperud, Hilde Vollan, Karoline Bragstad, Olav Hungnes",
  "Artic_Nano",	"Nanopore GridIon, Artic V4.1 protocol modified",	"Assembly by reference based mapping using the Artic Nanopore protocol with medaka", "Kathrine Stene-Johansen, Andreas Rohringer, Kamilla Heddeland Instefjord, Hilde Elshaug, Garcia Llorente Ignacio, Jon Bråte, Engebretsen Serina Beate, Pedersen Benedikte Nevjen, Atiya R Ali, Marie Paulsen Madsen, Rasmus Riis Kopperud, Karoline Bragstad, Olav Hungnes"
)

# Use join to add seq tech and authors
df_4 <- left_join(df_4, seq_tech_authors_lookup_table, by = "code") %>% 
  # Add submitting lab and address
  add_column(
    "covv_subm_lab"      = "Norwegian Institute of Public Health, Department of Virology",
    "covv_subm_lab_addr" = "P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  )

# Beholde endelige kolonner og rekkefølge
# Keep some columns for finding fasta sequences later
metadata_raw <- df_4 %>% 
  select("submitter",
         "fn",
         "covv_virus_name",
         "covv_type",
         "covv_passage",
         "covv_collection_date" = PROVE_TATT,
         "covv_location",
         "covv_host",
         "covv_gender",
         "covv_patient_age",
         "covv_patient_status",
         "covv_specimen",
         "covv_seq_technology"  = "seq_tech",
         "covv_assembly_method" = "assembly",
         "covv_orig_lab"        = "Lab",
         "covv_orig_lab_addr"   = "Lab address",
         "covv_subm_lab",
         "covv_subm_lab_addr",
         "covv_authors"         = "authors",
         "covv_subm_sample_id",
         "covv_outbreak",
         "covv_add_host_info",
         "covv_add_location",
         "covv_provider_sample_id",
         "covv_last_vaccinated",
         "covv_treatment",
         "covv_coverage"        = COVERAGE,
         "covv_sampling_strategy",
         "KEY",
         "SEARCH_COLUMN",
         "code",
         SETUP)

# Change name of primers used for Nanopore depending on date
metadata_raw <- metadata_raw %>% 
  mutate(covv_seq_technology = case_when(
    covv_collection_date > "2023-07-01" & str_detect(covv_seq_technology, "Nanopore") ~ "Nanopore GridIon, Artic V5.3.2 protocol modified",
    .default = covv_seq_technology)
  )

# Remove any duplicate ids and empty "code"
metadata_raw <- metadata_raw %>% 
  distinct(covv_virus_name, .keep_all = TRUE) %>%
  filter(!is.na(code))

# Create metadatafile for submission
metadata_submit <- metadata_raw %>%
  select(-KEY, -SEARCH_COLUMN, -SETUP, -code)	

## Find fasta sequences

# Create vector of samples to use
keep <- metadata_raw %>% pull(KEY)

# Load SEQUENCEDATA table and collect
seq <- tbl(con, "SEQUENCEDATA") %>% 
  filter(KEY %in% keep) %>%
  filter(TYPE == "SEQUENCE") %>% 
  # Retain only the columns "KEY", "EXPERIMENT", and "Sequence"
  select(KEY, EXPERIMENT, DATA) %>% 
  collect()

  
# Close connection
dbDisconnect(con)

# Function to decode and decompress a single entry
process_entry <- function(data_gz_base64) {
  tryCatch({
    # Decode from base64
    data_gz_raw <- base64decode(data_gz_base64)
    
    # Decompress the gzipped data
    data_decompressed <- memDecompress(data_gz_raw, type = "gzip")
    
    # Filter out null bytes ('\0') from the raw vector
    data_decompressed_no_nulls <- data_decompressed[data_decompressed != as.raw(0)]
    
    # Convert the cleaned raw vector to a character string
    data_text_no_nulls <- rawToChar(data_decompressed_no_nulls)
    
    # Remove weird characters from the beginning
    data_text_no_nulls_cleaned <- str_remove(data_text_no_nulls, "°t")
    
    return(data_text_no_nulls_cleaned)
  }, error = function(e) {
    message("Error processing entry: ", e$message)
    return(NA)
  })
}

# Apply the function to all entries in the DATA column
decompressed_seq <- seq %>%
  mutate(Sequence = map_chr(DATA, process_entry)) %>%
  # Trim strange characters from beginning of sequence string
  mutate(Sequence = str_sub(Sequence, start = 3)) %>%
  # Keep relevant columns
  select(KEY, EXPERIMENT, Sequence) %>%
  rename(Sequence = "Sequence")

# Join with metadata_raw to get the virus name. This needs to be in the fasta header to match the metadata file
decompressed_seq <- left_join(decompressed_seq, metadata_raw, by = c("KEY")) %>% 
  # Keep relevant columns
  select(covv_virus_name, Sequence)

# Convert to list to write as fasta using seqinr
# Need to name the elements with the covv_sequence_name
fasta_list <- setNames(as.list(decompressed_seq$Sequence), decompressed_seq$covv_virus_name)

# Define the output file path and filename
output_path <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon/"
output_dir <- format(Sys.Date(), "%Y-%m-%d")

# Create directory if not exists
if (!dir.exists(paste0(output_path, output_dir))) {
  dir.create(paste0(output_path, output_dir))  
} else {
  print("Directiry already exists")
}

output_filename_csv <- paste0(Sys.Date(), "_metadata.csv")
output_path_csv <- file.path(output_path, output_dir, output_filename_csv)


# Write the submission dataframe to a csv file
write_csv(metadata_submit, output_path_csv)


# Create the output filename for the FASTA file
output_filename_fasta <- paste0(Sys.Date(), "_sequences.fasta")
output_path_fasta <- file.path(output_path, output_dir, output_filename_fasta)

# Write fasta file
write.fasta(fasta_list, names =names(fasta_list), file.out = output_path_fasta)



