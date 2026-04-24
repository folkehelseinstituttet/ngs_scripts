library(odbc)
library(tidyverse)
library(lubridate)

# Version 2.0-dev
# Versjon 1 inneholdt kun info om prøvedato og sekvensering.
# Versjon 2 legger på mer info om analyser og resultater. 

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

# Name output files
outfile  <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/VIRUS_POWERBI_lw_uttrekk.tsv"))
outfile2 <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/VIRUS_POWERBI_results.tsv"))

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

## ==================================================
## Define analysis code groups
## ==================================================

ngs_seq_codes <- c("NGS", "SC2_NGS", "MPX_WGS", "SC2_WGS", "INF_WGS", "RSV_WGS",
                   "ROV_WGS", "HPV_WGS", "UKJVIRUS_WGS", "HCRES_NGS", "HCVNGS",
                   "HCGEN_NGS", "HCVNGS_PROSJ", "SC2_VAR_NGS")

extraction_codes <- c("EKSTRAKSJON", "EKSTR", "EXT", "EXTPRI", "EXTFLU", "EXTNEP",
                      "EXT_MOR", "EXT_PAR", "EXT_ROTA", "EXT_ROTA_S",
                      "EXT_NORO", "EXT_NORO_S", "EXT_B19", "EXT_RUB",
                      "EXTPRI_SA2R", "EXTPRI_A", "EXTPRI_B", "EXTPRI_FYR", "PROVEPREP")

culture_codes <- c("DYRKING", "VDYRKE", "VDYRKA", "BGM", "L20B", "A549", "RD",
                   "FORT_ROTA", "FORT_ROTA_S", "FORT_NORO", "FORT_NORO_S")

pcr_codes <- c(
  # Influensa
  "INFABPCR", "INFA_TRICDC", "INFB_TRICDC", "SC2_TRICDC", "INFSC2",
  "INFAH1H3", "INFBVYPCR", "INFB_VIC", "INFB_YAM",
  "IAH1C1", "IAH3C1", "IACDC1", "IBCDC1", "IASAC1",
  "INAH5A", "INAH5B", "INFAH9", "INFAN9", "H7VLA2", "RNPPCR",
  # Luftveir / VIRUS_CMN
  "RSVABPCR", "RSVA_PCR", "RSVB_PCR", "RINPCR", "RSPCR",
  "HMPVPCR", "ADPCR", "PA1PCR", "PA2PCR", "PA3PCR",
  "COV229EPCR", "COVNL63PCR", "COVOC43PCR", "COVHKU1PCR", "MPLPNEUPCR",
  "NCOV2019RDRP", "SARSCOV2RDRP", "SABEPCR", "SABNPCR", "SABRDRP",
  "SEK_COV", "EV_D68_PCR", "EV_D68_PCR_2",
  # Entero / POL_ENT
  "ENTERO_PCR_RNA", "ENTPCR", "ENT_RNA",
  # Rota / Noro
  "ROTA_PCR_RNA", "ROTAVP4_PCR", "ROTAVP6_PCR", "ROTAVP7_PCR", "ROTA_RIDAGENE",
  "NORO_PCR_RNA", "NOROPCR", "NOROPCR_RT",
  # MMR / B19 / Parvovirus
  "MOPCR", "MOPCR_RT", "MOPCR_CDC", "MOPCR_CDC_REPL",
  "RUPCR", "RUPCR_CDC", "RUPCR_CDC_REPL",
  "PAPCR_CDC", "PAPCR_CDC_REPL", "PARPCR", "PARPCR_PRIM", "PARPCR_SEK",
  "B19PCR",
  # HEP_HIV
  "HCVPCR", "HIRPCR", "HIDPCR", "HAPCR", "HAPCR-PRIM", "HAPCR-SEK",
  "HBQPCR", "HBQPCR_BG", "HBSPCR1", "HBSPCR2",
  "HBQPCRSENS_1ML", "HBQPCRSANSLAV",
  "HEVPCR", "HAVPCR", "HCPCR",
  # Arbovirus
  "DENPCR-IH", "DENPCR-ALT", "DENPCR-CDC",
  "CHIPCR-IH", "CHIPCR-ALT", "ZIKPCR-ALTO", "VNVPCR-IH",
  "YFVPCR", "TBEPCR",
  # HPV
  "HPV_QPCR", "HPV_LUMINEX"
)

serology_codes <- c(
  # Influensa
  "IASRH1",
  # MMR / B19 / Parvo
  "MOGENZ", "MOGMIC", "MOMENZ", "MOMMIC",
  "RUGENZ", "RUMMED", "RUMMIC", "RUGSER", "RUMEUR", "RUGEUR", "MOMEUR", "MOGEUR",
  "PAMSER", "PAMMIC", "PAGSER", "PAGMIC", "PAGT",
  "B19GSER", "B19MSER", "B19GBIO", "B19MBIO",
  "TBEGSER", "TBEMSER", "TBEGENZ", "TBEMENZ", "TBEGIF", "TBEMIF",
  # HEP_HIV
  "HIAGB", "HIAGNB", "HIIE", "HIGWB",
  "HBSEU", "HBCPIE", "HBEIF", "HBSIFQ", "HBSNEU", "HBSGEN1", "HBSGEN2",
  "HAIF", "HAIFV", "HAMF", "HBSKVA", "HBSKVAR",
  "WBLT22_STRIP", "HCV_LIA", "HCVB", "HDAGDS", "HDIEDS",
  # Arbovirus / VIRUS_CMN
  "DENGIF", "DENMIF", "DENNS1",
  "CHIGIF", "CHIMIF", "YFVGIF", "YFVMIF",
  "JEVGIF", "JEVMIF", "VNVGIF", "VNVMIF",
  "ZIKGIF", "ZIKMIF", "ZIGEUR", "ZIMEUR",
  "HANGIF", "HANMIF", "SFVGIF", "SFVMIF", "SINGIF", "SINMIF",
  "DEGEUR", "DEMEUR", "CHIMEUR", "CHIGEUR"
)

## ==================================================
## Classify tests into buckets
## ==================================================

ngs_info <- test %>% 
  # Behold virusprøver
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>% 
  # Behold relevante analysekoder
  filter(ANALYSIS %in% c("NGS_PREP", ngs_seq_codes,
                         extraction_codes, culture_codes,
                         pcr_codes, serology_codes)) %>%
  # Gruppere prøvene etter bucket
  mutate(bucket = case_when(
    ANALYSIS == "NGS_PREP" & X_TECH_REVIEW == "A"          ~ "Auth_NGS_PREP",
    ANALYSIS == "NGS_PREP"                                 ~ "NotAuth_NGS_PREP",
    ANALYSIS %in% ngs_seq_codes & X_TECH_REVIEW == "A"     ~ "Auth_NGS_SEQ",
    ANALYSIS %in% ngs_seq_codes                            ~ "NotAuth_NGS_SEQ",
    ANALYSIS %in% extraction_codes & X_TECH_REVIEW == "A"  ~ "Auth_EXTRACTION",
    ANALYSIS %in% extraction_codes                         ~ "NotAuth_EXTRACTION",
    ANALYSIS %in% culture_codes & X_TECH_REVIEW == "A"     ~ "Auth_CULTURE",
    ANALYSIS %in% culture_codes                            ~ "NotAuth_CULTURE",
    ANALYSIS %in% pcr_codes & X_TECH_REVIEW == "A"         ~ "Auth_PCR",
    ANALYSIS %in% pcr_codes                                ~ "NotAuth_PCR",
    ANALYSIS %in% serology_codes & X_TECH_REVIEW == "A"    ~ "Auth_SEROLOGY",
    ANALYSIS %in% serology_codes                           ~ "NotAuth_SEROLOGY",
    TRUE                                                  ~ NA_character_
  )) %>%
  filter(!is.na(bucket)) %>%
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

# Write File 1: sample-level wide table
write_tsv(final, outfile)

## ==================================================
## File 2: VIRUS_POWERBI_results.tsv
## Long-format diagnostic result values per sample
## ==================================================

# Whitelist of (ANALYSIS, NAME) pairs with diagnostic value.
# Admin/workflow fields (Autohandling, MSISLABDB, Rådatafil, Utført av, etc.)
# are intentionally excluded.
result_whitelist <- tribble(
  ~ANALYSIS,       ~NAME,
  # --- PCR: influensa ---
  "INFABPCR",      "Influensa A",
  "INFABPCR",      "Influensa B",
  "INFABPCR",      "ct. A",
  "INFABPCR",      "ct. B",
  "INFA_TRICDC",   "Resultat",
  "INFA_TRICDC",   "ct. INFA",
  "INFB_TRICDC",   "Resultat",
  "INFB_TRICDC",   "ct. INFB",
  "SC2_TRICDC",    "Resultat",
  "SC2_TRICDC",    "ct. SC2",
  "INFSC2",        "Resultat",
  "INFSC2",        "ct. SC2",
  "INFSC2",        "ct. InfA",
  "INFSC2",        "ct. InfB",
  "IAH3C1",        "Resultat",
  "IAH3C1",        "H3",
  "IAH3C1",        "ct. H3",
  "IASRH1",        "Resultat",
  "IASRH1",        "H1pdm09",
  "IASRH1",        "ct. H1",
  # --- PCR: RSV ---
  "RSVA_PCR",      "Resultat",
  "RSVA_PCR",      "ct. RSVA",
  "RSVB_PCR",      "Resultat",
  "RSVB_PCR",      "ct. RSVB",
  "RSVABPCR",      "ct. RSVA",
  "RSVABPCR",      "ct. RSVB",
  # --- PCR: arbovirus ---
  "DENGIF",        "Resultat DENV-1",
  "DENGIF",        "Resultat DENV-2",
  "DENGIF",        "Resultat DENV-3",
  "DENGIF",        "Resultat DENV-4",
  "DENGIF",        "Konklusjon DENV-1",
  "DENGIF",        "Konklusjon DENV-2",
  "DENGIF",        "Konklusjon DENV-3",
  "DENGIF",        "Konklusjon DENV-4",
  "CHIGIF",        "Resultat",
  "CHIGIF",        "Konklusjon",
  # --- Serology: MMR / B19 ---
  "MOGENZ",        "Konklusjon",
  "MOGENZ",        "Result_num",
  "MOGENZ",        "Titer",
  "MOGENZ",        "S / Positiv CO %",
  "MOGMIC",        "Konklusjon",
  "MOGMIC",        "Result_num",
  "MOGMIC",        "S / Positiv CO %",
  "PAMSER",        "Konklusjon",
  "PAMSER",        "Result_num_avlest",
  "PAMSER",        "S / Positiv CO %",
  "PAMMIC",        "Konklusjon",
  "PAMMIC",        "Result_num",
  "PAMMIC",        "S / Positiv CO %",
  "MOMENZ",        "Konklusjon",
  "MOMENZ",        "Result_num",
  "MOMENZ",        "S / Positiv CO %",
  "RUGENZ",        "Konklusjon",
  "RUGENZ",        "Result_num",
  "RUGENZ",        "Titer",
  "RUGSER",        "Konklusjon",
  "RUGSER",        "Result_num_avlest",
  "B19GSER",       "Konklusjon",
  "B19GSER",       "Result_num_avlest",
  "B19MSER",       "Konklusjon",
  "B19MSER",       "Result_num_avlest",
  # --- Serology: HEP_HIV ---
  "HIAGB",         "Konklusjon",
  "HIAGB",         "Result_num",
  "HIAGB",         "S/CO prosent",
  "HAIFV",         "Konklusjon",
  "HAIFV",         "Resultat_txt",
  "HAIFV",         "Resultat_num",
  "HCVB",          "Konklusjon",
  "HCVB",          "Result_num",
  "HCVB",          "S/CO prosent",
  # --- NGS/WGS typing + QC ---
  "NGS",           "Genotype fra skript",
  "NGS",           "Gj. snittlig dybde",
  "NGS",           "Dekning % av genomet",
  "NGS",           "Kvalitet på sekvensen",
  "NGS_PREP",      "NGS-status",
  "NGS_PREP",      "Ct",
  "NGS_PREP",      "Agens",
  "SC2_NGS",       "Genetisk variant",
  "SC2_NGS",       "Stammenr",
  "INF_WGS",       "Subtype",
  "INF_WGS",       "Clade",
  "RSV_WGS",       "Clade",
  "MPX_WGS",       "Klade",
  "MPX_WGS",       "Lineage",
  "MPX_WGS",       "Stammenavn",
  # --- Culturing ---
  "VDYRKE",        "Konklusjon",
  "VDYRKE",        "Funn",
  "VDYRKE",        "eMSIS status",
  "VDYRKA",        "Konklusjon",
  "VDYRKA",        "Funn"
)

results_file2 <- tbl(con, "RESULT_VIEW") %>%
  select(SAMPLE_NUMBER, TEST_NUMBER, ANALYSIS, NAME, ENTRY, FORMATTED_ENTRY,
         ENTERED_ON, CHANGED_ON) %>%
  collect() %>%
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>%
  inner_join(result_whitelist, by = c("ANALYSIS", "NAME")) %>%
  mutate(
    value = coalesce(
      na_if(as.character(FORMATTED_ENTRY), ""),
      na_if(as.character(ENTRY), "")
    )
  ) %>%
  filter(!is.na(value)) %>%
  select(SAMPLE_NUMBER, TEST_NUMBER, ANALYSIS, NAME, value, ENTERED_ON, CHANGED_ON)

# Write File 2: long-format results table
write_tsv(results_file2, outfile2)

# Close connection
odbc::dbDisconnect(con)
