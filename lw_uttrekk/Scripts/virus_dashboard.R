library(odbc)
library(tidyverse)
library(lubridate)

# Version 1.2

## ==================================================
## Validate required environment variables
## ==================================================

required_vars <- c(
  "OUTDIR",
  "SQL_DRIVER",
  "SQL_SERVER",
  "SQL_DATABASE",
  "RUN_ENV"
)

missing <- required_vars[Sys.getenv(required_vars) == ""]
if (length(missing) > 0) {
  stop(
    "Missing required environment variables: ",
    paste(missing, collapse = ", ")
  )
}

## ==================================================
## Resolve variables
## ==================================================

run_env   <- Sys.getenv("RUN_ENV")   # Test or Prod
outdir    <- Sys.getenv("OUTDIR")
sqldriver <- Sys.getenv("SQL_DRIVER")
sqlserver <- Sys.getenv("SQL_SERVER")
database  <- Sys.getenv("SQL_DATABASE")

## ==================================================
## Validate output directory
## ==================================================

if (!dir.exists(outdir)) {
  stop(
    "OUTDIR does not exist: ", outdir,
    "\nEnvironment: ", run_env
  )
}

# Name output file
outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/VIRUS_POWERBI_lw_uttrekk.tsv"))

## ==================================================
## Establish connection to Lab Ware 
## ==================================================

con <- tryCatch(
  {
    odbc::dbConnect(odbc::odbc(),
                    Driver = sqldriver,
                    Server = sqlserver,
                    Database = database
    )
  },
  error = function(e) {
    cat(
      "ERROR: Unable to connect to database.\n",
      "Environment: ", run_env, "\n",
      "Message: ", e$message, "\n", 
      file = outfile
    )
    stop("Connection failed")
  }
)

## ==================================================
## Extract data from LabWare
## ==================================================

# Lage liste med relevante faggrupper til filtrering
faggrupper <- c("HEP_HIV", "HPV", "INFLUENSA", "MMR", "POL_ENT", "ROTA", "VIRUS_CMN")

# Hente ut metadata om alle prøver fra SAMPLE-tabellen
samples <- tbl(con, "SAMPLE_VIEW") %>% 
  # Velge ut relevant kolonner først. Dette for å forenkle hva som skal hentes ut av driveren
  select(ORIGINAL_SAMPLE, PARENT_SAMPLE, TEMPLATE, SAMPLE_NUMBER, TEXT_ID, GROUP_NAME, SAMPLED_DATE, RECD_DATE, X_MEDICAL_REVIEW, STATUS, X_AGENS, PATIENT) %>% 
  # Filtrer på faggrupper
  filter(GROUP_NAME %in% faggrupper) %>% 
  collect() %>% 
  # Remove identical rows
  distinct() %>%
  # Add column indicating if sample is a child sample
  # Child sample have a different ORIGNIAL_SAMPLE than SAMPLE_NUMBER
  mutate(child_sample = if_else(ORIGINAL_SAMPLE == SAMPLE_NUMBER, "NO", "YES"))

# Trekke ut SAMPLE_NUMBER
samples_sample_number <- samples %>% distinct(SAMPLE_NUMBER) %>% pull(SAMPLE_NUMBER)

# Finne batch eller sekvenserings run
test <- tbl(con, "TEST_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW", "BATCH") %>% 
  collect()

ngs_info <- test %>% 
  # Behold virusprøver
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>% 
  # Behold enten "NGS" eller "NGS_PREP"
  filter(ANALYSIS == "NGS" | ANALYSIS == "NGS_PREP" | ANALYSIS == "SC2_NGS" | ANALYSIS == "MPX_WGS") %>%
  # Gruppere prøvene etter "A" eller andre i X_TECH_REVIEW
  mutate(bucket = case_when(
    ANALYSIS == "NGS_PREP" & X_TECH_REVIEW == "A" ~ "Auth_NGS_PREP", # First check if NGS_PREP og A
    ANALYSIS == "NGS_PREP"                        ~ "NotAuth_NGS_PREP", # Deretter hvis NGS_PREP, men ikke A
    X_TECH_REVIEW == "A"                          ~ "Auth_NGS_SEQ", # Hvis ikke ANALYSIS = NGS_PREP må det være NGS
    TRUE                                          ~ "NotAuth_NGS_SEQ"  # Resten må være NGS_SEQ og ikke A
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
final <- left_join(samples, ngs_info, by = c("SAMPLE_NUMBER" = "SAMPLE_NUMBER")) %>%
  rename("SAMPLE.STATUS" = STATUS)

# Write final data file
write_tsv(final, outfile)

# Close connection
odbc::dbDisconnect(con)
