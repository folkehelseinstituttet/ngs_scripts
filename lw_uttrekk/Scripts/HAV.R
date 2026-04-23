library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.1
# Extracts HAV (Hepatitt A Virus) PCR/genotyping data from LabWare.
# Includes sample metadata, HAGEN analyses, and results.
# Not WGS/NGS - covers all HAGEN (Hepatitt A genotyping) analyses.

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
outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/HAV_lw_uttrekk.tsv"))

# Define the semaphore file
readyfile <- sub("\\.tsv$", ".ready", outfile)

# Remove the semaphore file if it exists
if (file.exists(readyfile)) {
  unlink(readyfile)
}

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

# Pull sample metadata from SAMPLE_VIEW.
# HAV belongs to the HEP_HIV group.
# TEXT_ID is the sequence/lab identifier for the sample.
samples <- tbl(con, "SAMPLE_VIEW") %>%
  select(
    SAMPLE_NUMBER, TEXT_ID,
    GROUP_NAME, SAMPLED_DATE, RECD_DATE,
    X_ZIPCODE, GENDER, X_GENDER, BIRTH_DATE,
    X_AGENS, X_MEDICAL_REVIEW, STATUS, PATIENT,
    ORDER_NUM
  ) %>%
  filter(GROUP_NAME == "HEP_HIV") %>%
  collect() %>%
  distinct()

# Pull test info from TEST_VIEW.
# Used to identify HAV analyses and to exclude cancelled/rejected tests.
tests <- tbl(con, "TEST_VIEW") %>%
  select(TEST_NUMBER, SAMPLE_NUMBER, ANALYSIS, X_TECH_REVIEW, BATCH, STATUS) %>%
  collect()

# Pull results from RESULT_VIEW for HAGEN analyses.
# Filtered at DB level for efficiency, mirroring the HCV WGS pattern.
# Join to tests by TEST_NUMBER to link sequence ID and other results.
results <- tbl(con, "RESULT_VIEW") %>%
  select(TEST_NUMBER, SAMPLE_NUMBER, ANALYSIS, NAME, ENTRY, FORMATTED_ENTRY, LIST_KEY, RESULT_NUMBER) %>%
  filter(ANALYSIS %like% "%HAGEN%") %>%
  collect()

# Close database connection
odbc::dbDisconnect(con)

## ==================================================
## Filter and clean
## ==================================================

# Filter to HAGEN analyses in TEST_VIEW.
# str_detect catches any analysis code containing "HAGEN".
# Exclude cancelled (X) and rejected (R) tests.
hav_tests <- tests %>%
  filter(str_detect(ANALYSIS, regex("HAGEN", ignore_case = TRUE))) %>%
  filter(!X_TECH_REVIEW %in% c("X", "R"))

# Vector of SAMPLE_NUMBERs with at least one HAV analysis
hav_sample_numbers <- hav_tests %>%
  distinct(SAMPLE_NUMBER) %>%
  pull(SAMPLE_NUMBER)

# Filter sample metadata to HAV samples only.
# Exclude samples cancelled or rejected at medical review level.
samples_cleaned <- samples %>%
  filter(SAMPLE_NUMBER %in% hav_sample_numbers) %>%
  filter(!X_MEDICAL_REVIEW %in% c("X", "R"))

# Update sample list after medical review filter
hav_sample_numbers_cleaned <- samples_cleaned %>%
  distinct(SAMPLE_NUMBER) %>%
  pull(SAMPLE_NUMBER)

# Filter results to HAGEN samples (results already pre-filtered to HAGEN at DB level)
hav_results <- results %>%
  filter(SAMPLE_NUMBER %in% hav_sample_numbers_cleaned)

# Extract sequence ID by joining tests to results via TEST_NUMBER,
# mirroring the HCV WGS pattern in HCV.R.
# The sequence ID is stored in result rows where NAME == "SekvensID".
hav_seq_id <- hav_tests %>%
  filter(SAMPLE_NUMBER %in% hav_sample_numbers_cleaned) %>%
  select(TEST_NUMBER, SAMPLE_NUMBER) %>%
  left_join(
    hav_results %>% select(TEST_NUMBER, NAME, ENTRY),
    by = "TEST_NUMBER"
  ) %>%
  filter(NAME == "SekvensID") %>%
  group_by(SAMPLE_NUMBER) %>%
  summarise(SEQ_ID = paste(unique(na.omit(ENTRY)), collapse = "; "), .groups = "drop")

## ==================================================
## Summarise test info per sample
## ==================================================

# Collapse multiple HAGEN analyses and batches to one row per sample
test_summary <- hav_tests %>%
  filter(SAMPLE_NUMBER %in% hav_sample_numbers_cleaned) %>%
  group_by(SAMPLE_NUMBER) %>%
  summarise(
    ANALYSES     = paste(unique(ANALYSIS), collapse = "; "),
    BATCHES      = paste(unique(na.omit(BATCH)), collapse = "; "),
    TECH_REVIEWS = paste(unique(X_TECH_REVIEW), collapse = "; "),
    .groups = "drop"
  )

## ==================================================
## Pivot results wide (one row per sample)
## ==================================================

# For each result row, use FORMATTED_ENTRY if available, else ENTRY
# Then pivot wide: columns are named ANALYSIS_ResultName
hav_results_wide <- hav_results %>%
  mutate(entry_value = if_else(
    !is.na(FORMATTED_ENTRY) & FORMATTED_ENTRY != "",
    FORMATTED_ENTRY,
    ENTRY
  )) %>%
  # Multiple entries for same sample/analysis/result name -> concatenate
  group_by(SAMPLE_NUMBER, ANALYSIS, NAME) %>%
  summarise(entry_value = paste(unique(na.omit(entry_value)), collapse = "; "),
            .groups = "drop") %>%
  unite("result_col", ANALYSIS, NAME, sep = "_") %>%
  pivot_wider(
    names_from  = result_col,
    values_from = entry_value,
    values_fill = NA_character_
  )

## ==================================================
## Join into final dataset
## ==================================================

final <- samples_cleaned %>%
  left_join(test_summary,     by = "SAMPLE_NUMBER") %>%
  left_join(hav_seq_id,       by = "SAMPLE_NUMBER") %>%
  left_join(hav_results_wide, by = "SAMPLE_NUMBER") %>%
  # Parse dates
  mutate(
    SAMPLED_DATE = as.Date(SAMPLED_DATE),
    RECD_DATE    = as.Date(RECD_DATE),
    BIRTH_DATE   = as.Date(BIRTH_DATE)
  )

## ==================================================
## Write output
## ==================================================

write_tsv(final, outfile)

# Create semaphore file to signal that the output file is complete
writeLines("done", readyfile)
