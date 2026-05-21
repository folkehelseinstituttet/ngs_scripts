# SC2 20-25 data cleaning
# Input: SC2_20_25_raw_merged
# Output: SC2_20_25_clean, SC2_20_25

if (!exists("normalize_geography_columns")) {
  source(file.path("Source_files", "common_report_utils.R"))
}

if (!exists("SC2_20_25_raw_merged")) {
  stop("Object 'SC2_20_25_raw_merged' is missing. Source SC2_SQLquery_BNCOVID19.R first.")
}

SC2_20_25_clean <- SC2_20_25_raw_merged %>%
  tidyr::unite("spike_mut", s, s2, s3, sep = ";", na.rm = TRUE) %>%
  mutate(
    week = lubridate::week(as.Date(prove_tatt)),
    year = lubridate::year(as.Date(prove_tatt)),
    wy = tsibble::yearweek(as.Date(prove_tatt)),
    my = tsibble::yearmonth(as.Date(prove_tatt))
  ) %>%
  mutate(
    coverage_breadth_artic = na_if(coverage_breadth_artic, ""),
    coverage_breadth_swift = na_if(coverage_breadth_swift, ""),
    coverage_breadth_eksterne = na_if(coverage_breadth_eksterne, ""),
    coverage_breadth_nano = na_if(coverage_breadth_nano, ""),
    sekv_oppsett_run_artic = na_if(sekv_oppsett_run_artic, ""),
    sekv_oppsett_nano = na_if(sekv_oppsett_nano, ""),
    sekv_oppsett_sanger = na_if(sekv_oppsett_sanger, ""),
    sekv_oppsett_swift = na_if(sekv_oppsett_swift, "")
  ) %>%
  mutate(
    nc_coverage = coalesce(coverage_breadth_artic, coverage_breadth_swift, coverage_breadth_eksterne, coverage_breadth_nano),
    ngs_run_id = coalesce(sekv_oppsett_run_artic, sekv_oppsett_nano, sekv_oppsett_sanger, sekv_oppsett_swift)
  ) %>%
  {
    if ("ngs_report" %in% names(.)) filter(., is.na(ngs_report) | trimws(ngs_report) == "") else .
  } %>%
  select(
    c(
      "prove_kategori" = "p",
      "pasient_utland" = "reise",
      "prove_tatt" = "prove_tatt",
      "pasient_sykdomsdebut_dato" = "dato_sykdomsdebut",
      "pasient_fylke_name" = "fylkenavn",
      "pasient_landsdel" = "landsdel",
      "prove_lw_id" = "lw_orig_prove",
      "prove_innsender_navn" = "sted",
      "pasient_fylke_nr" = "fylke",
      "pasient_kommentar" = "paskommnt",
      "pasient_aldersgruppe" = "alders_gruppe",
      "pasient_alder" = "alder",
      "pasient_kjnn" = "k",
      "prove_tatt_est" = "sampling_date_est",
      "pasient_status" = "st",
      "pasient_vaks" = "vaks",
      "pasient_antiviralbehandling" = "antiviral_behandling",
      "prove_material" = "materiale",
      "nc_pangolin_short" = "pangolin_nom",
      "nc_clade" = "new_next_strain_nom",
      "pasient_utbrudd" = "utbrudd",
      "pasient_vaks_2uipt" = "vaks2u_fpt",
      "mut_orf1b" = "orf1b",
      "mut_orf1a_3" = "orf3a",
      "mut_e" = "e",
      "mut_orf6" = "orf6",
      "mut_orf7a" = "orf7a",
      "mut_orf7b" = "orf7b",
      "mut_orf8" = "orf8",
      "mut_n" = "n",
      "mut_orf9b" = "orf9b",
      "ngs_instrument_id" = "gisaid_platform",
      "pasient_no" = "pasient_id",
      "nc_pangolin_long" = "full_pango_lineage",
      "key" = "key",
      "prove_kommentar" = "kommentar",
      "nc_coverage",
      "ngs_run_id",
      "year",
      "wy",
      "my",
      "spike_mut"
    )
  ) %>%
  filter(nc_coverage != "") %>%
  filter(prove_tatt != "") %>%
  normalize_geography_columns()

SC2_20_25 <- SC2_20_25_clean %>%
  filter(nc_coverage >= 70) %>%
  filter(nc_pangolin_short != "#BESTILT#") %>%
  filter(nc_pangolin_short != "Inkonklusiv") %>%
  filter(nc_pangolin_short != "inkonklusiv") %>%
  filter(nc_pangolin_short != "Se kommentar") %>%
  filter(nc_pangolin_short != "Seekom") %>%
  filter(nc_pangolin_short != "") %>%
  filter(nc_pangolin_short != "Failed") %>%
  filter(nc_pangolin_short != "failed") %>%
  filter(nc_pangolin_short != "Unassigned")
