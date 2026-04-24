library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.0
script_version <- "1.0"

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

run_env <- Sys.getenv("RUN_ENV")
outdir <- Sys.getenv("OUTDIR")
output_dir <- file.path(outdir, run_env, "ToOrdinary", "LW_Datauttrekk")
sqldriver <- Sys.getenv("SQL_DRIVER")
sqlserver <- Sys.getenv("SQL_SERVER")
database <- Sys.getenv("SQL_DATABASE")

## ==================================================
## Validate output directory
## ==================================================

if (!dir.exists(outdir)) {
  stop(
    "OUTDIR does not exist: ", outdir,
    "\nEnvironment: ", run_env
  )
}

if (!dir.exists(output_dir)) {
  stop(
    "Output directory does not exist: ", output_dir,
    "\nEnvironment: ", run_env
  )
}

## ==================================================
## Settings
## ==================================================

run_date <- Sys.Date()
date_from <- run_date - 365
date_to   <- run_date

message("Script version: ", script_version)
message("Environment: ", run_env)
message("Run date: ", run_date)
message("Including samples from: ", date_from, " to ", date_to)

## ==================================================
## Establish connection to LabWare
## ==================================================

con <- tryCatch(
  {
    DBI::dbConnect(
      odbc::odbc(),
      Driver = sqldriver,
      Server = sqlserver,
      Database = database
    )
  },
  error = function(e) {
    error_file <- file.path(output_dir, "NGS_PREP_reports_error.txt")
    cat(
      "ERROR: Unable to connect to database.\n",
      "Environment: ", run_env, "\n",
      "Message: ", e$message, "\n",
      file = error_file
    )
    stop("Connection failed")
  }
)

## ==================================================
## Helper functions
## ==================================================

season_code_from_date <- function(x) {
  y <- year(x)
  m <- month(x)
  ifelse(
    m >= 7,
    paste0(substr(y, 3, 4), substr(y + 1, 3, 4)),
    paste0(substr(y - 1, 3, 4), substr(y, 3, 4))
  )
}

rekvnr_from_id <- function(x, sample_date) {
  x <- as.character(x)
  sample_date <- as.Date(sample_date)
  year_prefix <- ifelse(is.na(sample_date), NA_character_, paste0("25", format(sample_date, "%y")))
  serial <- rep(NA_character_, length(x))
  
  has_influ_serial <- !is.na(x) & grepl("[0-9]{4}[0-9]+$", x)
  serial[has_influ_serial] <- sub("^.*?[0-9]{4}([0-9]+)$", "\\1", x[has_influ_serial], perl = TRUE)
  
  has_fallback_serial <- is.na(serial) & !is.na(x) & grepl("[0-9]+$", x)
  serial[has_fallback_serial] <- sub("^.*?([0-9]+)$", "\\1", x[has_fallback_serial])
  
  out <- rep(NA_character_, length(x))
  valid <- !is.na(year_prefix) & !is.na(serial)
  out[valid] <- paste0(year_prefix[valid], serial[valid])
  out
}

safe_coalesce_chr <- function(...) {
  vals <- list(...)
  out <- as.character(vals[[1]])
  if (length(vals) > 1) {
    for (i in 2:length(vals)) {
      out <- dplyr::coalesce(out, as.character(vals[[i]]))
    }
  }
  as.character(out)
}

repair_text <- function(x) {
  x <- as.character(x)
  
  # SQL text can arrive with mixed encodings and byte placeholders.
  # Repair it once centrally before it is used in joins, mapping, or export.
  # Use sub = "byte" so invalid bytes are preserved as <f8>/<e6>/<e5>
  # instead of being silently dropped, which would turn Trøndelag into Trndelag.
  x_utf8 <- iconv(x, from = "", to = "UTF-8", sub = "byte")
  bad_idx <- is.na(x_utf8) & !is.na(x)
  if (any(bad_idx)) {
    x_utf8[bad_idx] <- iconv(x[bad_idx], from = "latin1", to = "UTF-8", sub = "byte")
  }
  bad_idx <- is.na(x_utf8) & !is.na(x)
  if (any(bad_idx)) {
    x_utf8[bad_idx] <- enc2utf8(x[bad_idx])
  }
  x <- x_utf8
  
  x <- gsub("Ã¸", "ø", x, fixed = TRUE)
  x <- gsub("Ã¦", "æ", x, fixed = TRUE)
  x <- gsub("Ã¥", "å", x, fixed = TRUE)
  x <- gsub("Ã¼", "ü", x, fixed = TRUE)
  x <- gsub("Ã~", "Ø", x, fixed = TRUE)
  x <- gsub("Ã???", "Æ", x, fixed = TRUE)
  x <- gsub("Ã.", "Å", x, fixed = TRUE)
  x <- gsub("Ão", "Ü", x, fixed = TRUE)
  x <- gsub("<f8>", "ø", x, ignore.case = TRUE)
  x <- gsub("<d8>", "Ø", x, ignore.case = TRUE)
  x <- gsub("<e6>", "æ", x, ignore.case = TRUE)
  x <- gsub("<c6>", "Æ", x, ignore.case = TRUE)
  x <- gsub("<e5>", "å", x, ignore.case = TRUE)
  x <- gsub("<c5>", "Å", x, ignore.case = TRUE)
  x <- gsub("<fc>", "ü", x, ignore.case = TRUE)
  x <- gsub("<dc>", "Ü", x, ignore.case = TRUE)
  x
}

repair_character_df <- function(df) {
  df %>%
    mutate(across(where(is.character), repair_text))
}

format_report_date <- function(x) {
  x <- repair_text(x)
  x <- na_if(as.character(x), "")
  parsed <- suppressWarnings(parse_date_time(
    x,
    orders = c("ymd HMS", "ymd HM", "ymd", "dmy HMS", "dmy HM", "dmy"),
    tz = "UTC"
  ))
  out <- ifelse(is.na(parsed), x, format(as.Date(parsed), "%Y-%m-%d"))
  out[is.na(x)] <- NA_character_
  as.character(out)
}

write_report_csv <- function(df, file) {
  write.table(
    df,
    file = file,
    sep = ";",
    row.names = FALSE,
    na = "",
    qmethod = "double",
    fileEncoding = "windows-1252"
  )
}

normalize_name <- function(x) {
  x <- repair_text(x)
  x <- tolower(x)
  x <- gsub("\\?", "", x)
  x <- gsub("%", " prosent ", x)
  x <- gsub("[<>]", " ", x)
  x <- gsub("[^a-z0-9æøå]+", "_", x)
  x <- gsub("^_+|_+$", "", x)
  x
}

analysis_to_assay_groups <- function(x) {
  x_norm <- normalize_name(x)
  has_triplex_marker <- str_detect(x_norm, "triplex|sc2|sars|cov")
  
  out <- character(0)
  
  if (str_detect(x_norm, "h1")) {
    out <- c(out, "H1")
  }
  if (str_detect(x_norm, "h3")) {
    out <- c(out, "H3")
  }
  if (str_detect(x_norm, "vic")) {
    out <- c(out, "BVIC")
  }
  if (str_detect(x_norm, "yam")) {
    out <- c(out, "BYAM")
  }
  if (has_triplex_marker && str_detect(x_norm, "infa")) {
    out <- c(out, "TRIPLEX_INFA")
  }
  if (has_triplex_marker && str_detect(x_norm, "infb")) {
    out <- c(out, "TRIPLEX_INFB")
  }
  if (has_triplex_marker && str_detect(x_norm, "sc2|sars|cov")) {
    out <- c(out, "TRIPLEX_SC2")
  }
  
  unique(out)
}

county_to_landsdel <- c(
  "Østfold" = "Østlandet",
  "Akershus" = "Østlandet",
  "Oslo" = "Østlandet",
  "Buskerud" = "Østlandet",
  "Innlandet" = "Østlandet",
  "Vestfold" = "Østlandet",
  "Telemark" = "Østlandet",
  "Agder" = "Sørlandet",
  "Rogaland" = "Vestlandet",
  "Vestland" = "Vestlandet",
  "Møre og Romsdal" = "Vestlandet",
  "Trøndelag" = "Trøndelag",
  "Nordland" = "Nord-Norge",
  "Troms" = "Nord-Norge",
  "Finnmark" = "Nord-Norge"
)

map_county_to_landsdel <- function(x) {
  out <- unname(county_to_landsdel[as.character(x)])
  out[is.na(x)] <- NA_character_
  out
}

report_configs <- data.frame(
  report_label = c("INF", "SC2", "RSV"),
  batch_pattern = c("^NGS_PREP_INF", "^NGS_PREP_SC2", "^NGS_PREP_RSV"),
  stringsAsFactors = FALSE
)

build_report <- function(report_label, batch_pattern) {
  message("Building NGS_PREP_", report_label, " report using batch pattern: ", batch_pattern)
  
  # ==================================================
  # 1. Pull NGS_PREP tests for this report
  # ==================================================
  
  test_tbl <- tbl(con, Id(schema = "rpt", table = "TEST_VIEW"))
  
  ngs_prep_tests <- test_tbl %>%
    select(TEST_NUMBER, SAMPLE_NUMBER, ANALYSIS, BATCH, BATCH_LINK, STATUS) %>%
    filter(ANALYSIS == "NGS_PREP") %>%
    collect() %>%
    repair_character_df() %>%
    filter(!is.na(BATCH), str_detect(BATCH, batch_pattern))
  
  ngs_prep_sample_numbers <- ngs_prep_tests %>%
    distinct(SAMPLE_NUMBER) %>%
    pull(SAMPLE_NUMBER)
  
  message("NGS_PREP_", report_label, " sample count: ", length(ngs_prep_sample_numbers))
  
  # ==================================================
  # 2. Base sample table, filtered to last 365 days
  # ==================================================
  
  sample_tbl <- tbl(con, Id(schema = "rpt", table = "SAMPLE_VIEW"))
  
  sample_base <- sample_tbl %>%
    select(
      SAMPLE_NUMBER,
      ORDER_NUM,
      TEXT_ID,
      X_INFLU_ID,
      X_CUSTOMER_SAMPLE_ID,
      GROUP_NAME,
      STATUS,
      OLD_STATUS,
      ORIGINAL_SAMPLE,
      PARENT_SAMPLE,
      SAMPLED_DATE,
      RECD_DATE,
      DATE_COMPLETED,
      X_START_APPROVED_ON,
      X_AGENS,
      X_MEDICAL_REVIEW,
      SAMPLE_TYPE,
      SAMPLE_NAME,
      PRIORITY,
      X_SAMPLE_CATEGORY,
      X_SAMPLE_SUBCAT,
      X_SPECIMEN_SOURCE,
      X_REPORT_COMMENTS,
      X_SAMPLE_COMMENT,
      X_ZIPCODE,
      GENDER,
      X_GENDER,
      BIRTH_DATE,
      X_PATIENT_AGE,
      PATIENT,
      FOR_ENTITY,
      PROJECT,
      X_SAMPLE_LOC_ID
    ) %>%
    filter(
      GROUP_NAME == "INFLUENSA",
      !is.na(SAMPLED_DATE)
    ) %>%
    collect() %>%
    filter(SAMPLE_NUMBER %in% ngs_prep_sample_numbers) %>% 
    repair_character_df() %>%
    mutate(SAMPLED_DATE = as.Date(SAMPLED_DATE)) %>%
    filter(SAMPLED_DATE >= date_from, SAMPLED_DATE <= date_to) %>%
    distinct() %>%
    mutate(
      TEXT_ID = as.character(TEXT_ID),
      X_INFLU_ID = as.character(X_INFLU_ID),
      Key = X_INFLU_ID,
      Prove_LW_ID = SAMPLE_NUMBER,
      season_prefix = season_code_from_date(SAMPLED_DATE),
      RekvNr = rekvnr_from_id(X_INFLU_ID, SAMPLED_DATE),
      child_sample = if_else(ORIGINAL_SAMPLE == SAMPLE_NUMBER, "NO", "YES"),
      Prove_Tatt = SAMPLED_DATE,
      Prove_Maanad = month(SAMPLED_DATE),
      Prove_Uke = isoweek(SAMPLED_DATE),
      Sesong = season_prefix,
      Prove_Sesong = season_prefix
    )
  
  message("Base sample rows after date filter: ", nrow(sample_base))
  
  # ==================================================
  # 3. Region info
  # ==================================================
  
  region_tbl <- tbl(con, Id(schema = "rpt", table = "REGION_VIEW"))
  
  region_info <- region_tbl %>%
    select(ZIPCODE, ZIPNAME, REGIONNR, REGION, FYLKESNR, FYLKE, KOMMUNENR, KOMMUNE) %>%
    collect() %>%
    repair_character_df() %>%
    distinct()
  
  sample_base <- sample_base %>%
    left_join(region_info, by = c("X_ZIPCODE" = "ZIPCODE")) %>%
    mutate(
      Pasient_Fylke_Name = FYLKE,
      Pasient_Fylke_Nr = as.character(FYLKESNR),
      Pasient_Landsdel = map_county_to_landsdel(Pasient_Fylke_Name)
    )
  
  # ==================================================
  # 4. Customer info
  # ==================================================
  
  customer_tbl <- tbl(con, Id(schema = "rpt", table = "CUSTOMER_VIEW"))
  
  customer_info <- customer_tbl %>%
    select(NAME, COMPANY_NAME) %>%
    collect() %>%
    repair_character_df() %>%
    distinct()
  
  sample_base <- sample_base %>%
    left_join(customer_info, by = c("FOR_ENTITY" = "NAME")) %>%
    mutate(
      Prove_Innsender_Navn = COMPANY_NAME
    )
  
  # ==================================================
  # 5. Order info
  # ==================================================
  
  orders_tbl <- tbl(con, Id(schema = "rpt", table = "ORDERS_VIEW"))
  
  order_info <- orders_tbl %>%
    select(ORDER_NUM, RECEIVED_ON, X_PATIENT_TYPE) %>%
    collect() %>%
    repair_character_df() %>%
    distinct()
  
  sample_base <- sample_base %>%
    left_join(order_info, by = "ORDER_NUM")
  
  # ==================================================
  # 6. Batch info per sample
  # ==================================================
  
  batch_info <- ngs_prep_tests %>%
    group_by(SAMPLE_NUMBER) %>%
    summarise(
      NGS_Batch_Prep = paste(sort(unique(na.omit(BATCH))), collapse = ","),
      NGS_Batch_Link = paste(sort(unique(na.omit(BATCH_LINK))), collapse = ","),
      NGS_PREP_TEST_STATUS = paste(sort(unique(na.omit(STATUS))), collapse = ","),
      .groups = "drop"
    )
  
  # ==================================================
  # 7. Pull result rows for included samples
  # ==================================================
  
  result_tbl <- tbl(con, Id(schema = "rpt", table = "RESULT_VIEW"))
  
  results_selected <- result_tbl %>%
    select(
      SAMPLE_NUMBER,
      TEST_NUMBER,
      NAME,
      FORMATTED_ENTRY,
      ENTRY,
      ANALYSIS,
      BATCH,
      ENTERED_ON,
      CHANGED_ON
    ) %>%
    collect() %>%
    filter(SAMPLE_NUMBER %in% sample_base$SAMPLE_NUMBER) %>%
    repair_character_df() %>%
    mutate(
      NAME = as.character(NAME),
      FORMATTED_ENTRY = as.character(FORMATTED_ENTRY),
      ENTRY = as.character(ENTRY),
      ANALYSIS = as.character(ANALYSIS),
      NAME_norm = normalize_name(NAME),
      result_value = safe_coalesce_chr(FORMATTED_ENTRY, ENTRY),
      result_value = na_if(result_value, ""),
      result_value = na_if(result_value, "NA")
    ) %>%
    filter(!is.na(result_value))
  
  message("Selected result rows: ", nrow(results_selected))
  
  # ==================================================
  # 8. Generic one-per-name summary for non-PCR fields
  # ==================================================
  
  results_one <- results_selected %>%
    arrange(SAMPLE_NUMBER, NAME_norm, desc(CHANGED_ON), desc(ENTERED_ON)) %>%
    group_by(SAMPLE_NUMBER, NAME_norm) %>%
    summarise(
      result_value = first(result_value),
      .groups = "drop"
    )
  
  results_wide <- results_one %>%
    mutate(
      result_col = case_when(
        NAME_norm == "pasientstatus" ~ "Pasient_Status",
        NAME_norm == "antimikrobiell_behandling" ~ "Pasient_Antiviralbehandling",
        NAME_norm == "første_sykdomsdag" ~ "Pasient_Sykdomsdebut_Dato",
        NAME_norm == "forste_sykdomsdag" ~ "Pasient_Sykdomsdebut_Dato",
        NAME_norm == "utfall" ~ "Pasient_Utfall",
        NAME_norm == "utenlands_siste_7_dager" ~ "Pasient_Utland",
        NAME_norm == "vaksinert_inneværende_sesong" ~ "Pasient_Vaks",
        NAME_norm == "vaksinert_innevarende_sesong" ~ "Pasient_Vaks",
        NAME_norm == "vaksinert_2uker_før_prøvetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_før_prøvetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_for_prøvetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_for_prøvetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_før_provetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_før_provetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_for_provetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2uker_for_provetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_før_prøvetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_før_prøvetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_prøvetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_prøvetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_før_provetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_før_provetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_prøvetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_prøvetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_provetaking" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "vaksinert_2_uker_for_provetakning" ~ "Pasient_Vaks_2uipt",
        NAME_norm == "kliniske_opplysninger" ~ "Pasient_Kommentar",
        NAME_norm == "infprøvekategori" ~ "Prove_Kategori",
        NAME_norm == "infprovekategori" ~ "Prove_Kategori",
        NAME_norm == "agens_testprioritet" ~ "Prove_Prioritet",
        
        NAME_norm == "agens" ~ "Prove_Innsender_Res",
        NAME_norm == "agens_ekstern" ~ "Prove_Innsender_SubRes",
        NAME_norm == "agens_undergruppe" ~ "Prove_Innsender_SubRes2",
        
        NAME_norm == "sekvensid" ~ "NGS_LW_ID",
        NAME_norm == "ngs_status" ~ "NGS_Sekvens_Resultat",
        NAME_norm == "ngs_status_autokommentar" ~ "NGS_Status_Autokommentar",
        NAME_norm == "genotype_fra_skript" ~ "NGS_Genotype_fra_skript",
        NAME_norm == "subtype" ~ "NGS_Subtype",
        NAME_norm == "clade" ~ "NGS_Clade",
        NAME_norm == "kvalitet_på_sekvensen" ~ "NGS_Kvalitet",
        NAME_norm == "kvalitet_pa_sekvensen" ~ "NGS_Kvalitet",
        NAME_norm == "gj_snittlig_dybde" ~ "NGS_Gj_snittlig_dybde",
        NAME_norm == "gj_snittlig_dybde_2" ~ "NGS_Gj_snittlig_dybde_2",
        NAME_norm == "dekning_prosent_av_genomet" ~ "NGS_Dekning_prosent_av_genomet",
        NAME_norm == "rådatafil" ~ "NGS_Raadatafil",
        NAME_norm == "radatafil" ~ "NGS_Raadatafil",
        NAME_norm == "analysekode_ct" ~ "NGS_Analysekode_Ct",
        
        NAME_norm == "ct" ~ "Ct_samlekolonne",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(result_col)) %>%
    select(SAMPLE_NUMBER, result_col, result_value) %>%
    distinct() %>%
    pivot_wider(names_from = result_col, values_from = result_value)
  
  # ==================================================
  # 9. PCR-specific mapping with per-analysis dates
  # ==================================================
  
  pcr_rows <- results_selected %>%
    mutate(
      assay_group = case_when(
        NAME_norm == "ct_h1" ~ "H1",
        NAME_norm == "ct_h3" ~ "H3",
        NAME_norm %in% c("ct_vic", "resultat_vic") ~ "BVIC",
        NAME_norm %in% c("ct_yam", "resultat_yam") ~ "BYAM",
        NAME_norm %in% c("ct_infa", "influensa_a") ~ "TRIPLEX_INFA",
        NAME_norm %in% c("ct_infb", "influensa_b") ~ "TRIPLEX_INFB",
        NAME_norm == "ct_sc2" ~ "TRIPLEX_SC2",
        TRUE ~ NA_character_
      ),
      assay_field = case_when(
        NAME_norm %in% c("ct_h1", "ct_h3", "ct_vic", "ct_yam", "ct_infa", "ct_infb", "ct_sc2") ~ "CT",
        NAME_norm %in% c("resultat_vic", "resultat_yam", "influensa_a", "influensa_b") ~ "RES",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(assay_group), !is.na(assay_field))
  
  pcr_one <- pcr_rows %>%
    arrange(SAMPLE_NUMBER, assay_group, assay_field, desc(CHANGED_ON), desc(ENTERED_ON)) %>%
    group_by(SAMPLE_NUMBER, assay_group, assay_field) %>%
    summarise(
      value = first(result_value),
      .groups = "drop"
    )
  
  pcr_ct_res <- pcr_one %>%
    mutate(
      out_col = case_when(
        assay_group == "H1" & assay_field == "CT" ~ "PCR_H1_CT",
        assay_group == "H1" & assay_field == "RES" ~ "PCR_H1_Res",
        assay_group == "H3" & assay_field == "CT" ~ "PCR_H3_CT",
        assay_group == "H3" & assay_field == "RES" ~ "PCR_H3_Res",
        assay_group == "BVIC" & assay_field == "CT" ~ "PCR_Bvic_CT",
        assay_group == "BVIC" & assay_field == "RES" ~ "PCR_Bvic_Res",
        assay_group == "BYAM" & assay_field == "CT" ~ "PCR_Byam_CT",
        assay_group == "BYAM" & assay_field == "RES" ~ "PCR_Byam_Res",
        assay_group == "TRIPLEX_INFA" & assay_field == "CT" ~ "PCR_triplex_INFA_CT",
        assay_group == "TRIPLEX_INFA" & assay_field == "RES" ~ "PCR_triplex_INFA_Res",
        assay_group == "TRIPLEX_INFB" & assay_field == "CT" ~ "PCR_triplex_INFB_CT",
        assay_group == "TRIPLEX_INFB" & assay_field == "RES" ~ "PCR_triplex_INFB_Res",
        assay_group == "TRIPLEX_SC2" & assay_field == "CT" ~ "PCR_triplex_SC2_CT",
        assay_group == "TRIPLEX_SC2" & assay_field == "RES" ~ "PCR_triplex_SC2_Res",
        TRUE ~ NA_character_
      ),
      out_value = value
    ) %>%
    filter(!is.na(out_col), !is.na(out_value)) %>%
    select(SAMPLE_NUMBER, out_col, out_value) %>%
    distinct() %>%
    pivot_wider(names_from = out_col, values_from = out_value)
  
  pcr_date_rows <- results_selected %>%
    filter(NAME_norm == "analysert_dato_tid") %>%
    arrange(SAMPLE_NUMBER, ANALYSIS, desc(CHANGED_ON), desc(ENTERED_ON)) %>%
    group_by(SAMPLE_NUMBER, ANALYSIS) %>%
    summarise(
      PCR_analysis_date = first(result_value),
      CHANGED_ON = first(CHANGED_ON),
      ENTERED_ON = first(ENTERED_ON),
      .groups = "drop"
    )
  
  pcr_analysis_groups <- pcr_rows %>%
    distinct(SAMPLE_NUMBER, ANALYSIS, assay_group)
  
  pcr_dates_from_results <- pcr_date_rows %>%
    inner_join(pcr_analysis_groups, by = c("SAMPLE_NUMBER", "ANALYSIS"))
  
  pcr_dates_from_analysis_name <- pcr_date_rows %>%
    anti_join(pcr_analysis_groups, by = c("SAMPLE_NUMBER", "ANALYSIS")) %>%
    mutate(assay_group = lapply(ANALYSIS, analysis_to_assay_groups)) %>%
    unnest(assay_group) %>%
    filter(!is.na(assay_group), assay_group != "")
  
  pcr_dates_wide <- bind_rows(
    pcr_dates_from_results,
    pcr_dates_from_analysis_name
  ) %>%
    arrange(SAMPLE_NUMBER, assay_group, desc(CHANGED_ON), desc(ENTERED_ON)) %>%
    group_by(SAMPLE_NUMBER, assay_group) %>%
    summarise(
      PCR_analysis_date = format_report_date(first(PCR_analysis_date)),
      .groups = "drop"
    ) %>%
    mutate(
      out_col = case_when(
        assay_group == "H1" ~ "PCR_H1_Dato",
        assay_group == "H3" ~ "PCR_H3_Dato",
        assay_group == "BVIC" ~ "PCR_Bvic_Dato",
        assay_group == "BYAM" ~ "PCR_Byam_Dato",
        assay_group == "TRIPLEX_INFA" ~ "PCR_triplex_INFA_Dato",
        assay_group == "TRIPLEX_INFB" ~ "PCR_triplex_INFB_Dato",
        assay_group == "TRIPLEX_SC2" ~ "PCR_triplex_SC2_Dato",
        TRUE ~ NA_character_
      ),
      out_value = PCR_analysis_date
    ) %>%
    filter(!is.na(out_col), !is.na(out_value)) %>%
    select(SAMPLE_NUMBER, out_col, out_value) %>%
    distinct() %>%
    pivot_wider(names_from = out_col, values_from = out_value)
  
  pcr_wide <- pcr_ct_res %>%
    full_join(pcr_dates_wide, by = "SAMPLE_NUMBER")
  
  needed_result_cols <- c(
    "Pasient_Status",
    "Pasient_Antiviralbehandling",
    "Pasient_Sykdomsdebut_Dato",
    "Pasient_Utfall",
    "Pasient_Utland",
    "Pasient_Vaks",
    "Pasient_Vaks_2uipt",
    "Pasient_Kommentar",
    "Prove_Kategori",
    "Prove_Prioritet",
    "Prove_Innsender_Res",
    "Prove_Innsender_SubRes",
    "INF_Res",
    "NGS_LW_ID",
    "NGS_Sekvens_Resultat",
    "NGS_Status_Autokommentar",
    "NGS_Genotype_fra_skript",
    "NGS_Subtype",
    "NGS_Clade",
    "NGS_Kvalitet",
    "NGS_Gj_snittlig_dybde",
    "NGS_Gj_snittlig_dybde_2",
    "NGS_Dekning_prosent_av_genomet",
    "NGS_Raadatafil",
    "NGS_Analysekode_Ct",
    "Ct_samlekolonne"
  )
  
  for (nm in setdiff(needed_result_cols, names(results_wide))) {
    results_wide[[nm]] <- NA_character_
  }
  
  needed_pcr_cols <- c(
    "PCR_H1_CT", "PCR_H1_Res", "PCR_H1_Dato",
    "PCR_H3_CT", "PCR_H3_Res", "PCR_H3_Dato",
    "PCR_Bvic_CT", "PCR_Bvic_Res", "PCR_Bvic_Dato",
    "PCR_Byam_CT", "PCR_Byam_Res", "PCR_Byam_Dato",
    "PCR_triplex_INFA_CT", "PCR_triplex_INFA_Res", "PCR_triplex_INFA_Dato",
    "PCR_triplex_INFB_CT", "PCR_triplex_INFB_Res", "PCR_triplex_INFB_Dato",
    "PCR_triplex_SC2_CT", "PCR_triplex_SC2_Res", "PCR_triplex_SC2_Dato"
  )
  
  for (nm in setdiff(needed_pcr_cols, names(pcr_wide))) {
    pcr_wide[[nm]] <- NA_character_
  }
  
  # ==================================================
  # 10. Final report
  # ==================================================
  
  final_report_all_rows <- sample_base %>%
    left_join(batch_info, by = "SAMPLE_NUMBER") %>%
    left_join(results_wide, by = "SAMPLE_NUMBER") %>%
    left_join(pcr_wide, by = "SAMPLE_NUMBER") %>%
    mutate(
      INF_Res = NA_character_,
      Pasient_Alder = coalesce(as.character(X_PATIENT_AGE), as.character(BIRTH_DATE)),
      Pasient_Kjonn = safe_coalesce_chr(X_GENDER, GENDER),
      Pasient_No = as.character(PATIENT),
      Prove_Innsender_ID = as.character(FOR_ENTITY),
      Prove_Kommentar = safe_coalesce_chr(X_SAMPLE_COMMENT, X_REPORT_COMMENTS),
      Prove_Lokalisasjon = as.character(X_SAMPLE_LOC_ID),
      Prove_Material = safe_coalesce_chr(X_SPECIMEN_SOURCE, SAMPLE_TYPE),
      Prove_Prioritet = coalesce(Prove_Prioritet, as.character(PRIORITY)),
      Prove_Tatt_Est = NA_character_,
      Prove_Utbrudd = NA_character_,
      Prove_Vaks = Pasient_Vaks,
      
      PCR_H5_CT = NA_character_,
      PCR_H5_Dato = NA_character_,
      PCR_H5_Res = NA_character_,
      
      Ct_samlekolonne = coalesce(
        Ct_samlekolonne,
        PCR_H1_CT,
        PCR_H3_CT,
        PCR_Bvic_CT,
        PCR_Byam_CT,
        PCR_triplex_INFA_CT,
        PCR_triplex_INFB_CT,
        PCR_triplex_SC2_CT
      ),
      
      Pasient_Aldersgruppe = case_when(
        suppressWarnings(as.numeric(Pasient_Alder)) < 1 ~ "0",
        suppressWarnings(as.numeric(Pasient_Alder)) <= 4 ~ "1-4",
        suppressWarnings(as.numeric(Pasient_Alder)) <= 14 ~ "5-14",
        suppressWarnings(as.numeric(Pasient_Alder)) <= 24 ~ "15-24",
        suppressWarnings(as.numeric(Pasient_Alder)) <= 44 ~ "25-44",
        suppressWarnings(as.numeric(Pasient_Alder)) <= 64 ~ "45-64",
        suppressWarnings(as.numeric(Pasient_Alder)) >= 65 ~ "65+",
        TRUE ~ NA_character_
      )
    ) %>%
    select(
      Key,
      RekvNr,
      Prove_LW_ID,
      INF_Res,
      
      Pasient_Alder,
      Pasient_Aldersgruppe,
      Pasient_Antiviralbehandling,
      Pasient_Fylke_Name,
      Pasient_Fylke_Nr,
      Pasient_Kjonn,
      Pasient_Kommentar,
      Pasient_Landsdel,
      Pasient_No,
      Pasient_Status,
      Pasient_Sykdomsdebut_Dato,
      Pasient_Utfall,
      Pasient_Utland,
      Pasient_Vaks,
      Pasient_Vaks_2uipt,
      
      PCR_Bvic_CT,
      PCR_Bvic_Dato,
      PCR_Bvic_Res,
      PCR_Byam_CT,
      PCR_Byam_Dato,
      PCR_Byam_Res,
      PCR_H1_CT,
      PCR_H1_Dato,
      PCR_H1_Res,
      PCR_H3_CT,
      PCR_H3_Dato,
      PCR_H3_Res,
      PCR_H5_CT,
      PCR_H5_Dato,
      PCR_H5_Res,
      
      Prove_Innsender_ID,
      Prove_Innsender_Navn,
      Prove_Innsender_Res,
      Prove_Innsender_SubRes,
      Prove_Kategori,
      Prove_Kommentar,
      Prove_Lokalisasjon,
      Prove_Material,
      Prove_Prioritet,
      Prove_Sesong,
      Prove_Maanad,
      Prove_Tatt,
      Prove_Tatt_Est,
      Prove_Uke,
      Prove_Utbrudd,
      Prove_Vaks,
      
      NGS_Batch_Prep,
      NGS_Sekvens_Resultat,
      NGS_LW_ID,
      
      Ct_samlekolonne,
      
      PCR_triplex_SC2_CT,
      PCR_triplex_SC2_Dato,
      PCR_triplex_INFA_CT,
      PCR_triplex_INFA_Dato,
      PCR_triplex_INFA_Res,
      PCR_triplex_INFB_CT,
      PCR_triplex_INFB_Dato,
      PCR_triplex_INFB_Res,
      
      NGS_Subtype,
      NGS_Clade,
      NGS_Genotype_fra_skript,
      NGS_Kvalitet,
      NGS_Gj_snittlig_dybde,
      NGS_Gj_snittlig_dybde_2,
      NGS_Dekning_prosent_av_genomet,
      NGS_Raadatafil,
      NGS_Analysekode_Ct,
      Sesong,
      
      SAMPLE_NUMBER,
      X_INFLU_ID,
      SAMPLED_DATE
    ) %>%
    arrange(desc(SAMPLED_DATE), SAMPLE_NUMBER) %>%
    repair_character_df()
  
  final_report <- bind_rows(
    final_report_all_rows %>%
      filter(!is.na(RekvNr), RekvNr != "") %>%
      distinct(RekvNr, .keep_all = TRUE),
    final_report_all_rows %>%
      filter(is.na(RekvNr) | RekvNr == "")
  )
  
  deduplicated_rows <- nrow(final_report_all_rows) - nrow(final_report)
  if (deduplicated_rows > 0) {
    message("Removed duplicate RekvNr rows: ", deduplicated_rows)
  }
  
  # ==================================================
  # 11. Export
  # ==================================================
  
  base_outfile <- file.path(output_dir, paste0("NGS_PREP_", report_label, "_report.csv"))
  
  write_report_csv(final_report, base_outfile)
  
  message("Wrote file: ", base_outfile)
  message("NGS_PREP_", report_label, " final rows: ", nrow(final_report))
  message("NGS_PREP_", report_label, " final cols: ", ncol(final_report))
  
  # ==================================================
  # 12. Quick QC prints
  # ==================================================
  
  print(
    final_report %>%
      select(
        Key, RekvNr, Prove_LW_ID, Prove_Tatt,
        PCR_H1_CT, PCR_H1_Dato, PCR_H1_Res,
        PCR_H3_CT, PCR_H3_Dato, PCR_H3_Res,
        PCR_Bvic_CT, PCR_Bvic_Dato, PCR_Bvic_Res,
        PCR_Byam_CT, PCR_Byam_Dato, PCR_Byam_Res,
        PCR_triplex_INFA_CT, PCR_triplex_INFA_Dato, PCR_triplex_INFA_Res,
        PCR_triplex_INFB_CT, PCR_triplex_INFB_Dato, PCR_triplex_INFB_Res,
        PCR_triplex_SC2_CT, PCR_triplex_SC2_Dato,
        NGS_Sekvens_Resultat, NGS_Subtype, NGS_Clade
      ) %>%
      head(30)
  )
  
  print(
    final_report %>%
      summarise(
        n_rows = n(),
        n_distinct_sample = n_distinct(Prove_LW_ID),
        n_with_h1_date = sum(!is.na(PCR_H1_Dato)),
        n_with_h3_date = sum(!is.na(PCR_H3_Dato)),
        n_with_bvic_date = sum(!is.na(PCR_Bvic_Dato)),
        n_with_byam_date = sum(!is.na(PCR_Byam_Dato)),
        n_with_triplex_infa_date = sum(!is.na(PCR_triplex_INFA_Dato)),
        n_with_triplex_infb_date = sum(!is.na(PCR_triplex_INFB_Dato)),
        n_with_triplex_sc2_date = sum(!is.na(PCR_triplex_SC2_Dato))
      )
  )
  
  invisible(final_report)
}

for (i in seq_len(nrow(report_configs))) {
  build_report(report_configs$report_label[[i]], report_configs$batch_pattern[[i]])
}

DBI::dbDisconnect(con)
