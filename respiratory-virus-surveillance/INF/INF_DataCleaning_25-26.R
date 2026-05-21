# INF 25-26 data cleaning
# Input: INF_25_26_raw_merged
# Output: INF_25_26_clean, INF_25_26_sequences, fludb

if (!exists("normalize_geography_columns")) {
  source(file.path("Source_files", "common_report_utils.R"))
}

if (!exists("INF_25_26_raw_merged")) {
  stop("Object 'INF_25_26_raw_merged' is missing. Source INF_SQLquery_25-26.R first.")
}

INF_25_26_clean <- INF_25_26_raw_merged %>%
  mutate(prove_tatt = as.Date(prove_tatt, format = "%Y-%m-%d")) %>%
  filter(is.na(ngs_report) | trimws(ngs_report) == "") %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("^\\s*(?:3|P3(?:_.*)?)\\s*$", ignore_case = TRUE))) %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("ref", ignore_case = TRUE))) %>%
  filter(trimws(coalesce(tessy_reportable_variable, "")) != "") %>%
  filter(!stringr::str_detect(dplyr::coalesce(tessy_reportable_variable, ""), stringr::regex("ref", ignore_case = TRUE))) %>%
  as.data.frame() %>%
  normalize_geography_columns()

seq_data_raw <- tbl(conFLU2526, "SEQUENCEDATA") %>%
  collect() %>%
  janitor::clean_names()

seq_filtered <- seq_data_raw %>%
  inner_join(INF_25_26_raw_merged %>% select(key), by = "key") %>%
  filter(grepl("01-HA|02-NA|03-M|04-PB1|05-PB2|07-PA|06-NP|08-NS", experiment)) %>%
  mutate(
    experiment = stringr::str_remove(experiment, "\\d+-"),
    experiment = ifelse(experiment == "M", "MP", experiment)
  ) %>%
  filter(type == "SEQUENCE") %>%
  select(key, experiment, data)

process_entry <- function(data_gz_base64) {
  tryCatch({
    data_gz_raw <- base64enc::base64decode(data_gz_base64)
    data_decompressed <- memDecompress(data_gz_raw, type = "gzip")
    data_decompressed_no_nulls <- data_decompressed[data_decompressed != as.raw(0)]
    data_text_no_nulls <- rawToChar(data_decompressed_no_nulls)
    stringr::str_remove(data_text_no_nulls, "B0t")
  }, error = function(e) {
    message("Error processing entry: ", e$message)
    NA
  })
}

INF_25_26_sequences <- seq_filtered %>%
  mutate(sequence = purrr::map_chr(data, process_entry)) %>%
  mutate(sequence = stringr::str_sub(sequence, start = 3)) %>%
  select(key, experiment, sequence)

# Final pathogen DB object name
fludb <- INF_25_26_clean

if (exists("close_sql_connections")) close_sql_connections()

rm(process_entry, seq_data_raw, seq_filtered)
