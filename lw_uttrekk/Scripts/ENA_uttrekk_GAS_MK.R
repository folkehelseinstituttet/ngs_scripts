library(odbc)
library(tidyverse)
library(lubridate)

# version: dev

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

outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/ENA_GAS_MK_lw_uttrekk.tsv"))

tmp <- read_delim("K:/GbMetaFile.csv", delim = ";")
tmp %>% distinct(Gruppenavn)

## ==================================================
## Establish connection to LabWare
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
      "Timestamp: ", ts, "\n",
      "Environment: ", run_env, "\n",
      "Message: ", e$message, "\n", 
      file = outfile
    )
    stop("Connection failed")
  }
)
  
cat(
  "Connection successful!\n", 
  "Timestamp: ", ts, "\n",
  "Environment: ", run_env, "\n",
  file = outfile
)


# Trenger disse kolonnene:
# Run;Agens;Gruppenavn;Prøvenr;Reflab-ID;Materiale;Prøvetatt dato;Mottatt dato;Godkjent dato;Rekvisisjonsnr;Lokalisasjon;Pasientstatus;Rekvirentkode;Rekvirent
# Skal bare ha GAS og MK for Agens

# Bare faggruppe GB
faggruppe <- "GB"


## Hente ut data fra databasen

# Hente ut resultater. 
# Nå henter jeg alt. Tidligere begrenset jeg her på GAS_WGS, MIC og NGS. Kanskje gå tilbake til dette senere.
# Både GAS-prøver som er blitt NGS-analysert, og resultater for MIC
results <- tbl(con, "RESULT_VIEW") %>% 
  select("ANALYSIS", "NAME", "ENTRY", "SAMPLE_NUMBER", "RESULT_NUMBER", "TEST_NUMBER", "ORDER_NUMBER", "X_TABRES_NAME", "X_TABRES_SOURCE") %>% 
  #filter(ANALYSIS == "GAS_WGS" | NAME == "MIC" | ANALYSIS == "NGS") %>% 
  collect()

# Hente metadata om prøver fra SAMPLE_VIEW.
samples <- tbl(con, "SAMPLE_VIEW") %>% 
  select("GROUP_NAME", "X_ACCESSION_CODE", "X_AGENS", "SAMPLE_NUMBER", "SAMPLED_DATE", "X_PATIENT_AGE", "X_ZIPCODE", "ORDER_NUM", "X_GENDER", "BIRTH_DATE", "X_MEDICAL_REVIEW") %>% 
  # Filtrer på faggruppe
  filter(GROUP_NAME %in% faggruppe) %>% 
  collect()

# Hente info om hver enkelt test. For å kunne fjerne kansellerte tester
# Ta bort TEST_NUMBER som er X eller R i X_TECH_REVIEW fra TEST_VIEW
# Kanselleringer og TECH_REVIEW osv. Kansellerte GAS_WGS og kansellerte MIC
# Lage en liste med SAMPLE_NUMBERS som jeg IKKE vil ha
test <- tbl(con, "TEST_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW", "BATCH") %>% 
  filter(X_TECH_REVIEW == "X" | X_TECH_REVIEW == "R") %>% # R = Rejected, X = Cancelled
  collect()

# Hente ut region info
#region <- tbl(con, "REGION_VIEW") %>% 
#  collect()

# Lukke koblingen til databasen
odbc::dbDisconnect(con)

## Rense data data

# Lage liste over TEST_NUMBERS som skal fjernes
cancelled_test_numbers <- test %>% distinct(TEST_NUMBER) %>% pull(TEST_NUMBER)

# Ta bort disse TEST_NUMBERS fra results
# Results_cleaned vil bli utgangspunktet
results_cleaned <- results %>% 
  # Ta bort TEST_NUMBER som er X eller R
  filter(!TEST_NUMBER %in% cancelled_test_numbers)

# Fjerne total results for å spare plass
rm(results)

# Ta bort prøver som skal er kansellert
cancelled_sample_numbers <- samples %>%
  filter(X_MEDICAL_REVIEW == "X" | X_MEDICAL_REVIEW == "R") %>% 
  distinct(SAMPLE_NUMBER) %>% 
  pull(SAMPLE_NUMBER)

# Ta bort disse prøvene fra samples
samples_cleaned <- samples %>% 
  filter(!SAMPLE_NUMBER %in% cancelled_sample_numbers)

# Fjerne total samples for å spare plass
rm(samples)

## Filtrere og slå sammen data for GAS og PK

# Begrense resultatene til GAS/MK og prøver som har blitt typet etter WGS
# Bruke dette for å finne relevante SAMPLE_NUMBERS
gas_mk_res <- results_cleaned %>% 
  filter(ANALYSIS == "GAS_WGS" | ANALYSIS == "MK_WGS") %>% 
  # Ta bort prøver som er kansellert
  filter(!SAMPLE_NUMBER %in% cancelled_sample_numbers)

# Then get the SAMPLE_NUMBER for GAS/MK_WGS samples for getting sample metadata
gas_mk_wgs_sample_number <- gas_mk_res %>% distinct(SAMPLE_NUMBER) %>% pull(SAMPLE_NUMBER)

# Keep all results_cleaned info, but only for SAMPLE_NUMBERs with GAS/MK_WGS
gas_mk_res_long <- results_cleaned %>% 
  filter(SAMPLE_NUMBER %in% gas_mk_wgs_sample_number)

# Connect the sample metadata to gas_mk_res_long This already contains the resistance data
gas_mk_res_long_metadata <- gas_mk_res_long %>% 
  left_join(samples_cleaned, by =c("SAMPLE_NUMBER" = "SAMPLE_NUMBER"))

# Remove samples with NA in X_AGENS
gas_mk_res_long_metadata <- gas_mk_res_long_metadata %>% 
  filter(is.na(X_AGENS))

# Finne run-navn. Kun prøver som har blitt sekvensert
run_info <- test %>% 
  # Beholde relevante prøver
  filter(SAMPLE_NUMBER %in% gas_mk_wgs_sample_number) %>%
  # Beholde kun "NGS" (ikke "NGS_PREP")
  filter(ANALYSIS == "NGS") %>% 
  #select(SAMPLE_NUMBER, BATCH) %>% distinct(BATCH) %>% filter(!is.na(BATCH))

readr::write_csv(run_info, file = "GAS_MK_run_info.csv")  

colnames(gas_mk_res_long_metadata)



## Lage endelig dataobjekt

# Define age groups
age_breaks <- c(0, 6, 15, 44, 66, 79, Inf)
age_labels <- c("0-6", "7-15", "16-44", "45-66", "67-79", "80+")

final <- gas_pk_res_long_metadata_region %>% 
  # Beregne aldersgrupper
  mutate(
    age = interval(BIRTH_DATE, today()) / years(1), # Calculate age in years. Interval gives the time interval from birth to today. years(1) represents a duration of 1 year (365 days). These are then divided.
    age_group = cut(age, breaks = age_breaks, labels = age_labels, right = TRUE)
  ) %>% 
  # Velge ut endelige kolonner
  select(
    X_AGENS,
    SAMPLE_NUMBER,
    RESULT_NUMBER,
    TEST_NUMBER,
    ORDER_NUM,
    ANALYSIS,
    NAME,
    ENTRY,
    SAMPLED_DATE,
    X_GENDER,
    age_group,
    starts_with("REGION"),
    starts_with("FYLKE")
  )

# Write final data file
write_tsv(final, outfile)
