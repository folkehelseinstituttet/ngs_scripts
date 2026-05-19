# nolint start
resolve_script_dir <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep('^--file=', args_all, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub('^--file=', '', file_arg[1])
    return(dirname(normalizePath(script_path, winslash = '/', mustWork = FALSE)))
  }
  normalizePath(getwd(), winslash = '/', mustWork = TRUE)
}

bundle_scripts_dir <- resolve_script_dir()
analysis_started_at <- Sys.time()
log_timed_message <- function(...) {
  message(sprintf('[%s]', format(Sys.time(), '%Y-%m-%d %H:%M:%S')), ' ', paste0(..., collapse = ''))
  flush.console()
}
timed_step <- function(step_name, expr) {
  step_started_at <- Sys.time()
  log_timed_message('START: ', step_name)
  result <- force(expr)
  step_elapsed <- as.numeric(difftime(Sys.time(), step_started_at, units = 'secs'))
  log_timed_message('DONE: ', step_name, ' (', sprintf('%.2f', step_elapsed), 's)')
  result
}

invisible(timed_step('Source RSV SQL query', source(file.path(bundle_scripts_dir, 'RSV_SQLquery.R'))))

library(dplyr)
library(ggplot2)
library(lubridate)
library(tidyr)
library(scales)
library(officer)
library(openxlsx)

invisible(timed_step(
  'Source common report utilities',
  source('Source_files/common_report_utils.R')
))
invisible(timed_step(
  'Source shared patient/prove plot helpers',
  source('Source_files/shared_patient_prove_plots.R')
))

Sys.setlocale('LC_TIME', 'nb_NO.utf8')

normalize_norwegian_text <- function(x) {
  x <- iconv(x, from = '', to = 'UTF-8', sub = '')
  x <- ifelse(is.na(x), '', x)
  x
}

parse_prove_tatt <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x[x == ''] <- NA_character_
  parsed <- suppressWarnings(lubridate::parse_date_time(x, orders = c('Y-m-d', 'd.m.Y', 'd/m/Y', 'Y/m/d')))
  as.Date(parsed)
}

rsvdb <- rsvdb %>%
  mutate(
    prove_tatt = parse_prove_tatt(prove_tatt),
    season = season_label_from_date(prove_tatt),
    month_date = floor_date(prove_tatt, unit = 'month'),
    month_label = format_month_label(month_date),
    ngs_sekvens_resultat = na_if(trimws(as.character(ngs_sekvens_resultat)), 'NA'),
    ngs_clade = na_if(trimws(as.character(ngs_clade)), 'NA'),
    ngs_sekvens_resultat = ifelse(is.na(ngs_sekvens_resultat) | ngs_sekvens_resultat == '', 'Ukjent', ngs_sekvens_resultat),
    ngs_clade = ifelse(is.na(ngs_clade) | ngs_clade == '', 'Ukjent', ngs_clade),
    pasient_landsdel = ifelse(is.na(pasient_landsdel) | pasient_landsdel == '', 'Ukjent', pasient_landsdel),
    pasient_status = ifelse(is.na(pasient_status) | pasient_status == '', 'Ukjent', pasient_status)
  ) %>%
  mutate(
    pasient_landsdel = normalize_norwegian_text(pasient_landsdel),
    pasient_landsdel = recode(
      pasient_landsdel,
      'Sorlandet' = 'Sørlandet',
      'Srlandet' = 'Sørlandet',
      'Ostlandet' = 'Østlandet',
      'stlandet' = 'Østlandet',
      'MidtNorge' = 'Midt-Norge',
      'NordNorge' = 'Nord-Norge',
      .default = pasient_landsdel
    )
  ) %>%
  filter(!is.na(prove_tatt)) %>%
  filter(prove_tatt >= as.Date('2023-01-01'), prove_tatt <= Sys.Date() + 31)

month_levels <- rsvdb %>%
  distinct(month_date, month_label) %>%
  arrange(month_date) %>%
  pull(month_label)
season_info <- current_and_previous_seasons(Sys.Date())
current_season_label <- season_info$current_label
previous_season_label <- season_info$previous_label
season_label <- current_season_label
rsvdb_season <- rsvdb %>% filter(season == current_season_label)
season_month_levels <- rsvdb_season %>%
  distinct(month_date, month_label) %>%
  arrange(month_date) %>%
  pull(month_label)

export_graph_f <- read_pptx()
excel_export_sheets <- list()
export_graph_f <- add_section_slide(
  export_graph_f,
  'RSV analyse',
  paste('Rapport med to perioder:', 'Hele tidslinjen', 'og', season_label, '(forrige:', previous_season_label, ')')
)

# ------------------------------------------------------------------------------
# Data completeness + QC issues
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Data completeness og issues',
  'Datakompletthet og kvalitetsavvik'
)

column_profile <- data.frame(
  column_name = names(rsvdb),
  class = vapply(rsvdb, function(x) paste(class(x), collapse = ','), character(1)),
  non_missing_n = vapply(rsvdb, function(x) sum(!is.na(x) & trimws(as.character(x)) != ''), numeric(1)),
  unique_n = vapply(rsvdb, function(x) dplyr::n_distinct(x, na.rm = TRUE), numeric(1))
) %>%
  mutate(
    missing_n = nrow(rsvdb) - non_missing_n,
    missing_pct = round((missing_n / nrow(rsvdb)) * 100, 2)
  ) %>%
  arrange(desc(missing_pct))

qc_issues <- list(
  duplicate_keys = rsvdb %>%
    filter(!is.na(key), trimws(as.character(key)) != '') %>%
    count(key, name = 'n') %>%
    filter(n > 1) %>%
    nrow(),
  missing_date_n = sum(is.na(rsvdb$prove_tatt)),
  future_date_n = sum(!is.na(rsvdb$prove_tatt) & rsvdb$prove_tatt > Sys.Date()),
  missing_coverage_n = sum(is.na(suppressWarnings(as.numeric(as.character(rsvdb$ngs_coverage))))),
  missing_subtype_n = sum(is.na(rsvdb$ngs_sekvens_resultat) | trimws(as.character(rsvdb$ngs_sekvens_resultat)) == ''),
  missing_clade_n = sum(is.na(rsvdb$ngs_clade) | trimws(as.character(rsvdb$ngs_clade)) == ''),
  missing_run_n = sum(is.na(rsvdb$ngs_run_id) | trimws(as.character(rsvdb$ngs_run_id)) == '')
)

qc_summary <- data.frame(
  metric = names(qc_issues),
  value = as.numeric(unlist(qc_issues))
) %>%
  arrange(desc(value))

export_graph_f <- save_table_to_ppt(export_graph_f, head(column_profile, 30), 'RSV kolonner med høyest manglende andel')
export_graph_f <- save_table_to_ppt(export_graph_f, qc_summary, 'RSV data quality summary')

excel_export_sheets[['data_completeness']] <- column_profile
excel_export_sheets[['data_issues']] <- qc_summary

# ------------------------------------------------------------------------------
# Run QC by NGS run id
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Run quality issues',
  'Dekning og QC per NGS run id'
)

run_qc_window <- run_quality_window_bounds(Sys.Date(), min_months = 6L)
rsvdb_run_qc <- rsvdb %>%
  mutate(prove_tatt = as.Date(prove_tatt)) %>%
  filter(!is.na(prove_tatt), prove_tatt >= run_qc_window$start, prove_tatt <= run_qc_window$end)

run_qc_df <- rsvdb_run_qc %>%
  prepare_run_qc_df(
    run_col = 'ngs_run_id',
    cov_col = 'ngs_coverage',
    qc_col = 'nc_qc_overall_status',
    virus_col = 'ngs_sekvens_resultat',
    color_col = 'ngs_clade'
  )

run_cov_summary <- run_qc_summary_table(run_qc_df)

if (nrow(run_cov_summary) > 0) {
  export_graph_f <- save_table_to_ppt(
    export_graph_f,
    run_cov_summary,
    paste0(
      'Coverage QC by NGS run (summary table) - window ',
      format(run_qc_window$start, '%Y-%m-%d'),
      ' to ',
      format(run_qc_window$end, '%Y-%m-%d')
    )
  )
}

if (!is.null(run_qc_df) && nrow(run_qc_df) > 0) {
  for (v in sort(unique(run_qc_df$virus_group))) {
    if (is.na(v) || trimws(v) == '' || v == 'Ukjent') next
    rv <- run_qc_df %>% filter(virus_group == v)
    p_run_qc <- plot_run_qc_by_run_colorgroup(rv, paste('RSV run quality issues -', v), color_label = 'Klade')
    if (!is.null(p_run_qc)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_qc)
    p_run_cov <- plot_run_cov_by_run_colorgroup(rv, paste('RSV coverage per run -', v), color_label = 'Klade')
    if (!is.null(p_run_cov)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_cov)
  }
}

excel_export_sheets[['run_coverage_summary']] <- run_cov_summary
excel_export_sheets[['run_qc_counts']] <- if (is.null(run_qc_df)) data.frame() else run_qc_df %>% count(run_id, virus_group, color_group, name = 'n')

# ------------------------------------------------------------------------------
# Expanded patient metadata plots
# ------------------------------------------------------------------------------
if (FALSE) {
  export_graph_f <- add_section_slide(
    export_graph_f,
    'Seksjon: Pasientmetadata',
    'Alder, kjønn, status og geografi'
  )
}

rsvdb <- rsvdb %>%
  mutate(
    pasient_alder_num = suppressWarnings(as.numeric(trimws(as.character(pasient_alder)))),
    pasient_aldersgruppe = case_when(
      pasient_alder_num >= 0 & pasient_alder_num <= 4 ~ '0-4',
      pasient_alder_num >= 5 & pasient_alder_num <= 14 ~ '5-14',
      pasient_alder_num >= 15 & pasient_alder_num <= 24 ~ '15-24',
      pasient_alder_num >= 25 & pasient_alder_num <= 59 ~ '25-59',
      pasient_alder_num >= 60 ~ '60+',
      TRUE ~ 'Ukjent'
    )
  )

classify_prove_kategori_group <- function(x) {
  x_chr <- trimws(as.character(x))
  dplyr::case_when(
    grepl("^(P1\\b|P1_|1\\b)", x_chr) ~ "Sentinel",
    TRUE ~ "Non-Sentinel"
  )
}

clean_project_code <- function(x) {
  x_chr <- toupper(trimws(as.character(x)))
  x_chr <- gsub("\\s+", "", x_chr)
  x_chr <- ifelse(grepl("^[0-9]+", x_chr), sub("^([0-9]+).*$", "P\\1", x_chr), x_chr)
  x_chr <- ifelse(grepl("^P[0-9]+", x_chr), sub("^(P[0-9]+).*$", "\\1", x_chr), NA_character_)
  x_chr
}

if ("prove_kategori" %in% names(rsvdb)) {
  rsvdb <- rsvdb %>%
    mutate(
      prove_kategori_group = classify_prove_kategori_group(prove_kategori),
      prove_project_clean = ifelse(prove_kategori_group == "Non-Sentinel", clean_project_code(prove_kategori), NA_character_)
    )
}

if ("pasient_kjnn" %in% names(rsvdb)) {
  rsvdb <- rsvdb %>%
    mutate(pasient_kjnn = ifelse(is.na(pasient_kjnn) | trimws(as.character(pasient_kjnn)) == '', 'Ukjent', as.character(pasient_kjnn)))
} else {
  rsvdb$pasient_kjnn <- 'Ukjent'
}

plot_meta_stacked_count <- function(df, x_var, fill_var, title_txt, x_label, fill_label) {
  d <- df %>%
    count(.data[[x_var]], .data[[fill_var]], name = 'n') %>%
    mutate(xv = as.character(.data[[x_var]]), fv = as.character(.data[[fill_var]]))
  if (nrow(d) == 0) return(NULL)
  ggplot(d, aes(x = xv, y = n, fill = fv)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), kvalitativ_comb)) +
    labs(title = title_txt, x = x_label, y = 'Antall (n)', fill = fill_label) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

plot_meta_stacked_pct <- function(df, x_var, fill_var, title_txt, x_label, fill_label) {
  d <- df %>%
    count(.data[[x_var]], .data[[fill_var]], name = 'n') %>%
    group_by(.data[[x_var]]) %>%
    mutate(percent = 100 * n / sum(n)) %>%
    ungroup() %>%
    mutate(xv = as.character(.data[[x_var]]), fv = as.character(.data[[fill_var]]))
  if (nrow(d) == 0) return(NULL)
  ggplot(d, aes(x = xv, y = percent, fill = fv)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), kvalitativ_comb)) +
    scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    labs(title = title_txt, x = x_label, y = 'Andel (%)', fill = fill_label) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
}

if (FALSE) {
  p_age_subtype_n <- plot_meta_stacked_count(rsvdb, 'pasient_aldersgruppe', 'ngs_sekvens_resultat', 'RSV subtype per aldersgruppe (antall)', 'Aldersgruppe', 'Subtype')
  p_age_subtype_pct <- plot_meta_stacked_pct(rsvdb, 'pasient_aldersgruppe', 'ngs_sekvens_resultat', 'RSV subtype per aldersgruppe (andel)', 'Aldersgruppe', 'Subtype')
  p_status_subtype_n <- plot_meta_stacked_count(rsvdb, 'pasient_status', 'ngs_sekvens_resultat', 'RSV subtype per pasientstatus (antall)', 'Pasientstatus', 'Subtype')
  p_status_subtype_pct <- plot_meta_stacked_pct(rsvdb, 'pasient_status', 'ngs_sekvens_resultat', 'RSV subtype per pasientstatus (andel)', 'Pasientstatus', 'Subtype')
  p_landsdel_subtype_n <- plot_meta_stacked_count(rsvdb, 'pasient_landsdel', 'ngs_sekvens_resultat', 'RSV subtype per landsdel (antall)', 'Landsdel', 'Subtype')
  p_landsdel_subtype_pct <- plot_meta_stacked_pct(rsvdb, 'pasient_landsdel', 'ngs_sekvens_resultat', 'RSV subtype per landsdel (andel)', 'Landsdel', 'Subtype')
  p_kjnn_subtype_n <- plot_meta_stacked_count(rsvdb, 'pasient_kjnn', 'ngs_sekvens_resultat', 'RSV subtype per kjønn (antall)', 'Kjønn', 'Subtype')
  p_kjnn_subtype_pct <- plot_meta_stacked_pct(rsvdb, 'pasient_kjnn', 'ngs_sekvens_resultat', 'RSV subtype per kjønn (andel)', 'Kjønn', 'Subtype')

  if (!is.null(p_age_subtype_n)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_age_subtype_n)
  if (!is.null(p_age_subtype_pct)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_age_subtype_pct)
  if (!is.null(p_status_subtype_n)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_status_subtype_n)
  if (!is.null(p_status_subtype_pct)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_status_subtype_pct)
  if (!is.null(p_landsdel_subtype_n)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_subtype_n)
  if (!is.null(p_landsdel_subtype_pct)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_subtype_pct)
  if (!is.null(p_kjnn_subtype_n)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_kjnn_subtype_n)
  if (!is.null(p_kjnn_subtype_pct)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_kjnn_subtype_pct)
}

excel_export_sheets[['patient_age_by_subtype']] <- rsvdb %>% count(pasient_aldersgruppe, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['patient_status_by_subtype']] <- rsvdb %>% count(pasient_status, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['patient_landsdel_by_subtype']] <- rsvdb %>% count(pasient_landsdel, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['patient_kjnn_by_subtype']] <- rsvdb %>% count(pasient_kjnn, ngs_sekvens_resultat, name = 'n')

export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: RSV frekvens og trender',
  'Månedsfordeling av subtype, klade, metadata og kvalitetsmål'
)

subtype_month <- rsvdb %>%
  filter(
    !is.na(ngs_sekvens_resultat),
    trimws(ngs_sekvens_resultat) != "",
    !ngs_sekvens_resultat %in% c("Ukjent", "NA")
  ) %>%
  count(month_date, month_label, ngs_sekvens_resultat, name = 'n') %>%
  group_by(month_date, month_label) %>%
  mutate(percent = 100 * n / sum(n)) %>%
  ungroup()

p_subtype <- ggplot(subtype_month, aes(x = factor(month_label, levels = month_levels), y = percent, fill = ngs_sekvens_resultat)) +
  geom_col() +
  scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(subtype_month$ngs_sekvens_resultat), kvalitativ_comb)) +
  labs(title = 'RSV subtypefordeling per måned', x = 'Måned', y = 'Andel (%)', fill = 'Subtype') +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

export_graph_f <- save_plot_to_ppt(export_graph_f, p_subtype)

clade_month <- rsvdb %>%
  filter(
    !is.na(ngs_sekvens_resultat),
    trimws(ngs_sekvens_resultat) != "",
    !ngs_sekvens_resultat %in% c("Ukjent", "NA")
  ) %>%
  count(month_date, month_label, ngs_sekvens_resultat, ngs_clade, name = 'n') %>%
  group_by(month_date, month_label, ngs_sekvens_resultat) %>%
  mutate(percent = 100 * n / sum(n)) %>%
  ungroup()

for (subtype_name in unique(clade_month$ngs_sekvens_resultat)) {
  d <- clade_month %>% filter(ngs_sekvens_resultat == subtype_name)
  p <- ggplot(d, aes(x = factor(month_label, levels = month_levels), y = percent, fill = ngs_clade)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$ngs_clade), kvalitativ_comb)) +
    labs(title = paste('RSV kladefordeling per måned -', subtype_name), x = 'Måned', y = 'Andel (%)', fill = 'Klade') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p)
}

status_month <- rsvdb %>%
  count(month_date, month_label, pasient_status, name = 'n')
p_status <- ggplot(status_month, aes(x = factor(month_label, levels = month_levels), y = n, fill = pasient_status)) +
  geom_col() +
  scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(status_month$pasient_status), kvalitativ_comb)) +
  labs(title = 'RSV prøver per måned etter pasientstatus', x = 'Måned', y = 'Antall (n)', fill = 'Pasientstatus') +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
export_graph_f <- save_plot_to_ppt(export_graph_f, p_status)

landsdel_month <- rsvdb %>%
  count(month_date, month_label, pasient_landsdel, name = 'n')
p_landsdel <- ggplot(landsdel_month, aes(x = factor(month_label, levels = month_levels), y = n, fill = pasient_landsdel)) +
  geom_col() +
  scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(landsdel_month$pasient_landsdel), kvalitativ_comb)) +
  labs(title = 'RSV prøver per måned etter landsdel', x = 'Måned', y = 'Antall (n)', fill = 'Landsdel') +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel)

ct_type_map <- c(
  "A" = "prove_pcr_rsva_ct",
  "B" = "prove_pcr_rsvb_ct"
)
for (subtype_name in sort(unique(as.character(rsvdb$ngs_sekvens_resultat)))) {
  if (is.na(subtype_name) || trimws(subtype_name) == "" || subtype_name == "Ukjent") next
  subtype_upper <- toupper(subtype_name)
  ct_col <- if (grepl("A", subtype_upper)) ct_type_map[["A"]] else if (grepl("B", subtype_upper)) ct_type_map[["B"]] else NA_character_
  if (is.na(ct_col) || !(ct_col %in% names(rsvdb))) next
  subtype_df <- rsvdb %>% filter(ngs_sekvens_resultat == subtype_name)
  p_ct_subtype <- build_ct_month_plot(
    subtype_df,
    date_col = "month_date",
    ct_col = ct_col,
    color_col = "ngs_clade",
    title_txt = paste("RSV Ct-fordeling per måned -", subtype_name),
    subtitle_txt = paste("Ct-kolonne:", ct_col),
    color_label = "Klade"
  )
  if (!is.null(p_ct_subtype)) {
    export_graph_f <- save_plot_to_ppt(export_graph_f, p_ct_subtype)
  }
}

qc_month <- rsvdb %>%
  mutate(nc_qc_overall_status = ifelse(is.na(nc_qc_overall_status) | nc_qc_overall_status == '', 'Ukjent', nc_qc_overall_status)) %>%
  count(month_date, month_label, nc_qc_overall_status, name = 'n')

p_qc <- ggplot(qc_month, aes(x = factor(month_label, levels = month_levels), y = n, fill = nc_qc_overall_status)) +
  geom_col() +
  scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(qc_month$nc_qc_overall_status), kvalitativ_comb)) +
  labs(title = 'RSV QC-status per måned', x = 'Måned', y = 'Antall (n)', fill = 'QC-status') +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
export_graph_f <- save_plot_to_ppt(export_graph_f, p_qc)

excel_export_sheets[['subtype_monthly']] <- subtype_month %>% arrange(month_date, ngs_sekvens_resultat)
excel_export_sheets[['clade_monthly']] <- clade_month %>% arrange(month_date, ngs_sekvens_resultat, ngs_clade)
excel_export_sheets[['status_monthly']] <- status_month %>% arrange(month_date, pasient_status)
excel_export_sheets[['landsdel_monthly']] <- landsdel_month %>% arrange(month_date, pasient_landsdel)
excel_export_sheets[['qc_monthly']] <- qc_month %>% arrange(month_date, nc_qc_overall_status)
ct_long <- rsvdb %>%
  transmute(month_date, month_label, rsva_ct = suppressWarnings(as.numeric(prove_pcr_rsva_ct)), rsvb_ct = suppressWarnings(as.numeric(prove_pcr_rsvb_ct))) %>%
  pivot_longer(cols = c(rsva_ct, rsvb_ct), names_to = 'ct_type', values_to = 'ct_value') %>%
  filter(!is.na(ct_value))
if (nrow(ct_long) > 0) {
  excel_export_sheets[['ct_long']] <- ct_long %>% arrange(month_date, ct_type)
}

# ------------------------------------------------------------------------------
# Current season only (week 35 to week 34)
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  paste('Seksjon:', season_label),
  paste('Kun', season_label)
)

rsvdb_season <- rsvdb %>% filter(season == current_season_label)
season_month_levels <- rsvdb_season %>%
  distinct(month_date, month_label) %>%
  arrange(month_date) %>%
  pull(month_label)

run_qc_df_season <- rsvdb_season %>%
  prepare_run_qc_df(
    run_col = 'ngs_run_id',
    cov_col = 'ngs_coverage',
    qc_col = 'nc_qc_overall_status',
    virus_col = 'ngs_sekvens_resultat',
    color_col = 'ngs_clade'
  )

run_cov_summary_season <- run_qc_summary_table(run_qc_df_season)

if (nrow(run_cov_summary_season) > 0) {
  export_graph_f <- save_table_to_ppt(export_graph_f, run_cov_summary_season, paste('Coverage QC by NGS run (', season_label, ')'))
}

if (!is.null(run_qc_df_season) && nrow(run_qc_df_season) > 0) {
  for (v in sort(unique(run_qc_df_season$virus_group))) {
    if (is.na(v) || trimws(v) == '' || v == 'Ukjent') next
    rv <- run_qc_df_season %>% filter(virus_group == v)
    p_run_qc_season <- plot_run_qc_by_run_colorgroup(rv, paste('RSV run quality issues -', v, '-', season_label), color_label = 'Klade')
    if (!is.null(p_run_qc_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_qc_season)
    p_run_cov_season <- plot_run_cov_by_run_colorgroup(rv, paste('RSV coverage per run -', v, '-', season_label), color_label = 'Klade')
    if (!is.null(p_run_cov_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_cov_season)
  }
}

if (FALSE) {
  p_age_subtype_n_season <- plot_meta_stacked_count(rsvdb_season, 'pasient_aldersgruppe', 'ngs_sekvens_resultat', paste('RSV subtype per aldersgruppe (antall) -', season_label), 'Aldersgruppe', 'Subtype')
  p_age_subtype_pct_season <- plot_meta_stacked_pct(rsvdb_season, 'pasient_aldersgruppe', 'ngs_sekvens_resultat', paste('RSV subtype per aldersgruppe (andel) -', season_label), 'Aldersgruppe', 'Subtype')
  p_status_subtype_n_season <- plot_meta_stacked_count(rsvdb_season, 'pasient_status', 'ngs_sekvens_resultat', paste('RSV subtype per pasientstatus (antall) -', season_label), 'Pasientstatus', 'Subtype')
  p_status_subtype_pct_season <- plot_meta_stacked_pct(rsvdb_season, 'pasient_status', 'ngs_sekvens_resultat', paste('RSV subtype per pasientstatus (andel) -', season_label), 'Pasientstatus', 'Subtype')
  p_landsdel_subtype_n_season <- plot_meta_stacked_count(rsvdb_season, 'pasient_landsdel', 'ngs_sekvens_resultat', paste('RSV subtype per landsdel (antall) -', season_label), 'Landsdel', 'Subtype')
  p_landsdel_subtype_pct_season <- plot_meta_stacked_pct(rsvdb_season, 'pasient_landsdel', 'ngs_sekvens_resultat', paste('RSV subtype per landsdel (andel) -', season_label), 'Landsdel', 'Subtype')
  p_kjnn_subtype_n_season <- plot_meta_stacked_count(rsvdb_season, 'pasient_kjnn', 'ngs_sekvens_resultat', paste('RSV subtype per kjonn (antall) -', season_label), 'Kjonn', 'Subtype')
  p_kjnn_subtype_pct_season <- plot_meta_stacked_pct(rsvdb_season, 'pasient_kjnn', 'ngs_sekvens_resultat', paste('RSV subtype per kjonn (andel) -', season_label), 'Kjonn', 'Subtype')

  if (!is.null(p_age_subtype_n_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_age_subtype_n_season)
  if (!is.null(p_age_subtype_pct_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_age_subtype_pct_season)
  if (!is.null(p_status_subtype_n_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_status_subtype_n_season)
  if (!is.null(p_status_subtype_pct_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_status_subtype_pct_season)
  if (!is.null(p_landsdel_subtype_n_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_subtype_n_season)
  if (!is.null(p_landsdel_subtype_pct_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_subtype_pct_season)
  if (!is.null(p_kjnn_subtype_n_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_kjnn_subtype_n_season)
  if (!is.null(p_kjnn_subtype_pct_season)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_kjnn_subtype_pct_season)
}

subtype_month_season <- rsvdb_season %>%
  filter(
    !is.na(ngs_sekvens_resultat),
    trimws(ngs_sekvens_resultat) != "",
    !ngs_sekvens_resultat %in% c("Ukjent", "NA")
  ) %>%
  count(month_date, month_label, ngs_sekvens_resultat, name = 'n') %>%
  group_by(month_date, month_label) %>%
  mutate(percent = 100 * n / sum(n)) %>%
  ungroup()

if (nrow(subtype_month_season) > 0) {
  p_subtype_season <- ggplot(subtype_month_season, aes(x = factor(month_label, levels = season_month_levels), y = percent, fill = ngs_sekvens_resultat)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(subtype_month_season$ngs_sekvens_resultat), kvalitativ_comb)) +
    labs(title = paste('RSV subtypefordeling per maned -', season_label), x = 'Maned', y = 'Andel (%)', fill = 'Subtype') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_subtype_season)
}

clade_month_season <- rsvdb_season %>%
  filter(
    !is.na(ngs_sekvens_resultat),
    trimws(ngs_sekvens_resultat) != "",
    !ngs_sekvens_resultat %in% c("Ukjent", "NA")
  ) %>%
  count(month_date, month_label, ngs_sekvens_resultat, ngs_clade, name = 'n') %>%
  group_by(month_date, month_label, ngs_sekvens_resultat) %>%
  mutate(percent = 100 * n / sum(n)) %>%
  ungroup()

for (subtype_name in unique(clade_month_season$ngs_sekvens_resultat)) {
  d <- clade_month_season %>% filter(ngs_sekvens_resultat == subtype_name)
  p <- ggplot(d, aes(x = factor(month_label, levels = season_month_levels), y = percent, fill = ngs_clade)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$ngs_clade), kvalitativ_comb)) +
    labs(title = paste('RSV kladefordeling per maned -', subtype_name, '-', season_label), x = 'Maned', y = 'Andel (%)', fill = 'Klade') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p)
}

status_month_season <- rsvdb_season %>%
  count(month_date, month_label, pasient_status, name = 'n')
if (nrow(status_month_season) > 0) {
  p_status_season <- ggplot(status_month_season, aes(x = factor(month_label, levels = season_month_levels), y = n, fill = pasient_status)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(status_month_season$pasient_status), kvalitativ_comb)) +
    labs(title = paste('RSV prover per maned etter pasientstatus -', season_label), x = 'Maned', y = 'Antall (n)', fill = 'Pasientstatus') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_status_season)
}

landsdel_month_season <- rsvdb_season %>%
  count(month_date, month_label, pasient_landsdel, name = 'n')
if (nrow(landsdel_month_season) > 0) {
  p_landsdel_season <- ggplot(landsdel_month_season, aes(x = factor(month_label, levels = season_month_levels), y = n, fill = pasient_landsdel)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(landsdel_month_season$pasient_landsdel), kvalitativ_comb)) +
    labs(title = paste('RSV prover per maned etter landsdel -', season_label), x = 'Maned', y = 'Antall (n)', fill = 'Landsdel') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_season)
}

for (subtype_name in sort(unique(as.character(rsvdb_season$ngs_sekvens_resultat)))) {
  if (is.na(subtype_name) || trimws(subtype_name) == "" || subtype_name == "Ukjent") next
  subtype_upper <- toupper(subtype_name)
  ct_col <- if (grepl("A", subtype_upper)) "prove_pcr_rsva_ct" else if (grepl("B", subtype_upper)) "prove_pcr_rsvb_ct" else NA_character_
  if (is.na(ct_col) || !(ct_col %in% names(rsvdb_season))) next
  subtype_df <- rsvdb_season %>% filter(ngs_sekvens_resultat == subtype_name)
  p_ct_subtype_season <- build_ct_month_plot(
    subtype_df,
    date_col = "month_date",
    ct_col = ct_col,
    color_col = "ngs_clade",
    title_txt = paste("RSV Ct-fordeling per måned -", subtype_name, "-", season_label),
    subtitle_txt = paste("Ct-kolonne:", ct_col),
    color_label = "Klade"
  )
  if (!is.null(p_ct_subtype_season)) {
    export_graph_f <- save_plot_to_ppt(export_graph_f, p_ct_subtype_season)
  }
}

ct_long_season <- rsvdb_season %>%
  transmute(month_date, month_label, rsva_ct = suppressWarnings(as.numeric(prove_pcr_rsva_ct)), rsvb_ct = suppressWarnings(as.numeric(prove_pcr_rsvb_ct))) %>%
  pivot_longer(cols = c(rsva_ct, rsvb_ct), names_to = 'ct_type', values_to = 'ct_value') %>%
  filter(!is.na(ct_value))

qc_month_season <- rsvdb_season %>%
  mutate(nc_qc_overall_status = ifelse(is.na(nc_qc_overall_status) | nc_qc_overall_status == '', 'Ukjent', nc_qc_overall_status)) %>%
  count(month_date, month_label, nc_qc_overall_status, name = 'n')

if (nrow(qc_month_season) > 0) {
  p_qc_season <- ggplot(qc_month_season, aes(x = factor(month_label, levels = season_month_levels), y = n, fill = nc_qc_overall_status)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(qc_month_season$nc_qc_overall_status), kvalitativ_comb)) +
    labs(title = paste('RSV QC-status per maned -', season_label), x = 'Maned', y = 'Antall (n)', fill = 'QC-status') +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_qc_season)
}

excel_export_sheets[['run_coverage_summary_season']] <- run_cov_summary_season
excel_export_sheets[['run_qc_counts_season']] <- if (is.null(run_qc_df_season)) data.frame() else run_qc_df_season %>% count(run_id, virus_group, color_group, name = 'n')
excel_export_sheets[['pat_age_subtype_season']] <- rsvdb_season %>% count(pasient_aldersgruppe, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['pat_status_subtype_season']] <- rsvdb_season %>% count(pasient_status, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['pat_landsdel_subtype_season']] <- rsvdb_season %>% count(pasient_landsdel, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['pat_kjnn_subtype_season']] <- rsvdb_season %>% count(pasient_kjnn, ngs_sekvens_resultat, name = 'n')
excel_export_sheets[['subtype_monthly_season']] <- subtype_month_season %>% arrange(month_date, ngs_sekvens_resultat)
excel_export_sheets[['clade_monthly_season']] <- clade_month_season %>% arrange(month_date, ngs_sekvens_resultat, ngs_clade)
excel_export_sheets[['status_monthly_season']] <- status_month_season %>% arrange(month_date, pasient_status)
excel_export_sheets[['landsdel_monthly_season']] <- landsdel_month_season %>% arrange(month_date, pasient_landsdel)
excel_export_sheets[['qc_monthly_season']] <- qc_month_season %>% arrange(month_date, nc_qc_overall_status)
if (nrow(ct_long_season) > 0) {
  excel_export_sheets[['ct_long_season']] <- ct_long_season %>% arrange(month_date, ct_type)
}

# SC2-guided harmonized patient/prove panels for RSV
if (all(c('prove_tatt', 'ngs_sekvens_resultat', 'ngs_clade') %in% names(rsvdb))) {
  rsv_dims <- c(
    'pasient_fylke_name' = 'Fylke',
    'pasient_landsdel' = 'Landsdel',
    'pasient_aldersgruppe' = 'Age group',
    'pasient_status' = 'Patient status',
    'prove_kategori_group' = 'Sample category group'
  )
  rsv_dims <- rsv_dims[names(rsv_dims) %in% names(rsvdb)]

  export_graph_f <- add_section_slide(
    export_graph_f,
    'Population Under Surveillance'
  )

  norway_geojson_path <- resolve_norway_geojson_path()
  rsv_prev <- rsvdb %>% filter(season == previous_season_label)
  rsv_curr <- rsvdb %>% filter(season == current_season_label)

  if ('pasient_fylke_name' %in% names(rsvdb)) {
    p_fylke_prev <- build_fylke_map_plot_shared(
      rsv_prev,
      fylke_col = 'pasient_fylke_name',
      shape_path = norway_geojson_path,
      fill_palette = kvantitativ_b2
    )
    p_fylke_curr <- build_fylke_map_plot_shared(
      rsv_curr,
      fylke_col = 'pasient_fylke_name',
      shape_path = norway_geojson_path,
      fill_palette = kvantitativ_b2
    )
    if (!is.null(p_fylke_curr) && !is.null(p_fylke_prev)) {
      p_fylke_pair <- (p_fylke_curr + labs(subtitle = paste0(current_season_label, ' (m=', scales::comma(nrow(rsv_curr)), ')'))) |
        (p_fylke_prev + labs(subtitle = paste0(previous_season_label, ' (m=', scales::comma(nrow(rsv_prev)), ')')))
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_fylke_pair, title = 'Map: Fylke fordeling - left current, right previous')
    }
  }

  if (all(c('pasient_fylke_name', 'pasient_landsdel') %in% names(rsvdb))) {
    p_landsdel_prev <- build_landsdel_map_plot_shared(
      rsv_prev,
      fylke_col = 'pasient_fylke_name',
      landsdel_col = 'pasient_landsdel',
      shape_path = norway_geojson_path,
      palette_base = kvalitativ_comb
    )
    p_landsdel_curr <- build_landsdel_map_plot_shared(
      rsv_curr,
      fylke_col = 'pasient_fylke_name',
      landsdel_col = 'pasient_landsdel',
      shape_path = norway_geojson_path,
      palette_base = kvalitativ_comb
    )
    if (!is.null(p_landsdel_curr) && !is.null(p_landsdel_prev)) {
      p_landsdel_pair <- (p_landsdel_curr + labs(subtitle = paste0(current_season_label, ' (m=', scales::comma(nrow(rsv_curr)), ')'))) |
        (p_landsdel_prev + labs(subtitle = paste0(previous_season_label, ' (m=', scales::comma(nrow(rsv_prev)), ')')))
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_pair, title = 'Map: Landsdel fordeling - left current, right previous')
    }
  }

  if (all(c('pasient_kjnn', 'season') %in% names(rsvdb))) {
    p_kjnn <- build_two_season_pie_compare(
      rsvdb,
      season_col = 'season',
      category_col = 'pasient_kjnn',
      previous_label = previous_season_label,
      current_label = current_season_label,
      category_label = 'Kjønn',
      palette_base = kvalitativ_comb
    )
    if (!is.null(p_kjnn)) {
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_kjnn, title = 'Kjønn: sesongsammenligning')
    }
  }

  if (all(c('pasient_aldersgruppe', 'season') %in% names(rsvdb))) {
    p_alder <- build_two_season_pie_compare(
      rsvdb,
      season_col = 'season',
      category_col = 'pasient_aldersgruppe',
      previous_label = previous_season_label,
      current_label = current_season_label,
      category_label = 'Aldersgruppe',
      palette_base = kvalitativ_comb
    )
    if (!is.null(p_alder)) {
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_alder, title = 'Aldersgruppe: sesongsammenligning')
    }
  }

  for (subtype_name in sort(unique(as.character(rsvdb$ngs_sekvens_resultat)))) {
    if (is.na(subtype_name) || trimws(subtype_name) == '' || subtype_name == 'Ukjent') next
    rsv_sub <- rsvdb %>%
      filter(
        season == current_season_label,
        ngs_sekvens_resultat == subtype_name,
        !is.na(ngs_clade),
        trimws(as.character(ngs_clade)) != ''
      )
    if (nrow(rsv_sub) == 0) next

    for (dim_col in names(rsv_dims)) {
      dim_label <- rsv_dims[[dim_col]]
      p_pair <- build_group_distribution_plots(
        rsv_sub,
        x_col = dim_col,
        color_col = 'ngs_clade',
        x_label = dim_label,
        color_label = 'Clade',
        title_prefix = paste0(subtype_name, ' clade by ', dim_label, ' - current season'),
        palette_base = kvalitativ_comb
      )
      if (is.null(p_pair)) next
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_pair$percent_plot, title = paste0(subtype_name, ' by ', dim_label, ' (%) - current season'))
      export_graph_f <- save_plot_to_ppt(export_graph_f, p_pair$count_plot, title = paste0(subtype_name, ' by ', dim_label, ' (count) - current season'))
    }
  }
}

# ------------------------------------------------------------------------------
# Frameshift/Insertion/Deletion trends (INF blueprint adapted for RSV)
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Frameshift, insersjoner og delesjoner',
  'Kombinert varmekart facettert per mutasjonstype og RSVA/RSVB'
)

rsv_indel_date_col <- intersect(c('prove_tatt', 'sample_date', 'Sampledate'), names(rsvdb))[1]
rsv_indel_cols <- names(rsvdb)[grepl('(frameshift|insertion|deletion)', names(rsvdb), ignore.case = TRUE)]

if (!is.na(rsv_indel_date_col) && length(rsv_indel_cols) > 0) {
  rsv_indel_df <- rsvdb %>%
    mutate(
      indel_plot_date = as.Date(.data[[rsv_indel_date_col]]),
      indel_month = floor_date(indel_plot_date, 'month'),
      subtype_group = case_when(
        grepl('A', toupper(as.character(ngs_sekvens_resultat))) ~ 'RSVA',
        grepl('B', toupper(as.character(ngs_sekvens_resultat))) ~ 'RSVB',
        TRUE ~ 'Ukjent'
      )
    ) %>%
    filter(!is.na(indel_month), subtype_group %in% c('RSVA', 'RSVB'))

  rsv_long <- rsv_indel_df %>%
    pivot_longer(cols = all_of(rsv_indel_cols), names_to = 'mutation_col', values_to = 'mutation_raw') %>%
    filter(!is.na(mutation_raw), trimws(as.character(mutation_raw)) != '') %>%
    separate_rows(mutation_raw, sep = ';|,') %>%
    mutate(
      mutation_raw = trimws(as.character(mutation_raw)),
      mutation_type = case_when(
        grepl('frameshift', mutation_col, ignore.case = TRUE) ~ 'Frameshift',
        grepl('insertion', mutation_col, ignore.case = TRUE) ~ 'Insertion',
        grepl('deletion', mutation_col, ignore.case = TRUE) ~ 'Deletion',
        TRUE ~ 'Other'
      ),
      mutation_gene = sub('^(nc_[^_]+)_.*$', '\\1', mutation_col),
      mutation_label = paste0(mutation_gene, ': ', mutation_raw)
    ) %>%
    filter(
      mutation_raw != '',
      !tolower(mutation_raw) %in% c('na', 'n/a', 'none', 'no mutations', 'ikke_satt')
    )

  rsv_month_totals <- rsv_long %>%
    distinct(indel_month, subtype_group, .keep_all = TRUE) %>%
    count(indel_month, subtype_group, name = 'total')

  rsv_mut_counts <- rsv_long %>%
    group_by(indel_month, subtype_group, mutation_type, mutation_label) %>%
    summarise(n = n(), .groups = 'drop') %>%
    left_join(rsv_month_totals, by = c('indel_month', 'subtype_group')) %>%
    mutate(percent = 100 * n / total)

  if (nrow(rsv_mut_counts) > 0) {
    rsv_indel_heatmap <- ggplot(rsv_mut_counts, aes(x = indel_month, y = mutation_label, fill = percent)) +
      geom_tile(color = 'white') +
      facet_grid(mutation_type ~ subtype_group, scales = 'free_y', space = 'free_y') +
      scale_fill_gradientn(colors = kvantitativ_b1, labels = percent_format(scale = 1)) +
      scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
      labs(
        title = 'Frameshift/Insertion/Deletion andel over tid for RSV',
        subtitle = 'Facettert per mutasjonstype og subtypegruppe (RSVA/RSVB)',
        x = '',
        y = 'Mutasjonssteder',
        fill = 'Prosent'
      ) +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))

    export_graph_f <- save_plot_to_ppt(
      export_graph_f,
      rsv_indel_heatmap,
      title = 'RSV indel/frameshift trender (facettert)'
    )
  } else {
    message('Skipping RSV indel facetted plot: no plottable mutation rows.')
  }
} else {
  message('Skipping RSV indel analysis: missing date column or no frameshift/insertion/deletion columns found.')
}

current_week <- week(Sys.Date())
current_year <- year(Sys.Date())
results_root <- 'N:/Virologi/Influensa/2526/WGS_Analyse/Results'
results_share_root <- 'C:/Users/aroh/OneDrive - Folkehelseinstituttet/Sesong 2025_26'

ppt_name <- paste0('RSV_Week.', current_week, '-', current_year, '_result.pptx')
xlsx_name <- paste0('RSV_Week.', current_week, '-', current_year, '_tabeller.xlsx')

ppt_result <- file.path(results_root, ppt_name)
ppt_share <- file.path(results_share_root, ppt_name)
xlsx_result <- file.path(results_root, xlsx_name)
xlsx_share <- file.path(results_share_root, xlsx_name)

openxlsx::write.xlsx(excel_export_sheets, file = xlsx_result, overwrite = TRUE)
openxlsx::write.xlsx(excel_export_sheets, file = xlsx_share, overwrite = TRUE)

invisible(timed_step('Write PPTX to Results', invisible(capture.output(print(export_graph_f, target = ppt_result)))))
invisible(timed_step('Write PPTX to OneDrive share', invisible(capture.output(print(export_graph_f, target = ppt_share)))))

slide_count <- length(export_graph_f)
cat(sprintf('Excel-tabeller lagret:\n- %s\n- %s\n', xlsx_result, xlsx_share))
cat(sprintf('PowerPoint lagret med %d lysbilder (lysbilde 1-%d):\n- %s\n- %s\n', slide_count, slide_count, ppt_result, ppt_share))

total_elapsed_sec <- as.numeric(difftime(Sys.time(), analysis_started_at, units = 'secs'))
log_timed_message('TOTAL RUNTIME: ', sprintf('%.2f', total_elapsed_sec), 's')
# nolint end
