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

invisible(timed_step('Source RSV data cleaning', source(file.path(bundle_scripts_dir, 'RSV_DataCleaning_23-24.R'))))

library(dplyr)
library(ggplot2)
library(lubridate)
library(tidyr)
library(scales)
library(officer)
library(openxlsx)
library(patchwork)

invisible(timed_step('Source common report utilities', source('Source_files/common_report_utils.R')))

Sys.setlocale('LC_TIME', 'nb_NO.utf8')

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
    ngs_sekvens_resultat = ifelse(is.na(ngs_sekvens_resultat) | trimws(as.character(ngs_sekvens_resultat)) == '', 'Ukjent', trimws(as.character(ngs_sekvens_resultat))),
    ngs_clade = ifelse(is.na(ngs_clade) | trimws(as.character(ngs_clade)) == '', 'Ukjent', trimws(as.character(ngs_clade))),
    pasient_landsdel = ifelse(is.na(pasient_landsdel) | trimws(as.character(pasient_landsdel)) == '', 'Ukjent', trimws(as.character(pasient_landsdel))),
    pasient_status = ifelse(is.na(pasient_status) | trimws(as.character(pasient_status)) == '', 'Ukjent', trimws(as.character(pasient_status)))
  ) %>%
  filter(!is.na(prove_tatt)) %>%
  filter(prove_tatt >= as.Date('2023-01-01'), prove_tatt <= Sys.Date() + 31)

subclade_col <- if ('ngs_subclade' %in% names(rsvdb)) 'ngs_subclade' else 'ngs_clade'

rsvdb <- rsvdb %>%
  mutate(
    subclade_plot = ifelse(is.na(.data[[subclade_col]]) | trimws(as.character(.data[[subclade_col]])) == '', 'Ukjent', as.character(.data[[subclade_col]])),
    subtype_group = case_when(
      grepl('A', toupper(ngs_sekvens_resultat)) ~ 'RSVA',
      grepl('B', toupper(ngs_sekvens_resultat)) ~ 'RSVB',
      TRUE ~ 'Ukjent'
    ),
    pasient_alder_num = suppressWarnings(as.numeric(trimws(as.character(pasient_alder)))),
    pasient_aldersgruppe = as.character(age_to_group_standard(pasient_alder_num))
  )

rsvdb <- normalize_sex_column(rsvdb, candidate_cols = c('pasient_kjonn', 'pasient_kjnn'))

season_info <- current_and_previous_seasons(Sys.Date())
current_season_label <- season_info$current_label
previous_season_label <- season_info$previous_label

month_levels <- rsvdb %>%
  distinct(month_date, month_label) %>%
  arrange(month_date) %>%
  pull(month_label)

export_graph_f <- read_pptx()
excel_export_sheets <- list()

export_graph_f <- add_section_slide(
  export_graph_f,
  'RSV analyse',
  paste('Rapport med to perioder:', 'Hele tidslinjen', 'og', current_season_label, '(forrige:', previous_season_label, ')')
)

# ------------------------------------------------------------------------------
# Data completeness + QC issues (kept)
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
  duplicate_keys = rsvdb %>% filter(!is.na(key), trimws(as.character(key)) != '') %>% count(key, name = 'n') %>% filter(n > 1) %>% nrow(),
  missing_date_n = sum(is.na(rsvdb$prove_tatt)),
  future_date_n = sum(!is.na(rsvdb$prove_tatt) & rsvdb$prove_tatt > Sys.Date()),
  missing_coverage_n = sum(is.na(suppressWarnings(as.numeric(as.character(rsvdb$ngs_coverage))))),
  missing_subtype_n = sum(is.na(rsvdb$ngs_sekvens_resultat) | trimws(as.character(rsvdb$ngs_sekvens_resultat)) == ''),
  missing_subclade_n = sum(is.na(rsvdb$subclade_plot) | trimws(as.character(rsvdb$subclade_plot)) == ''),
  missing_run_n = sum(is.na(rsvdb$ngs_run_id) | trimws(as.character(rsvdb$ngs_run_id)) == '')
)

qc_summary <- data.frame(metric = names(qc_issues), value = as.numeric(unlist(qc_issues))) %>% arrange(desc(value))

export_graph_f <- save_table_to_ppt(export_graph_f, head(column_profile, 30), 'RSV kolonner med høyest manglende andel')
export_graph_f <- save_table_to_ppt(export_graph_f, qc_summary, 'RSV data quality summary')

excel_export_sheets[['data_completeness']] <- column_profile
excel_export_sheets[['data_issues']] <- qc_summary

# ------------------------------------------------------------------------------
# Run quality issues (SC2 style) mapped to RSV subclade
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Run quality issues',
  'Dekning og QC per NGS run id (farge = NC quality)'
)

run_qc_window <- run_quality_window_bounds(Sys.Date(), min_months = 6L)
run_qc_df <- rsvdb %>%
  filter(!is.na(prove_tatt), prove_tatt >= run_qc_window$start, prove_tatt <= run_qc_window$end) %>%
  prepare_run_qc_df(
    run_col = 'ngs_run_id',
    cov_col = 'ngs_coverage',
    qc_col = 'nc_qc_overall_status',
    virus_col = 'subtype_group',
    color_col = 'nc_qc_overall_status'
  )

run_cov_summary <- run_qc_summary_table(run_qc_df)
if (nrow(run_cov_summary) > 0) {
  export_graph_f <- save_table_to_ppt(
    export_graph_f,
    run_cov_summary,
    paste0('Coverage QC by NGS run - window ', format(run_qc_window$start, '%Y-%m-%d'), ' to ', format(run_qc_window$end, '%Y-%m-%d'))
  )
}

if (!is.null(run_qc_df) && nrow(run_qc_df) > 0) {
  for (v in sort(unique(run_qc_df$virus_group))) {
    if (is.na(v) || trimws(v) == '' || v == 'Ukjent') next
    rv <- run_qc_df %>% filter(virus_group == v)
    p_run_qc <- plot_run_qc_by_run_colorgroup(rv, paste('RSV run quality issues -', v), color_label = 'NC quality')
    if (!is.null(p_run_qc)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_qc)
    p_run_cov <- plot_run_cov_by_run_colorgroup(rv, paste('RSV coverage per run -', v), color_label = 'NC quality')
    if (!is.null(p_run_cov)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_cov)
  }
}

excel_export_sheets[['run_coverage_summary']] <- run_cov_summary
excel_export_sheets[['run_qc_counts']] <- if (is.null(run_qc_df)) data.frame() else run_qc_df %>% count(run_id, virus_group, color_group, name = 'n')

# ------------------------------------------------------------------------------
# Current season monthly: RSV A/B and subtype-specific subclades
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: RSV A/B per måned',
  paste0('Antall og andel - ', current_season_label)
)

rsv_curr <- rsvdb %>%
  filter(season == current_season_label, subtype_group %in% c('RSVA', 'RSVB'), !is.na(month_date))

rsv_ab_month <- rsv_curr %>% count(month_date, subtype_group, name = 'n')
if (nrow(rsv_ab_month) > 0) {
  p_ab_n <- ggplot(rsv_ab_month, aes(x = month_date, y = n, fill = subtype_group)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(rsv_ab_month$subtype_group), kvalitativ_comb)) +
    scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
    labs(title = paste0('RSV A/B per måned (antall) - ', current_season_label), x = 'måned', y = 'Antall (n)', fill = 'Subtype') +
    theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_ab_pct <- rsv_ab_month %>%
    group_by(month_date) %>% mutate(percent = 100 * n / sum(n)) %>% ungroup() %>%
    ggplot(aes(x = month_date, y = percent, fill = subtype_group)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(rsv_ab_month$subtype_group), kvalitativ_comb)) +
    scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
    scale_y_continuous(labels = percent_format(scale = 1)) +
    labs(title = paste0('RSV A/B per måned (andel) - ', current_season_label), x = 'måned', y = 'Andel (%)', fill = 'Subtype') +
    theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_f <- save_plot_to_ppt(export_graph_f, (p_ab_n | p_ab_pct) + plot_layout(guides = 'collect') & theme(legend.position = 'bottom'), title = paste0('RSV A/B per måned - antall + andel (', current_season_label, ')'))
}

for (subtype_id in c('RSVA', 'RSVB')) {
  d <- rsv_curr %>% filter(subtype_group == subtype_id) %>% count(month_date, subclade_plot, name = 'n')
  if (nrow(d) == 0) next

  p_n <- ggplot(d, aes(x = month_date, y = n, fill = subclade_plot)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$subclade_plot), kvalitativ_comb)) +
    scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
    labs(title = paste0(subtype_id, ' by subclade per måned (antall) - ', current_season_label), x = 'måned', y = 'Antall (n)', fill = 'Subclade') +
    theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_pct <- d %>%
    group_by(month_date) %>% mutate(percent = 100 * n / sum(n)) %>% ungroup() %>%
    ggplot(aes(x = month_date, y = percent, fill = subclade_plot)) +
    geom_col() +
    scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$subclade_plot), kvalitativ_comb)) +
    scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
    scale_y_continuous(labels = percent_format(scale = 1)) +
    labs(title = paste0(subtype_id, ' by subclade per måned (andel) - ', current_season_label), x = 'måned', y = 'Andel (%)', fill = 'Subclade') +
    theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_f <- save_plot_to_ppt(export_graph_f, (p_n | p_pct) + plot_layout(guides = 'collect') & theme(legend.position = 'bottom'), title = paste0(subtype_id, ' by subclade per måned - antall + andel (', current_season_label, ')'))
}

excel_export_sheets[['current_season_ab_monthly']] <- rsv_ab_month

# ------------------------------------------------------------------------------
# Whole-season pie comparisons (previous vs current): patient age groups
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Pasient aldersgruppe piesammenligning',
  paste0(previous_season_label, ' vs ', current_season_label)
)

if ('pasient_aldersgruppe' %in% names(rsvdb)) {
  p_age_pie <- build_two_season_pie_compare(
    rsvdb %>% filter(!is.na(pasient_aldersgruppe), trimws(as.character(pasient_aldersgruppe)) != ''),
    season_col = 'season',
    category_col = 'pasient_aldersgruppe',
    previous_label = previous_season_label,
    current_label = current_season_label,
    category_label = 'Pasient aldersgruppe',
    palette_base = kvalitativ_comb
  )
  if (!is.null(p_age_pie)) {
    export_graph_f <- save_plot_to_ppt(export_graph_f, p_age_pie, title = 'Pasient aldersgruppe hele sesongen (n=) - sammenligning')
  }
}

# ------------------------------------------------------------------------------
# Population under surveillance maps (SC2-style current vs previous season)
# ------------------------------------------------------------------------------
if (all(c('pasient_fylke_name', 'pasient_landsdel', 'season') %in% names(rsvdb))) {
  export_graph_f <- add_section_slide(
    export_graph_f,
    'Population Under Surveillance - maps'
  )

  norway_geojson_path <- resolve_norway_geojson_path()
  rsv_prev <- rsvdb %>% filter(season == previous_season_label)
  rsv_curr_map <- rsvdb %>% filter(season == current_season_label)

  p_fylke_prev <- build_fylke_map_plot_shared(
    rsv_prev,
    fylke_col = 'pasient_fylke_name',
    shape_path = norway_geojson_path,
    fill_palette = kvantitativ_b2
  )
  p_fylke_curr <- build_fylke_map_plot_shared(
    rsv_curr_map,
    fylke_col = 'pasient_fylke_name',
    shape_path = norway_geojson_path,
    fill_palette = kvantitativ_b2
  )
  if (!is.null(p_fylke_curr) && !is.null(p_fylke_prev)) {
    p_fylke_pair <- (p_fylke_prev + labs(subtitle = paste0(previous_season_label, ' (m=', scales::comma(nrow(rsv_prev)), ')'))) |
      (p_fylke_curr + labs(subtitle = paste0(current_season_label, ' (m=', scales::comma(nrow(rsv_curr_map)), ')')))
    export_graph_f <- save_plot_to_ppt(export_graph_f, p_fylke_pair, title = 'Map: Fylke fordeling - left previous, right current')
  }

  p_landsdel_prev <- build_landsdel_map_plot_shared(
    rsv_prev,
    fylke_col = 'pasient_fylke_name',
    landsdel_col = 'pasient_landsdel',
    shape_path = norway_geojson_path,
    palette_base = kvalitativ_comb
  )
  p_landsdel_curr <- build_landsdel_map_plot_shared(
    rsv_curr_map,
    fylke_col = 'pasient_fylke_name',
    landsdel_col = 'pasient_landsdel',
    shape_path = norway_geojson_path,
    palette_base = kvalitativ_comb
  )
  if (!is.null(p_landsdel_curr) && !is.null(p_landsdel_prev)) {
    p_landsdel_pair <- (p_landsdel_prev + labs(subtitle = paste0(previous_season_label, ' (m=', scales::comma(nrow(rsv_prev)), ')'))) |
      (p_landsdel_curr + labs(subtitle = paste0(current_season_label, ' (m=', scales::comma(nrow(rsv_curr_map)), ')')))
    export_graph_f <- save_plot_to_ppt(export_graph_f, p_landsdel_pair, title = 'Map: Landsdel fordeling - left previous, right current')
  }
}

# ------------------------------------------------------------------------------
# Shared patient/prove panels (SC2-style)
# ------------------------------------------------------------------------------
if (all(c('prove_tatt', 'subtype_group', 'subclade_plot') %in% names(rsvdb))) {
  rsv_dims <- c(
    'pasient_fylke_name' = 'Fylke',
    'pasient_landsdel' = 'Landsdel',
    'pasient_aldersgruppe' = 'Age group',
    'pasient_status' = 'Patient status'
  )
  rsv_dims <- rsv_dims[names(rsv_dims) %in% names(rsvdb)]

  export_graph_f <- add_section_slide(
    export_graph_f,
    'Population Under Surveillance'
  )

  for (subtype_id in c('RSVA', 'RSVB')) {
    rsv_sub <- rsvdb %>%
      filter(
        season == current_season_label,
        subtype_group == subtype_id,
        !is.na(subclade_plot),
        trimws(as.character(subclade_plot)) != ''
      )
    if (nrow(rsv_sub) == 0) next

    for (dim_col in names(rsv_dims)) {
      dim_label <- rsv_dims[[dim_col]]
      p_pair <- build_group_distribution_plots(
        rsv_sub,
        x_col = dim_col,
        color_col = 'subclade_plot',
        x_label = dim_label,
        color_label = 'Subclade',
        title_prefix = paste0(subtype_id, ' subklade per ', dim_label, ' - gjeldende sesong'),
        palette_base = kvalitativ_comb
      )
      if (is.null(p_pair)) next
      p_combined <- (p_pair$count_plot | p_pair$percent_plot) +
        patchwork::plot_layout(guides = 'collect') &
        theme(legend.position = 'bottom')
      export_graph_f <- save_plot_to_ppt(
        export_graph_f,
        p_combined,
        title = paste0(subtype_id, ' per ', dim_label, ' (antall + andel) - gjeldende sesong')
      )
    }
  }
}

# ------------------------------------------------------------------------------
# Frameshift / insertion / deletion (SC2-style remap: gene x month, faceted by RSVA/RSVB)
# ------------------------------------------------------------------------------
export_graph_f <- add_section_slide(
  export_graph_f,
  'Seksjon: Frameshift, insersjoner og delesjoner',
  'Gene per måned, facettert per RSVA/RSVB'
)

rsv_indel_date_col <- intersect(c('prove_tatt', 'sample_date', 'Sampledate'), names(rsvdb))[1]
rsv_indel_cols <- names(rsvdb)[grepl('(frameshift|insertion|deletion)', names(rsvdb), ignore.case = TRUE)]

infer_gene_label <- function(col_name) {
  x <- toupper(col_name)
  if (grepl('NS1', x)) return('NS1')
  if (grepl('NS2', x)) return('NS2')
  if (grepl('(^|_)N(_|$)', x)) return('N')
  if (grepl('(^|_)P(_|$)', x)) return('P')
  if (grepl('(^|_)M(_|$)', x)) return('M')
  if (grepl('SH', x)) return('SH')
  if (grepl('(^|_)G(_|$)', x)) return('G')
  if (grepl('(^|_)F(_|$)', x)) return('F')
  if (grepl('M2', x)) return('M2')
  if (grepl('(^|_)L(_|$)', x)) return('L')
  sub('^NC_|^MUT_|_MUTATION.*$|_MUT.*$', '', x)
}

if (!is.na(rsv_indel_date_col) && length(rsv_indel_cols) > 0) {
  rsv_long <- rsvdb %>%
    filter(subtype_group %in% c('RSVA', 'RSVB')) %>%
    mutate(indel_month = floor_date(as.Date(.data[[rsv_indel_date_col]]), 'month')) %>%
    filter(!is.na(indel_month)) %>%
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
      mutation_gene = vapply(mutation_col, infer_gene_label, character(1)),
      mutation_label = paste0(mutation_gene, ': ', mutation_raw)
    ) %>%
    filter(mutation_raw != '', !tolower(mutation_raw) %in% c('na', 'n/a', 'none', 'no mutations', 'ikke_satt'))

  totals <- rsv_long %>% distinct(indel_month, subtype_group, .keep_all = TRUE) %>% count(indel_month, subtype_group, name = 'total')
  mut_counts <- rsv_long %>%
    count(indel_month, subtype_group, mutation_gene, name = 'n') %>%
    left_join(totals, by = c('indel_month', 'subtype_group')) %>%
    mutate(percent = 100 * n / total)

  if (nrow(mut_counts) > 0) {
    p_indel <- ggplot(mut_counts, aes(x = indel_month, y = mutation_gene, fill = percent)) +
      geom_tile(color = 'white') +
      facet_wrap(~ subtype_group, ncol = 1, scales = 'free_y') +
      scale_fill_gradientn(colors = kvantitativ_b1, labels = percent_format(scale = 1)) +
      scale_x_date(labels = format_month_label, breaks = scales::date_breaks('1 month')) +
      labs(title = 'Frameshift/Insertion/Deletion andel over tid for RSV (gene-nivå)', subtitle = 'Facettert per RSVA/RSVB', x = '', y = 'RSV-gen', fill = 'Prosent') +
      theme_minimal() + theme(axis.text.x = element_text(angle = 45, hjust = 1))

    export_graph_f <- save_plot_to_ppt(export_graph_f, p_indel, title = 'RSV indel/frameshift trender per gen (facettert)')
    excel_export_sheets[['rsv_indel_counts']] <- mut_counts
  }
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

elapsed_total <- as.numeric(difftime(Sys.time(), analysis_started_at, units = 'secs'))
log_timed_message('TOTAL RUNTIME: ', sprintf('%.2f', elapsed_total), 's')
