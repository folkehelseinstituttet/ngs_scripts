library(odbc)
library(tidyverse)
library(lubridate)

# Establish connection to Lab Ware ----------------------------------------
# Variables stored in Renviron file
con <- odbc::dbConnect(odbc::odbc(),
                       Driver = Sys.getenv("SQL_DRIVER"),
                       Server = Sys.getenv("SQL_SERVER"),
                       Database = Sys.getenv("SQL_DATABASE"))

## Hente ut data fra databasen
# Hente ut metadata om alle prøver fra SAMPLE-tabellen

# Lage list med relevante faggrupper til filtrering
faggrupper <- c("GB", "ENTPATB", "IM", "MYC")

samples <- tbl(con, "SAMPLE_VIEW") %>% 
  # Velge ut relevant kolonner først. Dette for å forenkle hva som skal hentes ut av driveren
  select(SAMPLE_NUMBER, TEXT_ID, GROUP_NAME, SAMPLED_DATE, RECD_DATE, X_MEDICAL_REVIEW, STATUS, X_AGENS) %>% 
  # Filtrer på faggrupper
  filter(GROUP_NAME %in% faggrupper) %>% 
  collect() %>% 
  # Remove identical rows
  distinct()

# Trekke ut SAMPLE_NUMBER
samples_sample_number <- samples %>% distinct(SAMPLE_NUMBER) %>% pull(SAMPLE_NUMBER)

# Finne batch eller sekvenserings run
test <- tbl(con, "TEST_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW", "BATCH") %>% 
  collect()

ngs_info <- test %>% 
  # Behold baktprøver
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>% 
  # Behold enten "NGS" eller "NGS_PREP"
  filter(ANALYSIS == "NGS" | ANALYSIS == "NGS_PREP") %>%
  # Gruppere prøvene etter "A" eller andre i X_TECH_REVIEW
  mutate(bucket = case_when(
    ANALYSIS == "NGS_PREP" & X_TECH_REVIEW == "A" ~ "Auth_NGS_PREP", # First check if NGS_PREP og A
    ANALYSIS == "NGS_PREP"                        ~ "Rej_NGS_PREP", # Deretter hvis NGS_PREP, men ikke A
    X_TECH_REVIEW == "A"                          ~ "Auth_NGS_SEQ", # Hvis ikke ANALYSIS = NGS_PREP må det være NGS
    TRUE                                          ~ "Rej_NGS_SEQ"  # Resten må være NGS_SEQ og ikke A
  )) %>% 
  # Beholde relevante kolonner
  select(SAMPLE_NUMBER, bucket, BATCH) %>% 
  # For hver SAMPLE_NUMBER og bucket, concatenate BATCH med komma
  group_by(SAMPLE_NUMBER, bucket) %>% 
  summarise(value = paste(unique(BATCH), collapse = ","), .groups = "drop") %>% 
  # Spre (pivot_wider) hver prøve på en enkelt linje
  pivot_wider(names_from = bucket,
              values_from = value,
              values_fill = "") # Empty string if bucket absent
  
  
# Joine med sample-info
final <- left_join(samples, ngs_info, by = c("SAMPLE_NUMBER" = "SAMPLE_NUMBER"))

# Write final data file
write_tsv(final, paste0(format(Sys.Date(), "%Y-%m-%d"), "_BAKT_POWERBI_lw_uttrekk.tsv"))