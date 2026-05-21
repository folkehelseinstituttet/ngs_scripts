# SC2 25-26 data cleaning
# Input: SC2_25_26_raw_merged and SC2_20_25
# Output: SC2_25_26_clean, SC2_25_26_prefilter, SC2_25_26, SC2db_prefilter, SC2db

if (!exists("normalize_geography_columns")) {
  source(file.path("Source_files", "common_report_utils.R"))
}

if (!exists("SC2_25_26_raw_merged")) {
  stop("Object 'SC2_25_26_raw_merged' is missing. Source SC2_SQLquery_25-26.R first.")
}
if (!exists("SC2_20_25")) {
  stop("Object 'SC2_20_25' is missing. Source SC2_DataCleaning_BNCOVID19.R first.")
}

SC2_25_26_clean <- SC2_25_26_raw_merged %>%
  select(-any_of(c("levelid", "prkey", "endtcreated", "endtmodif", "objactionid", "objlck", "objowner", "objshared"))) %>%
  filter(is.na(ngs_report) | trimws(ngs_report) == "") %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("^\\s*(?:3|P3(?:_.*)?)\\s*$", ignore_case = TRUE))) %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("ref", ignore_case = TRUE))) %>%
  mutate(
    mut_s_1 = na_if(mut_s_1, "NA"),
    mut_s_2 = na_if(mut_s_2, "NA"),
    mut_s_3 = na_if(mut_s_3, "NA"),
    mut_s_4 = na_if(mut_s_4, "NA")
  ) %>%
  tidyr::unite("spike_mut", mut_s_1, mut_s_2, mut_s_3, mut_s_4, sep = ";", na.rm = TRUE) %>%
  mutate(
    week = lubridate::week(as.Date(prove_tatt)),
    year = lubridate::year(as.Date(prove_tatt)),
    wy = tsibble::yearweek(as.Date(prove_tatt)),
    my = tsibble::yearmonth(as.Date(prove_tatt))
  ) %>%
  filter(prove_tatt != "") %>%
  normalize_geography_columns()

SC2_25_26_prefilter <- SC2_25_26_clean

SC2_25_26 <- SC2_25_26_clean %>%
  filter((nc_coverage == "NA" | nc_coverage >= 0.7) & spike_mut != "")

keys_in_sc2_25_26 <- SC2_25_26$key

SC2_20_25_filtered <- SC2_20_25 %>%
  filter(!key %in% keys_in_sc2_25_26) %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("^\\s*(?:3|P3(?:_.*)?)\\s*$", ignore_case = TRUE))) %>%
  filter(!stringr::str_detect(dplyr::coalesce(prove_kategori, ""), stringr::regex("ref", ignore_case = TRUE)))

SC2_25_26 <- bind_rows(SC2_25_26, SC2_20_25_filtered)

SC2db_prefilter <- SC2_25_26_prefilter
SC2db <- SC2_25_26

if (exists("close_sql_connections")) close_sql_connections()

rm(keys_in_sc2_25_26)
