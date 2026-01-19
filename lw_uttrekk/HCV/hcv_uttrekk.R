library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.2

outdir <- "OUTDIR"
outfile <- file.path(outdir, paste0("HCV_665.csv"))

# Define the semafor file
readyfile <- sub("\\.csv$", ".ready", outfile)

# Remove the semafor file if it exists
if (file.exists(readyfile)) {
	unlink(readyfile)
}

# Establish connection to Lab Ware ----------------------------------------

con <- odbc::dbConnect(odbc::odbc(),
                       Driver = Sys.getenv("SQL_DRIVER"),
                       Server = Sys.getenv("SQL_SERVER"),
                       Database = Sys.getenv("SQL_DATABASE"))

# Extract sequencing Results and limit to "HCV_GEN"
# Could be further filtered. 
# Use TEST_NUMBER to join with others
res <- tbl(con, "RESULT_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "LIST_KEY", "ENTRY", "NAME") %>% # NAME er Resultat
  filter(LIST_KEY == "HCV_GEN") %>% 
  collect()

# Get sampled dates from the SAMPLE_VIEW table
sample_date <- tbl(con, "SAMPLE_VIEW") %>% 
  select("SAMPLE_NUMBER", "SAMPLED_DATE", "PROJECT", "ORDER_NUM") %>% 
  filter(SAMPLED_DATE > "2020-12-31") %>% 
  collect()

# Get the different analyses to get HCV NGS
analysis <- tbl(con, "TEST_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW") %>% 
  collect()

# Close database connection
odbc::dbDisconnect(con)


# Filter the analysis to get HCV samples analysed with NGS
analysis_filtered <- analysis %>% 
  filter(str_detect(ANALYSIS, "HCGEN_NGS") | str_detect(ANALYSIS, "HCRES_NGS")) %>% 
  # Remove cancelled or wrong samples
  # Drop tech review R and X or C
  filter(X_TECH_REVIEW != "R") %>% 
  filter(X_TECH_REVIEW != "X") %>% 
  filter(X_TECH_REVIEW != "C") 
  
# Connect the data
# Get the sample dates. Join by SAMPLE_NUMBER
hcv_ngs_joined <- analysis_filtered %>% 
  left_join(sample_date, by = c("SAMPLE_NUMBER" = "SAMPLE_NUMBER")) %>% 
  # Get the genotype results from NGS. Join by TEST_NUMBER
  left_join(res, by = c("TEST_NUMBER" = "TEST_NUMBER")) %>% 
  filter(NAME == "Resultat") # Genotype in in ENTRY

# Aggregate data and produce file for FHI Statistikk
# First clean the data and create new columns
data_cleaned <- hcv_ngs_joined %>% 
  # Remove samples without date
  filter(!is.na(SAMPLED_DATE)) %>% 
  # Clean up genotype names into a subtype column
  mutate(SUBTYPE = case_when(
    ENTRY == "1A" ~ "1a",
    ENTRY == "1B" ~ "1b",
    ENTRY == "2A" ~ "2a",
    ENTRY == "2B" ~ "2b",
    ENTRY == "3A" ~ "3a",
    ENTRY == "3B" ~ "3b",
    ENTRY == "3H" ~ "3h",
    ENTRY == "4A" ~ "4a",
    ENTRY == "4D" ~ "4d",
    ENTRY == "6A" ~ "6a",
    ENTRY == "6N" ~ "6n",
    ENTRY == "2K1B" ~ "2k1b",
    ENTRY == "2k1b(Skript) | 1b(GLUE)" ~ "2k1b",
    .default = ENTRY
  )) %>% 
  # Convert to date format for easier work with lubridate
  mutate(SAMPLED_DATE = as.Date(SAMPLED_DATE)) %>%
  # Create year, month, and yearmonth columns
  mutate(YEAR = year(SAMPLED_DATE),
         MONTH_NUM = month(SAMPLED_DATE),
         MONTH_NAME = month(SAMPLED_DATE, label = T)) %>% 
  unite("YEARMONTH_NUM", c("YEAR", "MONTH_NUM"), sep = "-", remove = F) %>% 
  unite("YEARMONTH_NAME", c("YEAR", "MONTH_NAME"), sep = "-", remove = F) %>% 
  # Remove samples with no genotype
  filter(!is.na(SUBTYPE)) %>% 
  filter(SUBTYPE != "NA") %>% 
  # Remove samples with wrong or strange results in SUBTYPE
  filter(SUBTYPE != "VHCIT",
         SUBTYPE != "KO",
         SUBTYPE != "MR",
         SUBTYPE != "IU",
         SUBTYPE != "Ikke typbar",
         SUBTYPE != "Analyse kansellert") %>% 
  # Create a GENOTYPE column
  mutate(GENOTYPE = case_when(
    SUBTYPE == "1a" ~ "1a",
    SUBTYPE == "1b" ~ "1b",
    SUBTYPE == "2" ~ "2",
    SUBTYPE == "2a" ~ "2",
    SUBTYPE == "2b" ~ "2",
    SUBTYPE == "2c" ~ "2",
    str_detect(SUBTYPE, "^3") ~ "3",
    str_detect(SUBTYPE, "^4") ~ "4",
    str_detect(SUBTYPE, "^5") ~ "5",
    str_detect(SUBTYPE, "^6") ~ "6",
    .default = SUBTYPE
  ))

# Tell antall prøver totalt og per genotype per år

# Først sett opp alle kombinasjoner av år og genotype for å få en komplett serie
all_years <- data_cleaned %>% distinct(YEAR)
all_genotypes <- data_cleaned %>% distinct(GENOTYPE)
all_combinations <- expand_grid(YEAR = all_years$YEAR, 
                                GENOTYPE = all_genotypes$GENOTYPE)

# Count all samples per year
total_per_year <- data_cleaned %>% 
  group_by(YEAR) %>% 
  summarise(ANTALL = n(), .groups = "drop") %>% 
  mutate(GENOTYPE = "Alle genotyper",
         FLAGG = "0")

# Count genotypes per year
per_genotype_year <- data_cleaned %>% 
  group_by(YEAR, GENOTYPE) %>% 
  summarise(ANTALL = n(), .groups = "drop") %>% 
  # join to get all genotypes for all years
  right_join(all_combinations, by = c("YEAR", "GENOTYPE")) %>% 
  mutate(FLAGG = "0",
         ANTALL = replace_na(ANTALL, 0)
         ) 

summary_df <- bind_rows(
  total_per_year,
  per_genotype_year
) %>% 
  select(YEAR, GENOTYPE, ANTALL, FLAGG) %>% 
  arrange(YEAR)
  
# Write the data file
write_delim(summary_df,
            outfile,
            delim = ";",
            quote = "all"
            )

# Write the semafor file
file.create(readyfile)
