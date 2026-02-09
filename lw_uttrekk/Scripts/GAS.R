library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.1

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
outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/GAS_PK_lw_uttrekk.tsv"))

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
  select("X_AGENS", "SAMPLE_NUMBER", "SAMPLED_DATE", "X_PATIENT_AGE", "X_ZIPCODE", "ORDER_NUM", "X_GENDER", "BIRTH_DATE", "X_MEDICAL_REVIEW") %>% 
  collect()

# Hente info om hver enkelt test. For å kunne fjerne kansellerte tester
# Ta bort TEST_NUMBER som er X eller R i X_TECH_REVIEW fra TEST_VIEW
# Kanselleringer og TECH_REVIEW osv. Kansellerte GAS_WGS og kansellerte MIC
# Lage en liste med SAMPLE_NUMBERS som jeg IKKE vil ha
test <- tbl(con, "TEST_VIEW") %>% 
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW") %>% 
  filter(X_TECH_REVIEW == "X" | X_TECH_REVIEW == "R") %>% # R = Rejected, X = Cancelled
  collect()

# Hente ut region info
region <- tbl(con, "REGION_VIEW") %>% 
  collect()

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

# Begrense resultatene til GAS og prøver som har blitt GAS-typet etter WGS
# Bruke dette for å finne relevante SAMPLE_NUMBERS
gas_pk_res <- results_cleaned %>% 
  filter(ANALYSIS == "GAS_WGS" | ANALYSIS == "PK_WGS") %>% 
  # Ta bort prøver som er kansellert
  filter(!SAMPLE_NUMBER %in% cancelled_sample_numbers)

# Then get the SAMPLE_NUMBER for GAS_WGS samples for getting sample metadata
gas_pk_wgs_sample_number <- gas_pk_res %>% distinct(SAMPLE_NUMBER) %>% pull(SAMPLE_NUMBER)

# Keep all results_cleaned info, but only for SAMPLE_NUMBERs with GAS_WGS
gas_pk_res_long <- results_cleaned %>% 
  filter(SAMPLE_NUMBER %in% gas_pk_wgs_sample_number)

# Connect the sample metadata to gas_res_long. This already contains the resistance data
gas_pk_res_long_metadata <- gas_pk_res_long %>% 
  left_join(samples_cleaned, by =c("SAMPLE_NUMBER" = "SAMPLE_NUMBER"))

# Then connect region info
gas_pk_res_long_metadata_region <- gas_pk_res_long_metadata %>% 
  left_join(region, by = c("X_ZIPCODE" = "ZIPCODE"))

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
