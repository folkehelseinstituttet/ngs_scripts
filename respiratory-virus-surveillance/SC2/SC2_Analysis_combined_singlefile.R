# Combined single-file SC2 analysis generated from SC2_Analysis.R and inlined SC2 module scripts.
# Keeps external sources: common_report_utils.R, SC2 SQL query scripts, and SC2_Classification.R.

# ============================================================================
# SARS-COV2 Surveillance
# Author: AR
# Date: 29.04.2026
# ============================================================================

# NOTE:
# This script uses tidy-eval, dynamic columns, and sourced helpers,
# nolint start

resolve_script_dir <- function() {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("^--file=", "", file_arg[1])
    return(dirname(normalizePath(script_path, winslash = "/", mustWork = FALSE)))
  }
  this_file <- tryCatch(normalizePath(sys.frames()[[1]]$ofile, winslash = "/", mustWork = FALSE), error = function(e) "")
  if (nzchar(this_file)) {
    return(dirname(this_file))
  }
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}
bundle_scripts_dir <- resolve_script_dir()
default_results_root <- "N:/Virologi/Influensa/2526/WGS_Analyse/Results"
results_root <- Sys.getenv("SC2_RESULTS_DIR", unset = default_results_root)
results_stats_dir <- Sys.getenv("SC2_RESULTS_STATS_DIR", unset = file.path(results_root, "Statistikk"))
results_share_dir <- Sys.getenv(
  "SC2_RESULTS_SHARE_DIR",
  unset = "C:/Users/aroh/OneDrive - Folkehelseinstituttet/Sesong 2025_26"
)

# ============================================================================
# SETUP - Install and load required packages
# ============================================================================

# Function to check, update, and install packages
check_install_update_packages <- function(packages) {
  installed_pkgs <- rownames(installed.packages())
  missing_packages <- setdiff(packages, installed_pkgs)
  if (length(missing_packages) > 0) {
    message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
    install.packages(missing_packages, dependencies = TRUE)
  }

  # Avoid in-session package updates: they can fail on Windows due to locked DLLs
  # and can trigger namespace unload conflicts (e.g., DBI imported by odbc/RSQLite).
  if (isTRUE(getOption("sc2_update_packages", FALSE))) {
    outdated_packages <- old.packages()
    if (!is.null(outdated_packages)) {
      outdated_required <- intersect(rownames(outdated_packages), packages)
      if (length(outdated_required) > 0) {
        message("Updating outdated required packages: ", paste(outdated_required, collapse = ", "))
        update.packages(oldPkgs = outdated_required, ask = FALSE, checkBuilt = TRUE)
      }
    }
  }
}

# List of required packages
required_packages <- c(
  "odbc", "RSQLite", "DBI", "tidyverse", "lubridate", "ggrepel", "scales",
  "openxlsx", "RColorBrewer", "officer", "tsibble", "patchwork",
  "flextable", "cowplot", "zoo", "reshape2", "janitor", "rvg", "treemapify",
  "data.table", "tools", "knitr"
)

# Use CRAN mirror in Germany for package installs/updates.
options(repos = c(CRAN = "https://cran.uni-muenster.de/"))

# Show warnings immediately and keep error messages visible in terminal.
options(warn = 1, show.error.messages = TRUE)

# Locale guard: set UTF-8 Norwegian locale as early as possible for stable
# rendering of Norwegian characters in plots and slide titles.
init_locale <- function() {
  locale_candidates <- c("nb_NO.UTF-8", "Norwegian (Bokmal)_Norway.utf8", "Norwegian")
  for (loc in locale_candidates) {
    ok <- tryCatch(Sys.setlocale(category = "LC_ALL", locale = loc), error = function(e) NA_character_)
    if (!is.na(ok) && nzchar(ok)) {
      message("Locale set to: ", ok)
      return(invisible(ok))
    }
  }
  warning("Could not set Norwegian UTF-8 locale; continuing with system default locale.")
  invisible(NA_character_)
}
init_locale()

# Restore terminal output if previous runs left active sinks.
while (sink.number() > 0) sink()
while (sink.number(type = "message") != 2) sink(type = "message")

analysis_started_at <- Sys.time()
log_timed_message <- function(...) {
  message(sprintf("[%s]", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), " ", paste0(..., collapse = ""))
  flush.console()
}
timed_step <- function(step_name, expr) {
  step_started_at <- Sys.time()
  log_timed_message("START: ", step_name)
  result <- force(expr)
  step_elapsed <- as.numeric(difftime(Sys.time(), step_started_at, units = "secs"))
  log_timed_message("DONE: ", step_name, " (", sprintf("%.2f", step_elapsed), "s)")
  result
}

load_required_libraries <- function(packages) {
  lapply(packages, function(pkg) {
    withCallingHandlers(
      library(pkg, character.only = TRUE),
      warning = function(w) {
        if (grepl("was built under R version", conditionMessage(w), fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
  })
}

# Call the function to install and update packages
timed_step("Package install/update", check_install_update_packages(required_packages))

# Load libraries
timed_step("Load libraries", load_required_libraries(required_packages))
utils::globalVariables(c(
  ".", ".data", "Tessy_plot", "plot_date", "age_value", "age_group_plot",
  "age_group_raw", "prove_kategori_group", "group_plot", "n", "n_raw",
  "tessy_n", "percent", "kvalitativ_a", "sc2_palette"
))

# Set data.table week option to legacy mode to maintain current behavior
options(datatable.week = "legacy")

# Execute shared report utilities (includes FHI palettes).
timed_step("Source common report utilities", source("Source_files/common_report_utils.R"))
timed_step("Source shared patient/prove plot helpers", source("Source_files/shared_patient_prove_plots.R"))
if (!exists("fhi_discrete_palette", mode = "function")) {
  fhi_discrete_palette <- function(n, palette_name = NULL) {
    base_palette <- if (exists("kvalitativ_comb", inherits = TRUE)) {
      kvalitativ_comb
    } else if (exists("kvalitativ_a", inherits = TRUE)) {
      kvalitativ_a
    } else {
      c("#ec7c73", "#40436d", "#61d2b2", "#a93c38", "#f9dc8c", "#7176c9")
    }
    rep_len(base_palette, n)
  }
  warning("fhi_discrete_palette() not found after sourcing Color palettes.R; using kvalitativ palette fallback.")
}

# ============================================================================
# VARIABLES - Define variables and helper functions
# ============================================================================

# Define the mutations of interest in single or combination heatmap (Spike only)
mutations <- c("Q493E", "F456L", "V1104L", "R346T", "S31-")

start_date <- yearweek(Sys.Date() - weeks(8)) # 4 week period start
end_date <- yearweek(Sys.Date()) # 4 week period end

set_flextable_defaults(font.size = 6)

# Dynamic season boundaries (week 35 -> week 34) based on today's date.
season_info <- current_and_previous_seasons(Sys.Date())
current_season_label <- season_info$current_label
previous_season_label <- season_info$previous_label
current_season_bounds <- season_window_bounds(season_info$current_start_year)
data_window_start <- min(current_season_bounds$start, Sys.Date() %m-% months(6))

Seqlim <- 10 # How many sequences need to be valid per week to include in the analysis
export_graph <- read_pptx() # power point placeholder for the results

# Unified PowerPoint export helper for both ggplot objects and tables.
export_to_ppt <- function(presentation, content, slide_title, layout = "Title and Content", master = "Office Theme") {
  sanitize_xml_text <- function(x) {
    x <- as.character(x)
    gsub("[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]", "", x, perl = TRUE)
  }

  slide_title <- sanitize_xml_text(slide_title)
  presentation <- officer::add_slide(presentation, layout = layout, master = master)
  presentation <- officer::ph_with(presentation, value = slide_title, location = officer::ph_location_type(type = "title"))

  if (inherits(content, "ggplot")) {
    presentation <- officer::ph_with(presentation, value = rvg::dml(ggobj = content), location = officer::ph_location_fullsize())
  } else {
    if (is.data.frame(content)) {
      char_cols <- vapply(content, is.character, logical(1))
      content[char_cols] <- lapply(content[char_cols], sanitize_xml_text)
    } else if (is.character(content)) {
      content <- sanitize_xml_text(content)
    }
    ft <- flextable::flextable(as.data.frame(content)) |> flextable::autofit()
    presentation <- officer::ph_with(presentation, value = ft, location = officer::ph_location_type(type = "body"))
  }

  presentation
}

# Backward-compatible wrappers that route through the single export function.
save_plot <- function(plot, slide_title, export_graph) {
  export_to_ppt(export_graph, plot, slide_title)
}

add_section_slide <- function(presentation, section_title, section_subtitle = NULL) {
  section_plot <- ggplot() +
    annotate("text", x = 0, y = 0.2, label = section_title, size = 11, fontface = "bold", family = "sans") +
    annotate("text", x = 0, y = -0.2, label = ifelse(is.null(section_subtitle), "", section_subtitle), size = 5, family = "sans") +
    xlim(-1, 1) + ylim(-1, 1) +
    theme_void()
  export_to_ppt(presentation, section_plot, section_title)
}

current_week_title <- week(Sys.Date())
current_year_title <- year(Sys.Date())
title_plot <- ggplot() +
  annotate("text", x = 0, y = 0.2, label = "SARS-CoV-2-overv\u00e5king", size = 13, fontface = "bold", family = "sans") +
  annotate("text", x = 0, y = -0.1, label = paste0("Uke ", current_week_title, " - ", current_year_title), size = 8, family = "sans") +
  xlim(-1, 1) + ylim(-1, 1) +
  theme_void()

export_graph <- export_to_ppt(export_graph, title_plot, paste0("SARS-CoV-2 Uke ", current_week_title))
export_graph <- add_section_slide(export_graph, "Datakvalitetskontroller", "Dataintegritet, kompletthet og konsistens")



# ============================================================================
# DATA LOAD - SQL (BN)
# ============================================================================

timed_step("Source SC2_SQLquery_BNCOVID19.R", source(file.path(bundle_scripts_dir, "SC2_SQLquery_BNCOVID19.R")))
timed_step("Source SC2_SQLquery_25-26.R", source(file.path(bundle_scripts_dir, "SC2_SQLquery_25-26.R")))
timed_step("Source SC2_Classification.R", source(file.path(bundle_scripts_dir, "SC2_Classification.R")))

# Harmonized sample-category classification:
# P1/P1_* or 1* -> Sentinel; everything else -> Non-Sentinel.
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

if (exists("SC2db_v")) {
  SC2db_v <- SC2db_v %>%
    mutate(
      prove_tatt = as.Date(prove_tatt),
      season = season_label_from_date(prove_tatt),
      prove_kategori_group = classify_prove_kategori_group(prove_kategori),
      prove_project_clean = ifelse(prove_kategori_group == "Non-Sentinel", clean_project_code(prove_kategori), NA_character_)
    )
}

if (exists("SC2db")) {
  SC2db <- SC2db %>%
    mutate(
      prove_tatt = as.Date(prove_tatt),
      season = season_label_from_date(prove_tatt),
      prove_kategori_group = classify_prove_kategori_group(prove_kategori),
      prove_project_clean = ifelse(prove_kategori_group == "Non-Sentinel", clean_project_code(prove_kategori), NA_character_)
    )
}

# NOTE: Initial standalone run-quality section removed.
# Run-quality outputs are consolidated under the single
# "Run Quality Issues" section below.

# ============================================================================
# EXTENDED SC2 PATIENT/TESSY EXPLORATION + DATA QUALITY (SC2db_v)
# ============================================================================

# Helper for Tessy distribution plots used in the early SC2 QC block.
build_tessy_group_plots <- function(df, x_col, x_label, export_graph_in) {
  required_cols <- c("plot_date_window", "Tessy_plot", x_col)
  if (any(!required_cols %in% names(df))) {
    return(export_graph_in)
  }

  plot_df <- df %>%
    mutate(season_plot = season_label_from_date(plot_date_window)) %>%
    filter(
      !is.na(plot_date_window),
      season_plot == current_season_label,
      !is.na(Tessy_plot),
      trimws(Tessy_plot) != "",
      !is.na(.data[[x_col]]),
      trimws(as.character(.data[[x_col]])) != "",
      as.character(.data[[x_col]]) != "IKKE_SATT"
    ) %>%
    mutate(group_plot = as.character(.data[[x_col]]))

  if (nrow(plot_df) == 0) {
    return(export_graph_in)
  }

  grouped_df <- plot_df %>%
    count(group_plot, Tessy_plot, name = "n") %>%
    group_by(group_plot) %>%
    mutate(percent = (n / sum(n)) * 100) %>%
    ungroup()

  x_labels_df <- grouped_df %>%
    group_by(group_plot) %>%
    summarise(group_n = sum(n), .groups = "drop") %>%
    arrange(desc(group_n), group_plot) %>%
    mutate(group_label = paste0(group_plot, " (n=", group_n, ")"))

  grouped_df <- grouped_df %>%
    left_join(x_labels_df, by = "group_plot") %>%
    mutate(group_label = factor(group_label, levels = x_labels_df$group_label))

  p_pct <- ggplot(grouped_df, aes(x = group_label, y = percent, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    coord_cartesian(ylim = c(0, 100)) +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(
      title = paste0("Tessy-fordeling per ", x_label, " (%) - gjeldende sesong"),
      x = x_label,
      y = "Andel (%)",
      fill = "Tessy"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_count <- ggplot(grouped_df, aes(x = group_label, y = n, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(
      title = paste0("Tessy-fordeling per ", x_label, " (antall) - gjeldende sesong"),
      x = x_label,
      y = "Antall (n)",
      fill = "Tessy"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_out <- export_to_ppt(export_graph_in, p_pct, paste0("Tessy per ", x_label, " (%) - gjeldende sesong"))
  export_graph_out <- export_to_ppt(export_graph_out, p_count, paste0("Tessy per ", x_label, " (antall) - gjeldende sesong"))
  export_graph_out
}

eda_source_df <- if (exists("SC2db_v")) SC2db_v else SC2db
results_dir_stats <- results_stats_dir
current_week_eda <- week(Sys.Date())
current_year_eda <- year(Sys.Date())

eda_tessy_col <- intersect(c("Tessy", "tessy"), names(eda_source_df))[1]
eda_date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(eda_source_df))[1]
eda_cov_col <- intersect(c("nc_coverage", "coverage_breadth_artic", "coverage_breadth_swift", "coverage_breadth_eksterne", "coverage_breadth_nano"), names(eda_source_df))[1]
eda_key_col <- intersect(c("key", "KEY"), names(eda_source_df))[1]
eda_origin_col <- intersect(c("Origin", "origin"), names(eda_source_df))[1]

if (!is.na(eda_tessy_col)) {
  has_pk_group_col <- "prove_kategori_group" %in% names(eda_source_df)
  has_prove_kat_col <- "prove_kategori" %in% names(eda_source_df)
  has_pas_status_col <- "pasient_status" %in% names(eda_source_df)
  has_pas_vaks_col <- "pasient_vaks" %in% names(eda_source_df)
  has_pas_vaks_2u_col <- "pasient_vaks_2uipt" %in% names(eda_source_df)

  eda_df <- eda_source_df %>%
    mutate(
      plot_date_window = if (!is.na(eda_date_col)) as.Date(.data[[eda_date_col]]) else as.Date(NA),
      Tessy_plot = as.character(.data[[eda_tessy_col]]),
      prove_kategori_raw = if (has_prove_kat_col) as.character(prove_kategori) else NA_character_,
      prove_kategori_group = ifelse(
        if (has_pk_group_col) is.na(prove_kategori_group) else TRUE,
        classify_prove_kategori_group(prove_kategori_raw),
        if (has_pk_group_col) as.character(prove_kategori_group) else "Non-Sentinel"
      ),
      pasient_status_plot = if (has_pas_status_col) ifelse(is.na(pasient_status) | pasient_status == "" | pasient_status == "IKKE_SATT", "Ukjent", as.character(pasient_status)) else "Ukjent",
      pasient_vaks_plot = if (has_pas_vaks_col) ifelse(is.na(pasient_vaks) | trimws(as.character(pasient_vaks)) == "", "Ukjent", as.character(pasient_vaks)) else "Ukjent",
      pasient_vaks_2uipt_plot = if (has_pas_vaks_2u_col) ifelse(is.na(pasient_vaks_2uipt) | trimws(as.character(pasient_vaks_2uipt)) == "", "Ukjent", as.character(pasient_vaks_2uipt)) else "Ukjent"
    ) %>%
    filter(!is.na(plot_date_window), plot_date_window >= data_window_start)

  # NOTE: Patient status / sample category / vaccination Tessy plots are created
  # in the dedicated patient section later in the report.

  column_profile <- data.frame(
    column_name = names(eda_df),
    class = vapply(eda_df, function(x) paste(class(x), collapse = ","), character(1)),
    non_missing_n = vapply(eda_df, function(x) sum(!is.na(x) & trimws(as.character(x)) != ""), numeric(1)),
    unique_n = vapply(eda_df, function(x) dplyr::n_distinct(x, na.rm = TRUE), numeric(1))
  ) %>%
    mutate(
      missing_n = nrow(eda_df) - non_missing_n,
      missing_pct = round((missing_n / nrow(eda_df)) * 100, 2)
    ) %>%
    arrange(desc(missing_pct))

  # Data quality checks and outliers.
  qc_issues <- list()

  if (!is.na(eda_key_col)) {
    dup_key_df <- eda_df %>%
      filter(!is.na(.data[[eda_key_col]]), trimws(as.character(.data[[eda_key_col]])) != "") %>%
      count(.data[[eda_key_col]], name = "n") %>%
      filter(n > 1) %>%
      arrange(desc(n))
    qc_issues[["duplicate_keys"]] <- nrow(dup_key_df)
    if (nrow(dup_key_df) > 0) {
      export_graph <- export_to_ppt(export_graph, head(dup_key_df, 30), "SC2 duplicate key candidates")
    }
  }

  if (!is.na(eda_date_col)) {
    date_qc_df <- eda_df %>%
      mutate(plot_date = as.Date(.data[[eda_date_col]])) %>%
      summarise(
        missing_date_n = sum(is.na(plot_date)),
        future_date_n = sum(!is.na(plot_date) & plot_date > Sys.Date()),
        pre_2020_n = sum(!is.na(plot_date) & plot_date < as.Date("2020-01-01"))
      )
    qc_issues[["missing_date_n"]] <- date_qc_df$missing_date_n
    qc_issues[["future_date_n"]] <- date_qc_df$future_date_n
    qc_issues[["pre_2020_n"]] <- date_qc_df$pre_2020_n
  }

  age_qc_col <- intersect(c("pasient_alder", "pasient_age", "age", "alder"), names(eda_df))[1]
  if (!is.na(age_qc_col)) {
    age_qc_df <- eda_df %>%
      mutate(age_value = suppressWarnings(as.numeric(as.character(.data[[age_qc_col]])))) %>%
      summarise(
        missing_age_n = sum(is.na(age_value)),
        age_lt_0_n = sum(!is.na(age_value) & age_value < 0),
        age_gt_110_n = sum(!is.na(age_value) & age_value > 110)
      )
    qc_issues[["missing_age_n"]] <- age_qc_df$missing_age_n
    qc_issues[["age_lt_0_n"]] <- age_qc_df$age_lt_0_n
    qc_issues[["age_gt_110_n"]] <- age_qc_df$age_gt_110_n
  }

  if (!is.na(eda_cov_col)) {
    cov_qc_df <- eda_df %>%
      mutate(coverage_value = suppressWarnings(as.numeric(as.character(.data[[eda_cov_col]])))) %>%
      summarise(
        missing_cov_n = sum(is.na(coverage_value)),
        cov_lt_0_n = sum(!is.na(coverage_value) & coverage_value < 0),
        cov_gt_100_n = sum(!is.na(coverage_value) & coverage_value > 100),
        cov_between_1_100_n = sum(!is.na(coverage_value) & coverage_value > 1 & coverage_value <= 100),
        cov_between_0_1_n = sum(!is.na(coverage_value) & coverage_value >= 0 & coverage_value <= 1)
      )
    qc_issues[["missing_cov_n"]] <- cov_qc_df$missing_cov_n
    qc_issues[["cov_lt_0_n"]] <- cov_qc_df$cov_lt_0_n
    qc_issues[["cov_gt_100_n"]] <- cov_qc_df$cov_gt_100_n
    qc_issues[["cov_between_1_100_n"]] <- cov_qc_df$cov_between_1_100_n
    qc_issues[["cov_between_0_1_n"]] <- cov_qc_df$cov_between_0_1_n
  }

  if (!is.na(eda_tessy_col)) {
    tessy_vec <- as.character(eda_df[[eda_tessy_col]])
    qc_issues[["missing_tessy_n"]] <- sum(is.na(tessy_vec) | trimws(tessy_vec) == "")
  }

  qc_summary <- data.frame(
    metric = names(qc_issues),
    value = as.numeric(unlist(qc_issues))
  ) %>%
    arrange(desc(value))
  export_graph <- export_to_ppt(export_graph, qc_summary, "SC2 data quality summary")
  export_graph <- export_to_ppt(export_graph, head(column_profile, 30), "SC2 SC2db_v: highest missingness columns")

  # Numeric outlier scan (IQR-based):
  # include numeric-like columns (comma/dot aware), exclude ID/code fields.
  parse_numeric_locale <- function(v) {
    x <- as.character(v)
    x <- trimws(x)
    x[x == "" | toupper(x) %in% c("NA", "NAN")] <- NA_character_
    x <- gsub(",", ".", x, fixed = TRUE)
    suppressWarnings(as.numeric(x))
  }
  is_id_or_code_col <- function(nm) {
    nm_l <- tolower(nm)
    grepl("(key|lwid|lw_id|sekv.*id|sample.*id|run.*id|(^|_)id($|_))", nm_l) ||
      nm_l %in% c("week", "year", "isoweek", "isoyear", "prove_uke", "prove_sesong", "prove_kategori", "pasient_fylke_nr", "pasient_no")
  }

  all_cols <- names(eda_df)
  candidate_cols <- all_cols[!vapply(all_cols, is_id_or_code_col, logical(1))]
  if (length(candidate_cols) > 0) {
    parsed_map <- lapply(candidate_cols, function(col_name) {
      raw <- eda_df[[col_name]]
      if (is.numeric(raw)) {
        x <- as.numeric(raw)
      } else {
        x <- parse_numeric_locale(raw)
      }
      non_missing_raw <- sum(!is.na(raw) & trimws(as.character(raw)) != "")
      parse_rate <- if (non_missing_raw > 0) sum(!is.na(x)) / non_missing_raw else 0
      list(col = col_name, x = x, parse_rate = parse_rate)
    })
    names(parsed_map) <- candidate_cols
    numeric_cols <- names(parsed_map)[vapply(parsed_map, function(z) z$parse_rate >= 0.8, logical(1))]

    outlier_scan <- lapply(numeric_cols, function(col_name) {
      x <- parsed_map[[col_name]]$x
      x <- x[!is.na(x) & is.finite(x)]
      if (length(x) < 10) return(NULL)
      q1 <- as.numeric(quantile(x, 0.25, na.rm = TRUE))
      q3 <- as.numeric(quantile(x, 0.75, na.rm = TRUE))
      iqr <- q3 - q1
      lower <- q1 - 1.5 * iqr
      upper <- q3 + 1.5 * iqr
      out_n <- sum(x < lower | x > upper, na.rm = TRUE)
      data.frame(
        column_name = col_name,
        n = length(x),
        outlier_n = out_n,
        outlier_pct = round((out_n / length(x)) * 100, 2),
        min = min(x, na.rm = TRUE),
        p25 = q1,
        median = median(x, na.rm = TRUE),
        p75 = q3,
        max = max(x, na.rm = TRUE)
      )
    }) %>%
      bind_rows() %>%
      arrange(desc(outlier_pct), desc(outlier_n))

    if (nrow(outlier_scan) > 0) {
      export_graph <- export_to_ppt(export_graph, head(outlier_scan, 30), "SC2 numeric outlier scan (IQR)")
    } else {
      outlier_msg <- data.frame(
        note = "No numeric columns with >=10 non-missing values after exclusions (week/year removed).",
        numeric_columns_found = length(numeric_cols),
        stringsAsFactors = FALSE
      )
      export_graph <- export_to_ppt(export_graph, outlier_msg, "SC2 numeric outlier scan (IQR)")
    }
  } else {
    outlier_msg <- data.frame(
      note = "No numeric columns found for outlier scan after exclusions (week/year removed).",
      numeric_columns_found = 0L,
      stringsAsFactors = FALSE
    )
    export_graph <- export_to_ppt(export_graph, outlier_msg, "SC2 numeric outlier scan (IQR)")
  }
}

# ============================================================================
# NGS COVERAGE PERFORMANCE BY RUN SETUP / RUN ID
# ============================================================================
export_graph <- add_section_slide(export_graph, "Run Quality Issues", "Run setup pass/fail and operational quality")

ngs_qc_source <- if (exists("SC2db_v")) SC2db_v else if (exists("SC2db_prefilter")) SC2db_prefilter else if (exists("SC2db")) SC2db else NULL

if (!is.null(ngs_qc_source)) {
  current_week_ngs <- week(Sys.Date())
  current_year_ngs <- year(Sys.Date())
  ngs_date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(ngs_qc_source))[1]
  ngs_cov_col <- intersect(c("nc_coverage", "coverage_breadth_artic", "coverage_breadth_swift", "coverage_breadth_eksterne", "coverage_breadth_nano"), names(ngs_qc_source))[1]
  ngs_run_col <- intersect(c("ngs_run_id", "sekv_oppsett_run_artic", "sekv_oppsett_nano", "sekv_oppsett_sanger", "sekv_oppsett_swift"), names(ngs_qc_source))[1]
  ngs_tessy_col <- intersect(c("Tessy", "tessy"), names(ngs_qc_source))[1]
  ngs_subclade_col <- intersect(c("nc_pangolin_short", "NC_Pangolin Short", "nc_clade", "nc_nextclade", "Tessy", "tessy"), names(ngs_qc_source))[1]

  if (!is.na(ngs_cov_col) && !is.na(ngs_run_col)) {
    ngs_qc_df <- ngs_qc_source %>%
      mutate(
        run_setup = as.character(.data[[ngs_run_col]]),
        plot_date = if (!is.na(ngs_date_col)) as.Date(.data[[ngs_date_col]]) else as.Date(NA),
        Tessy_plot = if (!is.na(ngs_tessy_col)) as.character(.data[[ngs_tessy_col]]) else NA_character_,
        cov_raw = as.character(.data[[ngs_cov_col]]),
        cov_num = suppressWarnings(as.numeric(cov_raw)),
        cov_norm = ifelse(!is.na(cov_num) & cov_num > 1.5, cov_num / 100, cov_num),
        spike_ok = if ("Spike_mut" %in% names(.)) (!is.na(Spike_mut) & trimws(as.character(Spike_mut)) != "") else TRUE,
        # Match SC2db_v inclusion rule from SC2_SQLquery_25-26.
        include_by_coverage = (!is.na(cov_raw) & cov_raw == "NA") | (!is.na(cov_norm) & cov_norm >= 0.7),
        include_flag = include_by_coverage & spike_ok,
        qc_status = ifelse(include_flag, "Included_in_SC2db_v", "Failed_threshold_or_missing")
      ) %>%
      filter(!is.na(run_setup), trimws(run_setup) != "", run_setup != "Ukjent")

    ngs_perf <- ngs_qc_df %>%
      count(run_setup, qc_status, name = "n") %>%
      group_by(run_setup) %>%
      mutate(percent = (n / sum(n)) * 100) %>%
      ungroup()

    if (nrow(ngs_perf) > 0) {
      run_levels <- ngs_perf %>%
        distinct(run_setup) %>%
        mutate(
          run_num = suppressWarnings(as.numeric(stringr::str_extract(run_setup, "\\d+"))),
          run_suffix = toupper(stringr::str_extract(run_setup, "[A-Za-z]+$")),
          suffix_rank = dplyr::case_when(
            is.na(run_suffix) | run_suffix == "" ~ 0,
            run_suffix == "A" ~ 1,
            run_suffix == "B" ~ 2,
            TRUE ~ 3
          )
        ) %>%
        arrange(is.na(run_num), run_num, suffix_rank, run_setup) %>%
        pull(run_setup)

      # Keep only run setups represented by samples from the last 12 months.
      run_levels_last12m <- ngs_qc_df %>%
        filter(!is.na(plot_date), plot_date >= (Sys.Date() %m-% months(12))) %>%
        distinct(run_setup) %>%
        pull(run_setup) %>%
        as.character()
      run_levels_last12m <- run_levels[run_levels %in% run_levels_last12m]

      if (length(run_levels_last12m) == 0) {
        run_levels_last12m <- run_levels
      }
      ngs_qc_df <- ngs_qc_df %>%
        filter(run_setup %in% run_levels_last12m) %>%
        mutate(run_setup = factor(run_setup, levels = run_levels_last12m))
      ngs_perf <- ngs_perf %>%
        filter(run_setup %in% run_levels_last12m) %>%
        mutate(run_setup = factor(run_setup, levels = run_levels_last12m))

      p_ngs_perf_pct <- ggplot(ngs_perf, aes(x = run_setup, y = percent, fill = qc_status)) +
        geom_col(position = "stack") +
        scale_fill_manual(values = fhi_discrete_palette(n_distinct(ngs_perf$qc_status), sc2_palette)) +
        scale_y_continuous(labels = scales::percent_format(scale = 1)) +
        coord_cartesian(ylim = c(0, 100)) +
        labs(
          title = "NGS run setup: proportion included vs failed",
          x = "NGS-runoppsett / run-id",
          y = "Andel (%)",
          fill = "Status"
        ) +
        theme_minimal(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))

      p_ngs_perf_n <- ggplot(ngs_perf, aes(x = run_setup, y = n, fill = qc_status)) +
        geom_col(position = "stack") +
        scale_fill_manual(values = fhi_discrete_palette(n_distinct(ngs_perf$qc_status), sc2_palette)) +
        labs(
          title = "NGS run setup: included vs failed counts",
          x = "NGS-runoppsett / run-id",
          y = "Antall (n)",
          fill = "Status"
        ) +
        theme_minimal(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
      p_ngs_perf_combined <- p_ngs_perf_pct / p_ngs_perf_n +
        patchwork::plot_layout(heights = c(1, 1), guides = "collect") &
        theme(legend.position = "right")
      export_graph <- export_to_ppt(export_graph, p_ngs_perf_combined, "NGS run setup: included vs failed (% + count)")
    }

    # Coverage by run setup: box-and-whisker per run with per-sample points colored by Tessy.
    ngs_cov_run_df <- ngs_qc_df %>%
      filter(!is.na(cov_norm), !is.na(run_setup), trimws(run_setup) != "", run_setup != "Ukjent")

    if (nrow(ngs_cov_run_df) > 0) {
      cov_run_summary <- ngs_cov_run_df %>%
        group_by(run_setup) %>%
        summarise(
          n_samples = n(),
          mean_cov = round(mean(cov_norm, na.rm = TRUE), 3),
          median_cov = round(median(cov_norm, na.rm = TRUE), 3),
          p10_cov = round(as.numeric(stats::quantile(cov_norm, probs = 0.10, na.rm = TRUE)), 3),
          p90_cov = round(as.numeric(stats::quantile(cov_norm, probs = 0.90, na.rm = TRUE)), 3),
          included_n = sum(qc_status == "Included_in_SC2db_v", na.rm = TRUE),
          failed_n = sum(qc_status == "Failed_threshold_or_missing", na.rm = TRUE),
          included_pct = round(100 * included_n / n_samples, 1),
          .groups = "drop"
        ) %>%
        arrange(desc(included_pct), desc(median_cov), desc(n_samples), run_setup)

      export_graph <- export_to_ppt(
        export_graph,
        cov_run_summary,
        "Deknings-QC per NGS-run (oppsummeringstabell)"
      )

      if ("Tessy_plot" %in% names(ngs_cov_run_df) && any(!is.na(ngs_cov_run_df$Tessy_plot) & trimws(ngs_cov_run_df$Tessy_plot) != "")) {
        top_tessy_run <- ngs_cov_run_df %>%
          filter(!is.na(Tessy_plot), trimws(Tessy_plot) != "") %>%
          count(Tessy_plot, sort = TRUE) %>%
          slice_head(n = 8) %>%
          pull(Tessy_plot)

        ngs_cov_run_df <- ngs_cov_run_df %>%
          mutate(
            Tessy_plot = ifelse(is.na(Tessy_plot) | trimws(Tessy_plot) == "", "Ukjent", Tessy_plot),
            Tessy_plot = ifelse(Tessy_plot %in% top_tessy_run, Tessy_plot, "Andre")
          )

        p_cov_run_box <- ggplot(ngs_cov_run_df, aes(x = run_setup, y = cov_norm)) +
          geom_boxplot(fill = "grey90", color = "grey30", outlier.shape = NA) +
          geom_jitter(aes(color = Tessy_plot), width = 0.2, height = 0, alpha = 0.7, size = 1.6) +
          scale_color_manual(values = fhi_discrete_palette(n_distinct(ngs_cov_run_df$Tessy_plot), sc2_palette)) +
          labs(
            title = "Dekning per NGS-runoppsett",
            subtitle = "Boksplott per run; hver pr\u00f8ve farget etter Tessy (topp 8 + Andre)",
            x = "NGS-runoppsett / run-id",
            y = "Normalisert dekningsgrad (0-1)",
            color = "Tessy"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      } else {
        p_cov_run_box <- ggplot(ngs_cov_run_df, aes(x = run_setup, y = cov_norm)) +
          geom_boxplot(fill = "grey90", color = "grey30", outlier.shape = NA) +
          geom_jitter(width = 0.2, height = 0, alpha = 0.6, size = 1.5, color = "#1f77b4") +
          labs(
            title = "Dekning per NGS-runoppsett",
            subtitle = "Boksplott per run; Tessy ikke tilgjengelig for punktfarging",
            x = "NGS-runoppsett / run-id",
            y = "Normalisert dekningsgrad (0-1)"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      }

      export_graph <- export_to_ppt(export_graph, p_cov_run_box, "Dekning per runoppsett (boksplott + pr\u00f8vepunkter)")
    }

    # Coverage by month colored by subclade/lineage.
    if (!is.na(ngs_subclade_col)) {
      ngs_cov_month_df <- ngs_qc_df %>%
        mutate(
          month_date = floor_date(plot_date, unit = "month"),
          subclade_plot = as.character(.data[[ngs_subclade_col]]),
          subclade_plot = ifelse(is.na(subclade_plot) | trimws(subclade_plot) == "", "Ukjent", subclade_plot)
        ) %>%
        filter(!is.na(cov_norm), !is.na(month_date))

      if (nrow(ngs_cov_month_df) > 0) {
        top_subclades <- ngs_cov_month_df %>%
          count(subclade_plot, sort = TRUE) %>%
          slice_head(n = 10) %>%
          pull(subclade_plot)

        ngs_cov_month_df <- ngs_cov_month_df %>%
          mutate(subclade_plot = ifelse(subclade_plot %in% top_subclades, subclade_plot, "Andre")) %>%
          group_by(month_date, subclade_plot) %>%
          summarise(
            mean_cov = mean(cov_norm, na.rm = TRUE),
            median_cov = median(cov_norm, na.rm = TRUE),
            n = n(),
            .groups = "drop"
          )

        p_cov_month_subclade <- ggplot(
          ngs_cov_month_df,
          aes(x = month_date, y = median_cov, color = subclade_plot, group = subclade_plot)
        ) +
          geom_line(linewidth = 1) +
          geom_point(aes(size = n), alpha = 0.85) +
          scale_color_manual(values = fhi_discrete_palette(n_distinct(ngs_cov_month_df$subclade_plot), sc2_palette)) +
          scale_size_continuous(range = c(1.5, 5)) +
          scale_x_date(date_breaks = "1 month", date_labels = "%b-%Y") +
          labs(
            title = "Dekning per m\u00e5ned farget etter subklade",
            subtitle = "Median dekningsgrad per m\u00e5ned; topp 10 subklader vist separat",
            x = "M\u00e5ned",
            y = "Normalisert dekningsgrad (0-1)",
            color = "Subklade",
            size = "n"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))

        export_graph <- export_to_ppt(export_graph, p_cov_month_subclade, "Dekning per m\u00e5ned og subklade")
      }
    }

  }
}


# ============================================================================
# SEQUENCE SUMMARY - WEEK/MONTH
# ============================================================================

export_graph <- add_section_slide(export_graph, "Dekning", "Dekningsbredde og sekvenseringsytelse")
# ---- BEGIN INLINED: SC2/SC2_Seqs_per_month.R ----
###### Sekvenser per uke for prosentberegning: ######

if (!exists("SC2db_v")) {
  stop("Object 'SC2db_v' is missing. Run the SQL/classification scripts before sourcing SC2_Seqs_per_month.R.")
}

###### Sekvenser per m\u00e5ned for prosentberegning: ######

# Calculate Sequences per month for Spike protein sequence results
spm_spike <- SC2db_v %>%
  filter(nc_pangolin_short != "") %>%
  filter(Spike_mut != "") %>%
  count(my, name = "TotalSeq") %>%
  ungroup() %>%
  mutate(
    Date = as.Date(my),
    YearMonth = format(Date, "%Y %b")
  ) %>%
  select(-Date)  # Drop the temporary Date column if not needed

# Calculate Total Valid Sequences per month
v_seqs_per_month <- SC2db_v %>%
  count(my, name = "TotalSeq")

###### Sekvenser per opprinnelseslaboratorium #######

v_seqs_per_month_origin <- SC2db_v %>%
  group_by(my, Origin) %>%
  count(name = "TotalSeq") %>%
  ungroup() %>%
  mutate(my  = as.Date(paste0(my, " 01"), format="%Y %b %d")) 


# Create a bar chart per month based on Origin
spmlabto <- ggplot(v_seqs_per_month_origin, aes(x = my, y = TotalSeq, fill = Origin)) +
  geom_bar(stat = "identity") +
  labs(title = "Sekvensering av SC2 i Norge",
       x = "M\u00e5ned",
       y = "Antall (n)") +
  scale_x_date(
    breaks = "1 month",  # Show breaks every month
    labels = scales::date_format("%b %Y")  # Format as month name and year
  ) +
  scale_fill_manual(values = kvalitativ_a) +  # Set custom colors
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  theme(plot.title = element_text(hjust = 0.5, size = 14)) +  # Center the title and increase its size
  theme(legend.position="right")  # Optional: Remove legend if not needed


# Add a slide to the presentation with Title and Content layout and Office Theme master
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")

# Insert the graph into the slide
export_graph <- ph_with(export_graph, value = spmlabto, location = ph_location_fullsize())


# Assuming 'my' is the column in the dataframe with date format "YYYY-MM-DD"
# Convert 'my' to Date type if not already
v_seqs_per_month_origin <- v_seqs_per_month_origin %>%
  mutate(my = as.Date(my))

# Get the system date
current_date <- Sys.Date()

# Calculate the date threshold for filtering (8 months prior to today)
threshold_date <- current_date %m-% months(8)

# Filter the dataframe for rows with 'my' from the last 8 months
v_seqs_per_month_origin8m <- v_seqs_per_month_origin %>%
  filter(my >= threshold_date)

# Create a bar chart per month based on Origin
spmlabto8m <- ggplot(v_seqs_per_month_origin8m, aes(x = my, y = TotalSeq, fill = Origin)) +
  geom_bar(stat = "identity") +
  labs(title = "Sekvensering av SC2 i Norge",
       x = "M\u00e5ned",
       y = "Antall (n)") +
  scale_x_date(
    breaks = "1 month",  # Show breaks every month
    labels = scales::date_format("%b %Y")  # Format as month name and year
  ) +
  scale_fill_manual(values = kvalitativ_a) +  # Set custom colors
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  theme(plot.title = element_text(hjust = 0.5, size = 14)) +  # Center the title and increase its size
  theme(legend.position="right")  # Optional: Remove legend if not needed


spmlabto8m

# Add a slide to the presentation with Title and Content layout and Office Theme master
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")

# Insert the graph into the slide
export_graph <- ph_with(export_graph, value = spmlabto8m, location = ph_location_fullsize())

# ---- END INLINED: SC2/SC2_Seqs_per_month.R ----


# ============================================================================
# PANGOLIN ANALYSIS - OVERVIEW
# ============================================================================

export_graph <- add_section_slide(export_graph, "Pangolin og Tessy per m\u00e5ned", "M\u00e5nedlig linje- og Tessy-sammensetning")
# ---- BEGIN INLINED: SC2/SC2_Pangolin_p_m.R ----
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Pangolin-klassifisering per m\u00e5ned", location = ph_location_type(type = "title"))

sequencing_window_start <- if (exists("data_window_start")) as.Date(data_window_start) else (Sys.Date() %m-% months(6))

# Prepare data for the weekly sequence count
monthcount <- SC2db_v %>%
  dplyr::count(my, name = "TotalSeq")

# Calculate weekly counts for each Pangolin lineage
pangomtcount <- SC2db_v %>%
  group_by(my) %>%
  dplyr::count(Collapsed_pango, my, name = "count") %>%
  ungroup() %>%
  mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d")) %>%
  left_join(monthcount, by = "my") %>%
  mutate(Percent = count / TotalSeq)

# Count sequences per Pangolin lineage and Collapsed_pango variant for each month
fpangomtcount <- SC2db_v %>%
  group_by(my) %>%
  dplyr::count(nc_pangolin_short, Collapsed_pango, my, name = "count") %>%
  ungroup() %>%
  mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d")) %>%
  left_join(monthcount, by = "my") %>%
  mutate(Percent = round((count / TotalSeq) * 100, 2))

# Set sample dates for 'monthcount' data
monthcounstat <- monthcount %>%
  mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d"))

# Filter data using SC2 shared window: current season, or include previous season to minimum 6 months
pangowk12mo <- subset(SC2db_v,
                      prove_tatt >= sequencing_window_start &
                        prove_tatt <= Sys.Date())
subset_data12mo <- subset(pangomtcount, Sampledate >= sequencing_window_start)
subset_data2mo <- subset(pangomtcount, Sampledate >= Sys.Date() %m-% months(2))
subset_data4mo <- subset(pangomtcount, Sampledate >= Sys.Date() %m-% months(4))
subset_data4mofpango <- subset(fpangomtcount, Sampledate >= Sys.Date() %m-% months(4))
subset_data6mofpango <- subset(fpangomtcount, Sampledate >= sequencing_window_start)
subset_data12mofpango <- subset(fpangomtcount, Sampledate >= sequencing_window_start)
monthcount12mo <- subset(monthcounstat, Sampledate >= sequencing_window_start)
monthcounstat12mo <- subset(monthcounstat, Sampledate >= sequencing_window_start)

# Generate and save stacked bar percentage chart for all data period
grpangomtp <- ggplot(pangomtcount,
                     aes(x = Sampledate, y = Percent, fill = Collapsed_pango)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = custom_colors) +
  labs(y = "Andel (%)", x = "", fill = "SARS-CoV-2-nomenklatur") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(
    axis.text.x = element_text(
      angle = 90,
      hjust = 1,
      vjust = 0.5,
      size = 12
    ),
    axis.text.y = element_text(size = 12)
  )

# Second plot for sequence counts over time
grpangomtp_numbers <- ggplot(monthcounstat, aes(x = Sampledate, y = TotalSeq)) +
  geom_bar(stat = "identity") +
  labs(y = "Antall (n)", x = "") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(
    axis.text.x = element_text(
      angle = 90,
      hjust = 1,
      vjust = 0.5,
      size = 12
    ),
    axis.text.y = element_text(size = 12)
  )

# Combine the two plots and save
combined_plotwp <- grpangomtp / grpangomtp_numbers + plot_layout(guides = "collect", heights = c(3, 1))

# Add plot to PowerPoint
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plotwp, location = ph_location_fullsize())



# Convert `my` to the desired format and correctly order the data
pangoxls <- pangomtcount %>%
  select(my, Collapsed_pango, count) %>%
  mutate(my = format(as.Date(my), "%Y %b") %>% tolower()) %>%
  pivot_wider(
    names_from = my,     # Column that defines the new columns
    values_from = count  # Values for the new columns
  ) %>%
  mutate(across(everything(), ~ replace_na(.x, 0)))

# Convert back to the long format with correct ordering
pangostatistikk <- pangoxls %>%
  pivot_longer(
    cols = -Collapsed_pango,  # Pivot all columns except 'Collapsed_pango'
    names_to = "my",          # Name for the new key column
    values_to = "count"       # Name for the new value column
  ) %>%
  mutate(flagg = 0) %>%
  mutate(my_ord = as.Date(paste0(my, " 01"), format = "%Y %b %d")) %>%
  arrange(my_ord) %>%
  select(-my_ord)  # Remove the ordering column

# Calculate total counts for each 'my'
total_counts <- pangostatistikk %>%
  group_by(my) %>%
  summarize(total_count = sum(count))

# Join total counts back to the data
pangostatistikk_with_totals <- pangostatistikk %>%
  left_join(total_counts, by = "my") %>%
  mutate(percent = round((count / total_count) * 100))  # Calculate and round percentage to whole number


# Select and arrange the final data
final_pangostatistikk <- pangostatistikk_with_totals %>%
  select(Collapsed_pango, my, count, percent, flagg)

# Ensure numeric values are formatted correctly for CSV export
final_pangostatistikk <- final_pangostatistikk %>%
  mutate(across(
    .cols = where(is.numeric),
    .fns = ~ format(., scientific = FALSE)  # Ensure numeric values are correctly formatted
  ))




# Prepare data for last 12 months stacked bar percentage chart
grpangomtp_12mo <- ggplot(subset_data12mo,
                          aes(x = Sampledate, y = Percent, fill = Collapsed_pango)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = variant_color) +
  labs(y = "Andel (%)", x = "", fill = "Pangolin") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_blank())

# Second plot for last 12 months sequence counts
grpangomtp_numbers_12mo <- ggplot(monthcounstat12mo, aes(x = Sampledate, y = TotalSeq)) +
  geom_bar(stat = "identity") +
  labs(y = "Antall (n)", x = "") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(
    angle = 90,
    hjust = 1,
    vjust = 0.5
  ))

# Combine last 12 months plots
combined_plot_12mo <- grpangomtp_12mo / grpangomtp_numbers_12mo +
  plot_layout(guides = "collect", heights = c(3, 1))

# Add last 12 months plot to PowerPoint
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot_12mo, location = ph_location_fullsize())

# Create and save individual Pangolin variant plots for the last 12 months
unique_collapsed_pangosrec <- subset_data4mofpango %>%
  pull(Collapsed_pango) %>%
  unique()


# Create a summary table of Pangolin variants for the shared sequencing window
subset_data6mopango <- subset(fpangomtcount, Sampledate >= sequencing_window_start)

# Loop through unique 'Collapsed_pango' values
for (collapsed_pango in unique_collapsed_pangosrec) {
  loop_started_at <- Sys.time()
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop Pangolin START: ", collapsed_pango)
  }
  subset_data <- subset_data6mopango %>%
    filter(Collapsed_pango == collapsed_pango) %>%
    mutate(Sampledate = as.Date(Sampledate))
  
  # Plot for sequence count
  collapsed_pangosrecgr <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
    geom_bar(aes(y = count), stat = "identity") +
    labs(
      title = paste(
        "Antall",
        collapsed_pango,
        "undervarianter de siste seks m\u00e5nedene"
      ),
      x = "",
      y = "Antall (n)",
      fill = "Pangolin-nomenklatur"
    ) +
    scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 90, size = 12),
          axis.text.y = element_text(size = 12)) +
    geom_text(
      aes(
        y = count,
        label = paste(nc_pangolin_short, "(", count, ")", sep = "")
      ),
      position = position_stack(vjust = 0.5),
      color = "black",
      size = 3.5
    )
  
  # Save plot to PowerPoint as vector graphic
  plot_rvg <- dml(ggobj = collapsed_pangosrecgr)
  export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
    ph_with(plot_rvg, location = ph_location_fullsize())
  
  # Plot for percentage of sequences
  collapsed_pangosrecgr_percent <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
    geom_col(aes(y = Percent)) +
    labs(
      title = paste(
        "Andel av",
        collapsed_pango,
        "undervarianter de siste seks m\u00e5nedene"
      ),
      x = "",
      y = "Andel (%)",
      fill = "Pangolin-nomenklatur"
    ) +
    scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 90, size = 12),
          axis.text.y = element_text(size = 12)) +
    geom_text(
      aes(
        y = Percent,
        label = paste(nc_pangolin_short, "(", count, ")", sep = "")
      ),
      position = position_stack(vjust = 0.5),
      color = "black",
      size = 3.5
    )
  
  # Save percentage plot to PowerPoint
  plot_rvg_percent <- dml(ggobj = collapsed_pangosrecgr_percent)
  export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
    ph_with(plot_rvg_percent, location = ph_location_fullsize())
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop Pangolin DONE: ", collapsed_pango, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}

###### 15 top variants last recorded month
p6modata  <- subset_data6mopango %>% mutate(n = paste0(count, " (", round(Percent, 2), "%", ")"))

SC2_6mopangopivot <- p6modata %>%
  pivot_wider(id_cols = nc_pangolin_short,
              names_from = my,
              values_from = n,) %>%
  rename("SARS-CoV2 Variants" = nc_pangolin_short)

SC2_6mopangopivot <- SC2_6mopangopivot %>%
  mutate(last_col_numeric = as.numeric(str_extract(.[[ncol(.)]], "^[0-9]+"))) %>%  
  # Extract only the numeric part before ' b (...)'
  arrange(desc(last_col_numeric)) %>%  
  select(-last_col_numeric)  # Remove the temporary numeric column


# Display the result

ft <- flextable(SC2_6mopangopivot)
ft <- autofit(ft)

# Save summary table to PowerPoint
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph,
                        value = ft,
                        location = ph_location_type(type = "body"))
#####

subset_data6mopango$count <- as.numeric(subset_data6mopango$count)

SC2_6mopangopivot <- subset_data6mopango %>%
  pivot_wider(
    id_cols = nc_pangolin_short,
    names_from = my,
    values_from = count,
    values_fill = 0  # Fill missing values with 0
  ) %>%
  rename("SARS-CoV2 Variants" = nc_pangolin_short) %>%
  arrange(desc(.[[ncol(.)]])) %>%  # Order by the last column in descending order
  slice_head(n = 15)  # Display the top 15 rows


# Assuming the first column is an identifier and the rest are used for calculations
SC2_6mopangopivoperc <- subset_data6mopango %>%
  pivot_wider(
    id_cols = nc_pangolin_short,
    names_from = my,
    values_from = count,
    values_fill = 0  # Fill missing values with 0
  ) %>%
  rename("SARS-CoV2 Variants" = nc_pangolin_short) %>%
  arrange(desc(.[[ncol(.)]])) %>%  # Order by the last column in descending order
  slice_head(n = 15)  # Display the top 15 rows


# Display the result with flextable
ft <- flextable(SC2_6mopangopivot) %>%
  autofit() %>%
  set_header_labels(Arrow = "Trend")   # Rename the Arrow column to "Trend"


# Save summary table to PowerPoint
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph,
                        value = ft,
                        location = ph_location_type(type = "body"))

# ---- END INLINED: SC2/SC2_Pangolin_p_m.R ----

# ---- BEGIN INLINED: SC2/SC2_Tessy_p_m.R ----
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Tessy-klassifisering per m\u00e5ned", location = ph_location_type(type = "title"))

sequencing_window_start <- if (exists("data_window_start")) as.Date(data_window_start) else (Sys.Date() %m-% months(6))

# Count the number of sequences per month
monthcount <- SC2db_v %>%
  dplyr::count(my, name = "TotalSeq")

# Count the number of sequences for each tessy lineage per month
tessymtcount <- SC2db_v %>%
  group_by(my) %>%
  dplyr::count(Tessy, my, name = "count") %>%
  ungroup() %>%
  mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d"))

# Merge the lineage counts with the total sequence counts 
tessymtcount <- tessymtcount %>%
  left_join(monthcount, by = "my") %>%
  mutate(Percent = (count / TotalSeq)*100)

# Add Sampledate to monthcount
monthcount <- monthcount %>%
  mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d"))

# Subset data for shared sequencing window + short recency views
tessy12mo <- subset(SC2db_v, prove_tatt >= sequencing_window_start & prove_tatt <= Sys.Date())
tessy6mo <- subset(SC2db_v, prove_tatt >= sequencing_window_start & prove_tatt <= Sys.Date())
subset_data12mo <- subset(tessymtcount, Sampledate >= sequencing_window_start)
subset_data2mo <- subset(tessymtcount, Sampledate >= Sys.Date() %m-% months(2))
subset_data4mo <- subset(tessymtcount, Sampledate >= Sys.Date() %m-% months(4))
subset_data6mo <- subset(tessymtcount, Sampledate >= sequencing_window_start)
monthcount12mo <- subset(monthcount, Sampledate >= sequencing_window_start)

subset_data_season <- subset(tessymtcount, Sampledate >= sequencing_window_start)
subset_data_year <- subset(tessymtcount, Sampledate >= sequencing_window_start)
subset_data_season_p <- subset_data_season %>%
  mutate(Percent = (count / TotalSeq) * 100)
subset_data_year_p <- subset_data_year %>%
  mutate(Percent = (count / TotalSeq) * 100)

# Create the first stacked bar percentage chart for tessys
grtessymtp <- ggplot(tessymtcount, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
    labs(y = "Andel (%)", x = "", fill = "Tessy-kategori") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

# Create the second bar plot with numbers from the "TotalSeq" column
grtessyp_numbers <- ggplot(monthcount, aes(x = Sampledate, y = TotalSeq)) +
  geom_bar(stat = "identity") +
  labs(y = "Antall (n)", x = "") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

# Combine the two plots using patchwork
combined_plot <- grtessymtp / grtessyp_numbers + plot_layout(guides = "collect", heights = c(3, 1))

# Print the combined plot

# Save the combined plot to PowerPoint without title
export_graph <- save_plot(combined_plot, "Tessy Reporting Overview", export_graph)

############################################### Tessy-kategori single plots

# Define unique tessy categories for the last 2 months
unique_tessyrec <- subset_data4mo %>%
  pull(Tessy) %>%
  unique()

# Function to filter data for each collapsed tessy
get_data_for_tessy <- function(dataset, tessy_name) {
  dataset %>%
    filter(Tessy == tessy_name) %>%
    group_by(my) %>%
    dplyr::count(nc_pangolin_short, my, name = "Count") %>%
    ungroup() %>%
    left_join(SC2db_v %>% dplyr::count(my, name = "TotalSeq"), by = "my") %>%
    mutate(Percentage = (Count / TotalSeq) * 100) %>%
    arrange(my) %>%
    mutate(Sampledate = as.Date(paste(my, "01"), format = "%Y %b %d"))
}

# Create a list of dataframes for each collapsed tessy
tessy_data_list <- lapply(unique_tessyrec, function(tessy) {
  tessy_data <- get_data_for_tessy(tessy6mo, tessy)
  if (sum(tessy_data$Count) > 0) {
    return(tessy_data)
  } else {
    return(NULL)
  }
})

# Loop through the list of unique tessy categories and create charts
for (i in seq_along(unique_tessyrec)) {
  loop_started_at <- Sys.time()
  tessy <- unique_tessyrec[i]
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop Tessy ", i, "/", length(unique_tessyrec), " START: ", tessy)
  }
  subset_data <- get_data_for_tessy(tessy6mo, tessy)  # Retrieve the data for the specific tessy
  
  # Check if the subset is not empty
  if (nrow(subset_data) > 0) {
    
    # Create the chart for sequence count
    collapsed_pangosrecgr <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
      geom_bar(aes(y = Count), stat = "identity") +
      labs(
        title = paste("Pangolin-nomenklatur per Tessy-kategori", tessy),
        x = "", 
        y = "Antall (n)", 
        fill = "Pangolin-nomenklatur"
      ) +
      scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 90, size = 12),
        axis.text.y = element_text(size = 12)
      ) +
      geom_text(aes(y = Count, label = paste(nc_pangolin_short, "(", Count, ")", sep = "")), 
                position = position_stack(vjust = 0.5), 
                color = "black", 
                size = 3.5)
    
    # Save the individual chart to PowerPoint without title
    plot_rvg <- dml(ggobj = collapsed_pangosrecgr)
    export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
      ph_with(plot_rvg, location = ph_location_fullsize())
    
    # Calculate percentages for the subset data
    subset_data <- subset_data %>%
      mutate(Percent = Count / sum(Count) * 100) # Calculate the percentage
    
    # Create the chart for percentage of sequences
    collapsed_pangosrecgr_percent <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
      geom_col(aes(y = Percent)) +
      labs(
        title = paste("Pangolin-nomenklatur per Tessy-kategori", tessy),
        x = "", 
        y = "Andel (%)", 
        fill = "Pangolin-nomenklatur"
      ) +
      scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 90, size = 12),
        axis.text.y = element_text(size = 12)
      ) +
      geom_text(aes(y = Percent, label = paste(nc_pangolin_short, "(", Count, ")", sep = "")), 
                position = position_stack(vjust = 0.5), 
                color = "black", 
                size = 3.5)
    
    # Save percentage plot to PowerPoint
    plot_rvg_percent <- dml(ggobj = collapsed_pangosrecgr_percent)
    export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
      ph_with(plot_rvg_percent, location = ph_location_fullsize())
  }
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop Tessy ", i, "/", length(unique_tessyrec), " DONE: ", tessy, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}


# ################Table last 4 months Tessy frequency ############################

# Round the Percent column to 2 decimal points
p4modata  <- subset_data4mo %>% mutate(n = paste0(count, " (", round(Percent, 2), "%", ")"))

# Pivot wider on the "my" column, keeping count as a separate value
pv4modata <- p4modata %>% pivot_wider(names_from = my,id_cols = Tessy, values_from = n, 
                                      values_fill = list(count = 0, Percent = 0) ) 

# Display the updated dataframe
pv4modata

# Create flextable from the pivot table and add to PowerPoint
ft <- flextable(pv4modata)
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, ft, location = ph_location_type(type = "body"))


##########################Combined bar and line plot with tessy variables################

# ------------- STEP 1: Process Data -------------
# Step 1: Rename 'Tessy' values based on the condition
subset_data12mo_mod <- subset_data12mo %>%
  group_by(Tessy) %>%
  mutate(Tessy = ifelse(max(Percent) <= 5, "Andre SARS CoV 2", Tessy)) %>%
  ungroup()

# Step 2: Recalculate the counts for 'Andre Sars-CoV2' and all other categories
subset_data12mo_mod <- subset_data12mo_mod %>%
  group_by(Sampledate, Tessy) %>% # Group by month (Sampledate) and variant (Tessy)
  summarise(
    count = sum(count),           # Recalculate counts for each category
    TotalSeq = first(TotalSeq),   # Keep the total sequences for the month
    .groups = "drop_last"
  )

# Step 3: Recalculate percentages
subset_data12mo_modp <- subset_data12mo_mod %>%
  mutate(Percent = (count / TotalSeq) * 100)

# Check the results

# ------------- PLOT 1: Percentage Stacked Bar Plot -------------
grtessymtp_12mo <- ggplot(subset_data12mo, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_comb) +
  labs(y = "Andel (%)", x = "", fill = "Pangolin-nomenklatur") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") + # Do not set limits here to avoid conflict
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, size = 10))

# ------------- PLOT 2: Grey Bars for TotalSeq with Line Plot for Percentages -------------
combined_plot_12mo_mod <- ggplot(subset_data12mo_modp, aes(x = Sampledate)) +
  geom_bar(aes(y = TotalSeq / max(TotalSeq) * 100, fill = "TotalSeq"), 
           stat = "identity", alpha = 0.5, color = "black", position = "identity") +
  geom_line(aes(y = Percent, color = Tessy, group = Tessy), linewidth = 2) +
  scale_y_continuous(
    name = "Andel (%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data12mo$TotalSeq) / 100,
      name = "Antall (n)"
    )
  ) +
  scale_color_manual(values = variant_color, name = "Pangolin-nomenklatur") +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall (n)") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") + # Same scale on x-axis but no limits 
  labs(x = "") +
  theme_classic() +
  theme(axis.text.x = element_text(angle = 90, size = 10))

# ------------- COMBINE PLOTS USING PATCHWORK -------------
# Adjusting the height of the lower graph to be bigger (increasing lower plot's relative height in the layout)
combined_plot <- grtessymtp_12mo / combined_plot_12mo_mod + 
  plot_layout(guides = "collect", heights = c(3, 2))  # Adjusting height proportions (3 for lower plot)

# Print the combined plot

export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())


 ### Season only Tessy with trends 



# Assuming subset_data_season is correctly defined and has the necessary columns
subset_data_season_gr <- ggplot(subset_data_season, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_a) +
  labs(y = "Andel (%)", x = "", fill = "Pangolin-nomenklatur") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme_minimal() +
  theme(
    axis.text.x = element_blank(), # Remove x-axis labels
    axis.title.x = element_blank()  # Optionally, remove x-axis title
  )

# Assuming subset_data_season_p is defined and has necessary columns
subset_data_season_pgr <- ggplot(subset_data_season_p, aes(x = Sampledate)) +
  geom_bar(aes(y = TotalSeq / max(TotalSeq) * 100, fill = "TotalSeq"), 
           stat = "identity", alpha = 0.5, color = "black", position = "identity") +
  geom_line(aes(y = Percent, color = Tessy, group = Tessy), linewidth = 1.5) +
  scale_y_continuous(
    name = "Andel (%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data_season_p$TotalSeq) / 100,
      name = "Antall (n)"
    )
  ) +
  scale_color_manual(values = kvalitativ_a) +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall (n)") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  labs(x = "") +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1),
    legend.position = "bottom"
  )

# Combine the plots using Patchwork, adjusting the heights appropriately
combined_plot <- subset_data_season_gr / subset_data_season_pgr + 
  plot_layout(guides = "collect", heights = c(3, 2))

# Display the combined plot

# Export the plot to a PowerPoint slide
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())

# Assuming subset_data_season is correctly defined and has the necessary columns
subset_data_year_gr <- ggplot(subset_data_year, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_a) +
  labs(y = "Andel (%)", x = "", fill = "Pangolin-nomenklatur") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme_minimal() +
  theme(
    axis.text.x = element_blank(), # Remove x-axis labels
    axis.title.x = element_blank()  # Optionally, remove x-axis title
  )

# Assuming subset_data_season_p is defined and has necessary columns
subset_data_year_pgr <- ggplot(subset_data_year_p, aes(x = Sampledate)) +
  geom_bar(aes(y = TotalSeq / max(TotalSeq) * 100, fill = "TotalSeq"), 
           stat = "identity", alpha = 0.5, color = "black", position = "identity") +
  geom_line(aes(y = Percent, color = Tessy, group = Tessy), linewidth = 1.5) +
  scale_y_continuous(
    name = "Andel (%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data_season_p$TotalSeq) / 100,
      name = "Antall (n)"
    )
  ) +
  scale_color_manual(values = kvalitativ_a) +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall (n)") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  labs(x = "") +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1),
    legend.position = "bottom"
  )

# Combine the plots using Patchwork, adjusting the heights appropriately
combined_plot <- subset_data_year_gr / subset_data_year_pgr + 
  plot_layout(guides = "collect", heights = c(3, 2))

# Display the combined plot

# Export the plot to a PowerPoint slide
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())

# ---- END INLINED: SC2/SC2_Tessy_p_m.R ----


# ============================================================================
# MUTATION ANALYSIS - COMBINATIONS
# ============================================================================

export_graph <- add_section_slide(export_graph, "Mutation Analysis", "Mutation combinations, frequencies and domains")
# ---- BEGIN INLINED: SC2/SC2_Spike_mut_of_interest.R ----
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Spike-mutasjoner av interesse", location = ph_location_type(type = "title"))

# Extract relevant mutation data and perform initial filtering and transformations
mutfr <- SC2db_v %>%
  select(prove_tatt, Spike_mut, nc_pangolin_short, Collapsed_pango, Tessy) %>%
  filter(prove_tatt >= Sys.Date() - 365) %>%
  mutate(
    Sampledate = as.Date(prove_tatt),         # Convert prove_tatt to Date format
    Substitution = gsub(";", ",", Spike_mut),  # Replace semicolons with commas
    month = format(Sampledate, "%Y-%m"),      # Extract Year-Month
    Tessy_group = as.character(Tessy),
    Tessy_group = ifelse(is.na(Tessy_group) | trimws(Tessy_group) == "", "Ukjent", Tessy_group)
  ) %>%
  filter(Substitution != "") %>%
  group_by(month, Tessy_group, Substitution) %>%
  summarize(n = n(), .groups = "drop") %>%
  ungroup() %>%
  mutate(
    n = ifelse(is.na(n), 0, n),
    n_mut = str_count(Substitution, ","),
    date = as.Date(paste0(month, "-01"))     # Set to first day of the month
  ) %>%
  arrange(date)                               # Sort by date

mutfr_monthly <- mutfr %>%
  group_by(date, Tessy_group, n_mut) %>%
  summarise(n = sum(n), .groups = "drop")

grnmutfr <- ggplot(mutfr_monthly, aes(x = date, y = n_mut, color = Tessy_group, size = n)) +
  geom_point(alpha = 0.85, position = position_jitter(width = 2, height = 0.08, seed = 2526)) +
  labs(
    title = "Punktplott av mutasjoner per type og m\u00e5ned",
    x = "M\u00e5ned",
    y = "Antall mutasjoner",
    color = "Tessy",
    size = "Antall (n)"
  ) +
  scale_x_date(
    date_labels = "%b-%Y",
    date_breaks = "1 month",
    limits = c(floor_date(min(mutfr_monthly$date), unit = "month"), ceiling_date(max(mutfr_monthly$date), unit = "month"))
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 90, hjust = 1),
    plot.title = element_text(hjust = 0.5)
  ) +
  scale_color_manual(values = fhi_discrete_palette(n_distinct(mutfr_monthly$Tessy_group), sc2_palette))


# Add slide to presentation and insert the chart
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = grnmutfr, location = ph_location_fullsize())

# Create a heatmap for mutation combinations over the last 12 months
S_mut_data <- SC2db_v %>%
  filter(grepl(paste(mutations, collapse = "|"), Spike_mut)) %>%
  mutate(
    Sampledate = as.Date(prove_tatt),
    Substitution = gsub(";", ",", Spike_mut),
    YearMonth = format(Sampledate, "%Y %b")
  ) %>%
  select(Sampledate, Spike_mut, nc_pangolin_short, Collapsed_pango, YearMonth) %>%
  filter(Sampledate >= Sys.Date() - months(12))

# Create binary columns indicating the presence of each mutation
for (mutation in mutations) {
  loop_started_at <- Sys.time()
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop Mutation column START: ", mutation)
  }
  S_mut_data[[mutation]] <- as.integer(str_detect(S_mut_data$Spike_mut, mutation))
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop Mutation column DONE: ", mutation, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}

# Combine mutations into a single column
S_mut_data <- S_mut_data %>%
  mutate(Combination = apply(S_mut_data[, mutations], 1, function(x) paste(names(x)[x == 1], collapse = ",")))

# Summarize occurrences of each mutation combination by month
counts <- S_mut_data %>%
  group_by(YearMonth, Combination) %>%
  summarise(Count = n(), .groups = 'drop')

countspango <- S_mut_data %>%
  group_by(YearMonth, nc_pangolin_short, Combination) %>%
  summarise(Count = n(), .groups = 'drop')

# Join with total sequences per month
counts <- counts %>%
  left_join(spm_spike, by = "YearMonth") %>%
  mutate(Percentage = (Count / TotalSeq) * 100) %>%
  select(YearMonth, Combination, Percentage)

# Convert YearMonth to Date format and fill heatmap data
countm <- counts %>%
  mutate(YearMonth = as.Date(paste0(YearMonth, " 01"), format = "%Y %b %d"))

countm <- data.table::as.data.table(countm)
heatmap_data <- data.table::dcast(countm, YearMonth ~ Combination, value.var = "Percentage", fill = 0)

# Plot the heatmap
hmapmut <- ggplot(melt(heatmap_data, id.vars = "YearMonth"), aes(x = YearMonth, y = variable, fill = value)) +
  geom_tile() +
  scale_fill_gradientn(colours = kvantitativ_r1) +
  scale_x_date(date_labels = "%b %Y", date_breaks = "1 month") +
  labs(
    title = "Varmekart av mutasjonskombinasjoner per m\u00e5neder)",
    x = "M\u00e5ned",
    y = "Mutasjoner eller kombinasjoner",
    fill = "Andel (%)"
  ) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1))


export_graph <- save_plot(hmapmut, "Varmekart av mutasjonskombinasjoner per m\u00e5neder)", export_graph)

# Pangolin-nomenklatur per mutasjonskombinasjon
countspango <- countspango %>%
  mutate(Sampledate = as.Date(paste(YearMonth, "01"), format = "%Y %b %d"))

unique_combinations <- unique(countspango$Combination)

for (combination in unique_combinations) {
  loop_started_at <- Sys.time()
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop Combination START: ", combination)
  }
  # Subset data for the current combination
  subset_data <- countspango %>%
    filter(Combination == combination)
  
  # Plot for sequence count
  collapsed_pangosrecgr <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
    geom_bar(aes(y = Count), stat = "identity") +
    labs(
      title = paste("Pangolin-nomenklatur per kombinasjon av spike-mutasjoner for", combination),
    x = "M\u00e5ned",
      y = "Antall (n)", 
      fill = "Pangolin-nomenklatur"
    ) +
    scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 90, size = 12),
      axis.text.y = element_text(size = 12)
    ) +
    geom_text(aes(y = Count, label = paste(nc_pangolin_short, "(", Count, ")", sep = "")), 
              position = position_stack(vjust = 0.5), 
              color = "black", 
              size = 3.5)
  
  # Save the count plot to PowerPoint as a vector graphic
  plot_rvg <- dml(ggobj = collapsed_pangosrecgr)
  export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
    ph_with(plot_rvg, location = ph_location_fullsize())
  
  # Calculate percentages for the subset data
  subset_data <- subset_data %>%
    mutate(Percent = Count / sum(Count) * 100) # Calculate the percentage
  
  # Plot for percentage of sequences
  collapsed_pangosrecgr_percent <- ggplot(subset_data, aes(x = Sampledate, fill = nc_pangolin_short)) +
    geom_col(aes(y = Percent)) +
    labs(
      title = paste("Andel av Pangolin-nomenklatur per kombinasjon av spike-mutasjoner for", combination),
    x = "M\u00e5ned",
      y = "Andel (%)", 
      fill = "Pangolin-nomenklatur"
    ) +
    scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 90, size = 12),
      axis.text.y = element_text(size = 12)
    ) +
    geom_text(aes(y = Percent, label = paste(nc_pangolin_short, "(", Count, ")", sep = "")), 
              position = position_stack(vjust = 0.5), 
              color = "black", 
              size = 3.5)
  
  # Save percentage plot to PowerPoint
  plot_rvg_percent <- dml(ggobj = collapsed_pangosrecgr_percent)
  export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
    ph_with(plot_rvg_percent, location = ph_location_fullsize())
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop Combination DONE: ", combination, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}

# ---- END INLINED: SC2/SC2_Spike_mut_of_interest.R ----


# ============================================================================
# MUTATION ANALYSIS - PANGOLIN FOCUS
# ============================================================================

# ---- BEGIN INLINED: SC2/SC2_Spike_mut_freq.R ----
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Spike-mutasjonsfrekvens", location = ph_location_type(type = "title"))

# --- Filter and Prepare Linmut Data for Mutation Analysis ---

Linmut <- SC2db_v %>%
  # Select relevant columns for mutation analysis
  select(Spike_mut, my, year, week, nc_pangolin_short, nc_pangolin_long, Collapsed_pango, Tessy, key, prove_tatt) %>%
  # Filter to include data within the last year
  filter(prove_tatt >= Sys.Date() - 365) %>%
  # Split mutation data into separate entries per substitution
  mutate(Substitution = str_split(Spike_mut, ";|,", simplify = FALSE)) %>%
  unnest(Substitution) %>%
  # Remove redundant columns and empty substitutions
  select(-Spike_mut) %>%
  mutate(Substitution = stringr::str_trim(as.character(Substitution))) %>%
  filter(Substitution != "")

# --- Count Weekly Mutations and Calculate Percentages ---

spikecount <- Linmut %>%
  count(Substitution, my, name = "count") %>%
  ungroup() %>%
  # Join to include total sequences per month
  left_join(v_seqs_per_month, by = "my") %>%
  # Calculate mutation percentage and create sample date for plotting
  mutate(
    Percent = count / TotalSeq,
    Sampledate = as.Date(paste0(my, " 01"), format = "%Y %b %d")
  ) %>%
  filter(Sampledate >= Sys.Date() - 365) 

# --- Count Mutations per Uke by Pangolin Variant ---

spikecountcpango <- Linmut %>%
  count(Substitution, my, Collapsed_pango, name = "count") %>%
  ungroup() %>%
  # Join to get total sequence counts by variant and time period
  left_join(
    SC2db_v %>%
      count(my, Collapsed_pango, name = "Total") %>%
      ungroup(),
    by = c("my", "Collapsed_pango")
  ) %>%
  # Calculate percentage and format date
  mutate(
    Percent = count / Total,
    Sampledate = as.Date(paste0(my, " 01"), format = "%Y %b %d")
  ) %>%
  filter(Sampledate >= Sys.Date() - 180) 

# --- Identify Unique Pangolin Variants of Interest ---

unique_collapsed_pangos <- spikecountcpango %>%
  # Filter variants with mutation percentages within specified range in the last 3 months
  filter(Percent > 0.10, Percent < 0.95, Sampledate >= Sys.Date() - 90) %>%
  distinct(Collapsed_pango)

# --- Generate and Save Mutation Line Plots by Pangolin Variant ---

for (collapsed_pango in unique_collapsed_pangos$Collapsed_pango) {
  loop_started_at <- Sys.time()
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop SpikeFreq START: ", collapsed_pango)
  }
  # Filter data for the current variant
  plot_data <- spikecountcpango %>%
    filter(Collapsed_pango == collapsed_pango)
  
  # Generate line plot of mutation percentage over time
  plot <- ggplot(plot_data, aes(x = Sampledate, y = Percent, group = Substitution, colour = Substitution)) +
    geom_line(linewidth = 1) +
    scale_x_date(date_breaks = "1 month", date_labels = "%b-%Y", expand = c(0, 0)) +
    ylab("Andel (%)") +
    xlab("M\u00e5ned") +
    ggtitle(paste("Spike mutasjoner -", collapsed_pango)) +
    theme_classic() +
    theme(
      plot.title = element_text(color = "grey20", size = 20, hjust = 0.5, face = "bold"),
      axis.text.x = element_text(color = "grey20", size = 10, angle = 90, hjust = .5, vjust = .5, face = "plain"),
      axis.text.y = element_text(color = "grey20", size = 10, angle = 0, hjust = 1, vjust = 0.5, face = "plain"),
      axis.title.x = element_text(color = "grey20", size = 15, angle = 0, hjust = .5, vjust = 0.5, face = "bold"),
      axis.title.y = element_text(color = "grey20", size = 15, angle = 90, hjust = .5, vjust = .5, face = "bold")
    ) +
    scale_colour_discrete(guide = 'none') +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1), expand = c(0, 0)) +
    # Add labels for recent mutations of interest
    geom_text_repel(
      data = subset(plot_data, Sampledate == max(Sampledate) & Percent > 0.1 & Percent < 0.95),
      aes(label = sprintf("%s %s", scales::percent(Percent), toTitleCase(Substitution)), color = Substitution),
      direction = "y",
      force = 3,
      nudge_x = 70,
      na.rm = TRUE,
      segment.size = 0.2,
      segment.linetype = 2,
      segment.angle = 0,
      min.segment.length = 0,
      box.padding = 2,
      max.overlaps = Inf,
      show.legend = FALSE
    ) 
  
  # Use save_plot function to save the plot and insert into PowerPoint
  export_graph <- save_plot(plot, paste("Spike Mutations -", collapsed_pango), export_graph)
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop SpikeFreq DONE: ", collapsed_pango, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}

# --- Data Preparation for Latest Mutation Composition Analysis ---

# Convert 'my' column to date format
Linmut <- Linmut %>%
  mutate(my = as.Date(paste(my, "01"), format = "%Y %b %d"))

# Filter mutations with significant percentages in the latest time point
mut_int <- spikecount %>%
  filter(my == max(my), Percent > 0.05, Percent < 0.98) %>%
  select(Substitution)

# --- Create and Tree chart  for Each Significant Mutation ---


plots <- lapply(mut_int$Substitution, function(mut) {
  # Filter data for each mutation and count occurrences by Pangolin lineage
  x_i <- Linmut %>%
    filter(str_detect(Substitution, mut), my >= Sys.Date() - months(3)) %>%
    count(my, nc_pangolin_short, Substitution)
  
  # Create a tree map for the mutation composition
  tm <- ggplot(x_i, aes(area = n, fill = nc_pangolin_short, label = nc_pangolin_short)) +
    geom_treemap() +
    geom_treemap_text(color = "white", place = "centre", grow = TRUE) +
    ggtitle(mut) +
    theme(legend.position = "none")  # Suppress the legend display
  
  tm
})

# Define the layout of the plots on each slide
num_plots <- length(plots)
plots_per_slide <- 2 * 2  # Number of plots per slide
num_slides <- ceiling(num_plots / plots_per_slide)

# Loop to Save Tree Map Grids Across Multiple Slides
for (slide_index in 1:num_slides) {
  loop_started_at <- Sys.time()
  if (exists("log_timed_message", mode = "function")) {
    log_timed_message("Loop Treemap slide START: ", slide_index, "/", num_slides)
  }
  # Identify the range of plots for this slide
  start_plot <- (slide_index - 1) * plots_per_slide + 1
  end_plot <- min(start_plot + plots_per_slide - 1, num_plots)
  
  # Subset the list of plots for the current slide
  plot_subset <- plots[start_plot:end_plot]
  
  # Arrange selected plots into a grid
  combined_plot <- plot_grid(plotlist = plot_subset, ncol = 2)
  
  # Use save_plot function to save combined plot and insert into PowerPoint
  export_graph <- save_plot(combined_plot, paste("Mutation Composition - Slide", slide_index), export_graph)
  if (exists("log_timed_message", mode = "function")) {
    loop_elapsed <- as.numeric(difftime(Sys.time(), loop_started_at, units = "secs"))
    log_timed_message("Loop Treemap slide DONE: ", slide_index, "/", num_slides, " (", sprintf("%.2f", loop_elapsed), "s)")
  }
}

  
  # --- Spike lollipop map: mutation position + domain + Collapsed_pango ---

  Linmut <- Linmut %>%
    mutate(Number = as.integer(gsub("\\D", "", Substitution))) %>%
    mutate(Sampledate = as.Date(paste0(my, " 01"), format = "%Y %b %d")) %>%
    filter(!is.na(Number), Number >= 1, Number <= 1273) %>%
    mutate(Domain = case_when(
      Number < 13                      ~ "SP",
      Number >= 13 & Number <= 205     ~ "NTD",
      Number >= 319 & Number <= 541    ~ "RBD",
      Number >= 788 & Number <= 806    ~ "FP",
      Number >= 912 & Number <= 984    ~ "HR1",
      Number >= 1163 & Number <= 1213  ~ "HR2",
      Number >= 1214 & Number <= 1237  ~ "TM",
      Number >= 1238 & Number <= 1273  ~ "CT",
      TRUE                             ~ "Andre"
    ))

  domainmutcp <- Linmut %>%
    mutate(
      Tessy_group = as.character(Tessy),
      Tessy_group = ifelse(is.na(Tessy_group) | trimws(Tessy_group) == "", "Ukjent", Tessy_group)
    ) %>%
    group_by(Tessy_group, Substitution, Number, Domain) %>%
    summarise(n = n(), .groups = "drop")

  # Keep only Tessy groups with observed mutations for this view.
  domainmutcp <- domainmutcp %>%
    filter(!is.na(Tessy_group), trimws(as.character(Tessy_group)) != "")

  if (nrow(domainmutcp) == 0) {
    message("No valid Spike mutation positions found for domain lollipop map.")
  } else {

  domain_df <- tibble::tribble(
    ~Domain, ~xmin, ~xmax,
    "SP", 1, 12,
    "NTD", 13, 205,
    "RBD", 319, 541,
    "FP", 788, 806,
    "HR1", 912, 984,
    "HR2", 1163, 1213,
    "TM", 1214, 1237,
    "CT", 1238, 1273
  )

  domain_fill <- c(
    SP = "#86BC86", NTD = "#AFC8F7", RBD = "#FBC98D", FP = "#8ED3C7",
    HR1 = "#80B1D3", HR2 = "#FDE0A1", TM = "#D9A6A6", CT = "#B3E2CD"
  )

  tessy_levels <- domainmutcp %>%
    group_by(Tessy_group) %>%
    summarise(total_n = sum(n), .groups = "drop") %>%
    arrange(desc(total_n), Tessy_group) %>%
    pull(Tessy_group)
  domainmutcp$Tessy_group <- factor(domainmutcp$Tessy_group, levels = tessy_levels)

  for (tessy_name in tessy_levels) {
    tessy_df <- domainmutcp %>%
      filter(Tessy_group == tessy_name) %>%
      arrange(Number, Substitution)

    if (nrow(tessy_df) == 0) {
      next
    }

    # Plot in smaller AA windows to keep all labels readable and avoid crowding.
    label_df <- tessy_df %>%
      mutate(label_rank = row_number()) %>%
      mutate(
        label_band = ifelse(label_rank %% 2 == 0, "top", "bottom"),
        nudge_y = ifelse(
          label_band == "top",
          0.16 + (label_rank %% 20) * 0.014,
          -0.16 - (label_rank %% 20) * 0.014
        )
      )

    spike_lollipop_tessy <- ggplot(tessy_df, aes(x = Number, y = 1)) +
      geom_rect(
        data = domain_df,
        aes(xmin = xmin, xmax = xmax, ymin = 0.86, ymax = 1.14, fill = Domain),
        inherit.aes = FALSE,
        alpha = 0.25,
        color = NA
      ) +
      geom_segment(aes(xend = Number, yend = 0.86), linewidth = 0.3, alpha = 0.45, color = "grey35") +
      geom_point(aes(size = n, color = Domain), alpha = 0.9) +
      ggrepel::geom_text_repel(
        data = label_df,
        aes(x = Number, y = 1, label = Substitution),
        color = "black",
        size = 2.7,
        direction = "both",
        nudge_y = label_df$nudge_y,
        min.segment.length = 0,
        seed = 2526,
        max.overlaps = Inf,
        force = 28,
        force_pull = 1.2,
        box.padding = 0.3,
        point.padding = 0.2
      ) +
      scale_x_continuous(
        limits = c(1, 1273),
        breaks = c(1, 13, 205, 319, 541, 788, 806, 912, 984, 1163, 1213, 1237, 1273)
      ) +
      scale_y_continuous(limits = c(0.5, 1.5), breaks = NULL) +
      scale_fill_manual(values = domain_fill) +
      scale_color_manual(values = domain_fill) +
      scale_size_continuous(range = c(1.6, 6.5)) +
      guides(fill = "none") +
      labs(
        title = paste0("Spike mutation positions - Tessy: ", as.character(tessy_name)),
        subtitle = "Full Spike protein | all labels shown",
        x = "Spike amino-acid position",
        y = NULL,
        color = "Spike domain",
        fill = "Spike domain",
        size = "Antall (n)"
      ) +
      theme_minimal(base_size = 11) +
      theme(
        axis.text.x = element_text(angle = 90, vjust = 0.5),
        panel.grid.minor = element_blank(),
        legend.position = "bottom"
      )

    export_graph <- save_plot(
      spike_lollipop_tessy,
      paste0("Spike Mutation Domain Lollipop - Tessy ", as.character(tessy_name)),
      export_graph
    )
  }
  }
  


# ---- END INLINED: SC2/SC2_Spike_mut_freq.R ----


# ============================================================================
# FRAMESHIFT / INSERTION / DELETION ANALYSIS (SC2)
# ============================================================================

export_graph <- add_section_slide(
  export_graph,
  "Frameshift/Insertion/Deletion",
  "Mutasjonstrender fordelt p\u00e5 type og gen (fasettert etter Tessy)"
)

sc2_indel_source <- if (exists("SC2db_v")) SC2db_v else SC2db
sc2_indel_date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(sc2_indel_source))[1]
sc2_indel_cols <- names(sc2_indel_source)[grepl("(frameshift|insertion|deletion)", names(sc2_indel_source), ignore.case = TRUE)]
sc2_tessy_col <- intersect(c("Tessy", "tessy"), names(sc2_indel_source))[1]

if (!is.na(sc2_indel_date_col) && length(sc2_indel_cols) > 0 && !is.na(sc2_tessy_col)) {
  sc2_indel_df <- sc2_indel_source %>%
    mutate(
      indel_plot_date = as.Date(.data[[sc2_indel_date_col]]),
      indel_month = floor_date(indel_plot_date, "month"),
      Tessy_group = as.character(.data[[sc2_tessy_col]])
    ) %>%
    filter(!is.na(indel_month), !is.na(Tessy_group), trimws(Tessy_group) != "", Tessy_group != "Ukjent")

  sc2_indel_df <- sc2_indel_df %>%
    mutate(Tessy_group = trimws(as.character(Tessy_group)))

  sc2_long <- sc2_indel_df %>%
    pivot_longer(cols = all_of(sc2_indel_cols), names_to = "mutation_col", values_to = "mutation_raw") %>%
    filter(!is.na(mutation_raw), trimws(as.character(mutation_raw)) != "") %>%
    separate_rows(mutation_raw, sep = ";|,") %>%
    mutate(
      mutation_raw = trimws(as.character(mutation_raw)),
      mutation_type = case_when(
        grepl("frameshift", mutation_col, ignore.case = TRUE) ~ "Frameshift",
        grepl("insertion", mutation_col, ignore.case = TRUE) ~ "Insertion",
        grepl("deletion", mutation_col, ignore.case = TRUE) ~ "Deletion",
        TRUE ~ "Andre"
      ),
      mutation_gene = sub("^(nc_[^_]+)_.*$", "\\1", mutation_col)
    ) %>%
    filter(
      mutation_raw != "",
      !tolower(mutation_raw) %in% c("na", "n/a", "none", "no mutations", "ikke_satt")
    )

  # Correct denominator: number of samples per month/Tessy in source data.
  # Use unique sample keys when available; otherwise fall back to row count.
  if ("key" %in% names(sc2_indel_df)) {
    sc2_month_totals <- sc2_indel_df %>%
      mutate(sample_key = as.character(key)) %>%
      mutate(sample_key = ifelse(is.na(sample_key) | trimws(sample_key) == "", NA_character_, sample_key)) %>%
      group_by(indel_month, Tessy_group) %>%
      summarise(
        total = ifelse(sum(!is.na(sample_key)) > 0, dplyr::n_distinct(sample_key, na.rm = TRUE), dplyr::n()),
        .groups = "drop"
      )
  } else {
    sc2_month_totals <- sc2_indel_df %>%
      count(indel_month, Tessy_group, name = "total")
  }

  mut_counts <- sc2_long %>%
    group_by(indel_month, Tessy_group, mutation_type, mutation_gene, mutation_raw) %>%
    summarise(n = n(), .groups = "drop") %>%
    left_join(sc2_month_totals, by = c("indel_month", "Tessy_group")) %>%
    mutate(percent = (n / total) * 100)

  if (nrow(mut_counts) > 0) {
    mutation_type_order <- c("Frameshift", "Deletion", "Insertion")
    for (m_type in mutation_type_order) {
      type_df <- mut_counts %>%
        filter(mutation_type == m_type)
      if (nrow(type_df) == 0) next

      gene_order <- type_df %>%
        count(mutation_gene, wt = n, name = "total_n") %>%
        arrange(desc(total_n), mutation_gene) %>%
        pull(mutation_gene)

      for (gene_name in gene_order) {
        gene_df <- type_df %>%
          filter(mutation_gene == gene_name) %>%
          mutate(
            mutation_raw = as.character(mutation_raw),
            mutation_raw = factor(mutation_raw, levels = rev(unique(mutation_raw[order(percent, na.last = TRUE)])))
          )
        if (nrow(gene_df) == 0) next

        indel_heatmap <- ggplot(gene_df, aes(x = indel_month, y = mutation_raw, fill = percent)) +
          geom_tile(color = "white") +
          facet_wrap(~Tessy_group, scales = "free_y", ncol = 3) +
          scale_fill_gradientn(colors = kvantitativ_b1, labels = scales::percent_format(scale = 1)) +
          scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
          labs(
            title = paste0("SC2 ", m_type, " - ", gene_name, " over tid"),
            subtitle = "Fasettert etter Tessy",
            x = "",
            y = "Mutasjon",
            fill = "Andel"
          ) +
          theme_minimal(base_size = 11) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))

        export_graph <- export_to_ppt(
          export_graph,
          indel_heatmap,
          paste0("SC2 ", m_type, " - ", gene_name, " per Tessy")
        )
      }
    }
  } else {
    message("Skipping SC2 indel split plots: no plottable mutation rows.")
  }
} else {
  message("Skipping SC2 indel analysis: missing date/Tessy column or no frameshift/insertion/deletion columns found.")
}

# ============================================================================
# ORF ANALYSIS - ALL GENES
# ============================================================================


# ============================================================================
# DRUG RESISTANCE ANALYSIS - TABLES
# ============================================================================

export_graph <- add_section_slide(
  export_graph,
  "Drug Resistance",
  "Resistance mutation tables across antiviral targets"
)

# Paxlovid resistance
dr_pax <- SC2db_v %>%
  group_by(Tessy, dr_3c_lpro_mut, dr_res_paxlovid, dr_3c_lpro_fold) %>%
  filter(!is.na(dr_3c_lpro_mut) &
    dr_3c_lpro_mut != "NA" &
    dr_3c_lpro_mut != "No Mutations" &
    dr_3c_lpro_mut != "" &
    Tessy != "") %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

# Remdesivir resistance
dr_remd <- SC2db_v %>%
  group_by(Tessy, dr_rd_rp_mut, dr_res_remdesevir, dr_rd_rp_fold) %>%
  filter(!is.na(dr_rd_rp_mut) &
    dr_rd_rp_mut != "NA" &
    dr_rd_rp_mut != "No Mutations" &
    dr_rd_rp_mut != "" &
    Tessy != "") %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

# Antibody resistance
dr_ab <- SC2db_v %>%
  group_by(Tessy, dr_spike_m_abs, dr_spike_m_abs_fold) %>%
  filter(!is.na(dr_3c_lpro_mut) &
    dr_spike_m_abs != "NA" &
    dr_spike_m_abs != "No Mutations" &
    dr_spike_m_abs != "" &
    Tessy != "") %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

# Create tables using kable
dr_pax_table <- kable(dr_pax, format = "markdown", caption = "Table 1: 3CLpro (Paxlovid/Nirmatrelvir ) resistance mutations")
dr_remd_table <- kable(dr_remd, format = "markdown", caption = "Table 2: RdRP (Remdesivir) resistance mutations")
dr_ab_table <- kable(dr_ab, format = "markdown", caption = "Table 3: Spike (Antibody) resistance mutations")

# Define a list of data frames and their respective captions
table_data <- list(
  list(data = dr_pax, caption = "Table 1: 3CLpro (Paxlovid/Nirmatrelvir ) resistance mutations"),
  list(data = dr_remd, caption = "Table 2: RdRP (Remdesivir) resistance mutations"),
  list(data = dr_ab, caption = "Table 3: Spike (Antibody) resistance mutations")
)

# Loop through each item in the list to generate and export tables
for (table_info in table_data) {
  # Create the table with kable for visualization (optional step)
  table <- kable(table_info$data, format = "markdown", caption = table_info$caption)

  # Print the table for visualization

  # Save the original data.frame to the PowerPoint presentation
  export_graph <- export_to_ppt(export_graph, table_info$data, table_info$caption)
}

# ============================================================================
# CT DISTRIBUTION BY TESSY (LAST 6 MONTHS)
# ============================================================================
export_graph <- add_section_slide(export_graph, "CT-verdier kvalitet", "PCR CT-fordelinger per Tessy")

# Use SC2db_v if it exists, otherwise default to SC2db_v.
ct_source_df <- if (exists("SC2db_v")) SC2db_v else SC2db_v

# Resolve column names robustly across naming styles in current datasets.
ct_col <- intersect(c("pcr_sc2_ext_ct", "PCR_SC2_EXT_CT"), names(ct_source_df))[1]
tessy_col <- intersect(c("Tessy", "tessy"), names(ct_source_df))[1]
pango_col <- intersect(c("nc_pangolin_short", "NC_Pangolin Short"), names(ct_source_df))[1]
date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(ct_source_df))[1]

if (!is.na(ct_col) && !is.na(tessy_col) && !is.na(pango_col) && !is.na(date_col)) {
  ct_plot_df <- ct_source_df %>%
    mutate(
      plot_date = as.Date(.data[[date_col]]),
      ct_raw = as.character(.data[[ct_col]]),
      ct_value = suppressWarnings(as.numeric(.data[[ct_col]])),
      tessy_group = as.character(.data[[tessy_col]]),
      pangolin_short = as.character(.data[[pango_col]])
    ) %>%
    filter(
      !is.na(plot_date),
      plot_date >= (Sys.Date() %m-% months(6)),
      !is.na(ct_raw),
      trimws(ct_raw) != "",
      is.finite(ct_value),
      !is.na(tessy_group),
      trimws(tessy_group) != "",
      !is.na(pangolin_short),
      trimws(pangolin_short) != ""
    )

  if (nrow(ct_plot_df) > 0) {
    # Combined comparison plot across all Tessy categories.
    ct_x_min <- floor(max(0, quantile(ct_plot_df$ct_value, 0.02, na.rm = TRUE) - 1))
    ct_x_max <- ceiling(min(40, quantile(ct_plot_df$ct_value, 0.98, na.rm = TRUE) + 1))
    if (!is.finite(ct_x_min) || !is.finite(ct_x_max) || ct_x_min >= ct_x_max) {
      ct_x_min <- 0
      ct_x_max <- 40
    }
    ct_x_breaks <- pretty(c(ct_x_min, ct_x_max), n = 8)

    ct_summary_df <- ct_plot_df %>%
      group_by(tessy_group) %>%
      summarise(
        n = n(),
        mean_ct = mean(ct_value, na.rm = TRUE),
        median_ct = median(ct_value, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      filter(is.finite(mean_ct), is.finite(median_ct)) %>%
      mutate(tessy_group = forcats::fct_reorder(tessy_group, median_ct))

    ct_plot_df <- ct_plot_df %>%
      mutate(tessy_group = factor(tessy_group, levels = levels(ct_summary_df$tessy_group)))

    ct_by_tessy_plot <- ggplot(ct_plot_df, aes(x = ct_value, y = tessy_group)) +
      geom_boxplot(outlier.shape = NA, width = 0.55, fill = "#BFD7EA", alpha = 0.45) +
      geom_jitter(aes(color = pangolin_short), height = 0.15, width = 0, alpha = 0.45, size = 1.6) +
      geom_point(data = ct_summary_df, aes(x = mean_ct, y = tessy_group), color = "#0072B2", size = 2.8) +
      geom_point(data = ct_summary_df, aes(x = median_ct, y = tessy_group), color = "#D55E00", size = 3.0, shape = 18) +
      geom_text(
        data = ct_summary_df,
        aes(x = ct_x_max, y = tessy_group, label = paste0("n=", n)),
        hjust = 1.05,
        size = 2.9,
        color = "grey25"
      ) +
      scale_x_continuous(breaks = ct_x_breaks) +
      coord_cartesian(xlim = c(ct_x_min, ct_x_max)) +
      guides(color = guide_legend(override.aes = list(alpha = 1, size = 3))) +
      labs(
        title = "PCR SC2 EXT CT per Tessy-kategori (siste 6 m\u00e5neder)",
        subtitle = "Grey: samples | Light blue box: IQR | Blue: mean | Orange diamond: median",
        x = "PCR_SC2_EXT_CT (zoomed)",
        y = "Tessy-kategori",
        color = "Pangolin short"
      ) +
      theme_minimal(base_size = 12)
    export_graph <- export_to_ppt(export_graph, ct_by_tessy_plot, "PCR SC2 EXT CT per Tessy-kategori (siste 6 m\u00e5neder)")
  } else {
    message("No rows available for Tessy CT plots in the last 6 months.")
  }
} else {
  message("Missing one or more required columns for Tessy CT plots: ct, tessy, pangolin, or date.")
}

# ============================================================================
# AGE DISTRIBUTION BY TESSY (3M/6M)
# ============================================================================

age_source_df <- if (exists("SC2db_v")) SC2db_v else SC2db

age_date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(age_source_df))[1]
age_tessy_col <- intersect(c("Tessy", "tessy"), names(age_source_df))[1]
age_col <- intersect(c("pasient_alder"), names(age_source_df))[1]

build_age_tessy_plot <- function(month_window, sentinel_only = FALSE) {
  if (is.na(age_date_col) || is.na(age_tessy_col)) {
    return(NULL)
  }
  if (is.na(age_col)) {
    return(NULL)
  }

  plot_df <- age_source_df %>%
    mutate(
      plot_date = as.Date(.data[[age_date_col]]),
      Tessy_plot = as.character(.data[[age_tessy_col]])
    ) %>%
    filter(
      !is.na(plot_date),
      plot_date >= (Sys.Date() %m-% months(month_window)),
      !is.na(Tessy_plot),
      trimws(Tessy_plot) != ""
    )

  if (sentinel_only) {
    if (!("prove_kategori_group" %in% names(plot_df))) {
      return(NULL)
    }
    plot_df <- plot_df %>% filter(prove_kategori_group == "Sentinel")
  }

  plot_df <- plot_df %>%
    mutate(
      pasient_alder_num = suppressWarnings(as.numeric(trimws(as.character(.data[[age_col]])))),
      age_group_raw = as.character(pasient_alder_num),
      pasient_aldersgruppe = as.character(age_to_group_standard(pasient_alder_num)),
      age_group_plot = case_when(
        pasient_aldersgruppe %in% c("0-4", "5-14", "15-24", "25-59", "60+") ~ pasient_aldersgruppe,
        TRUE ~ NA_character_
      )
    )

  age_levels <- c("0-4", "5-14", "15-24", "25-59", "60+")

  plot_df <- plot_df %>%
    mutate(age_group_plot = factor(age_group_plot, levels = age_levels)) %>%
    filter(!is.na(age_group_plot))

  if (nrow(plot_df) == 0) {
    return(NULL)
  }

  age_tessy_df <- plot_df %>%
    count(Tessy_plot, age_group_plot, name = "n") %>%
    group_by(Tessy_plot) %>%
    mutate(
      tessy_n = sum(n),
      percent = (n / tessy_n) * 100
    ) %>%
    ungroup()

  tessy_levels <- age_tessy_df %>%
    distinct(Tessy_plot, tessy_n) %>%
    arrange(desc(tessy_n), Tessy_plot) %>%
    pull(Tessy_plot)

  tessy_labels <- age_tessy_df %>%
    distinct(Tessy_plot, tessy_n) %>%
    mutate(label = paste0(Tessy_plot, "\n(n=", tessy_n, ")")) %>%
    {
      setNames(.$label, .$Tessy_plot)
    }

  age_tessy_df <- age_tessy_df %>%
    mutate(Tessy_plot = factor(Tessy_plot, levels = tessy_levels))

  # Diagnostics for last 6 months: raw labels and normalized labels
  if (month_window == 6 && !sentinel_only) {
    current_week_age <- week(Sys.Date())
    current_year_age <- year(Sys.Date())
    results_dir_age <- results_stats_dir

    raw_age_counts <- plot_df %>%
      count(Tessy_plot, age_group_raw, name = "n_raw") %>%
      arrange(desc(n_raw))

    norm_age_counts <- plot_df %>%
      count(Tessy_plot, age_group_plot, name = "n_norm") %>%
      arrange(Tessy_plot, age_group_plot)
  }

  ggplot(age_tessy_df, aes(x = Tessy_plot, y = percent, fill = age_group_plot)) +
    geom_col(position = "stack") +
    scale_x_discrete(labels = tessy_labels) +
    scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    coord_cartesian(ylim = c(0, 100)) +
    scale_fill_manual(values = kvalitativ_a) +
    labs(
      title = paste0(
        "Aldersgruppefordeling per ECDC-variantklassifisering",
        ifelse(sentinel_only, " (Sentinel only)", ""),
        " (last ", month_window, " months)"
      ),
      x = "ECDC Variant Classification",
      y = "Andel (%)",
      fill = "Age group"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.x = element_text(angle = 0, hjust = 0.5),
      panel.grid.major.x = element_blank()
    )
}

if (FALSE) {
  age_tessy_6m_plot <- build_age_tessy_plot(6)
  if (!is.null(age_tessy_6m_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_6m_plot, "Aldersgruppe andel per Tessy - siste 6 m\u00e5neder")
  } else {
    message("Could not create age-group Tessy plot for the last 6 months (missing required columns or rows).")
  }

  age_tessy_3m_plot <- build_age_tessy_plot(3)
  if (!is.null(age_tessy_3m_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_3m_plot, "Aldersgruppe andel per Tessy - siste 3 m\u00e5neder")
  } else {
    message("Could not create age-group Tessy plot for the last 3 months (missing required columns or rows).")
  }

  age_tessy_6m_sentinel_plot <- build_age_tessy_plot(6, sentinel_only = TRUE)
  if (!is.null(age_tessy_6m_sentinel_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_6m_sentinel_plot, "Aldersgruppe andel per Tessy (kun sentinel) - siste 6 m\u00e5neder")
  }

  age_tessy_3m_sentinel_plot <- build_age_tessy_plot(3, sentinel_only = TRUE)
  if (!is.null(age_tessy_3m_sentinel_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_3m_sentinel_plot, "Aldersgruppe andel per Tessy (kun sentinel) - siste 3 m\u00e5neder")
  }
}

# ============================================================================
# PATIENT/TESSY DISTRIBUTION BY REGION AND AGE
# ============================================================================
export_graph <- add_section_slide(export_graph, "Befolkning under overv\u00e5king")

patient_source_df <- if (exists("SC2db_v")) SC2db_v else SC2db
patient_tessy_col <- intersect(c("Tessy", "tessy"), names(patient_source_df))[1]
patient_date_col <- intersect(c("prove_tatt", "PROVE_TATT", "sample_date", "Sampledate"), names(patient_source_df))[1]
patient_fylke_col <- intersect(c("pasient_fylke_name", "fylkenavn", "pasient_fylke"), names(patient_source_df))[1]
patient_landsdel_col <- intersect(c("pasient_landsdel", "landsdel"), names(patient_source_df))[1]
patient_age_col <- intersect(c("pasient_alder"), names(patient_source_df))[1]

build_tessy_group_plots <- function(df, x_col, x_label, export_graph_in) {
  if (is.na(patient_tessy_col) || is.na(patient_date_col) || is.na(x_col)) {
    return(export_graph_in)
  }

  plot_df <- df %>%
    mutate(
      plot_date = as.Date(.data[[patient_date_col]]),
      season_plot = season_label_from_date(plot_date),
      Tessy_plot = as.character(.data[[patient_tessy_col]]),
      group_plot = as.character(.data[[x_col]])
    ) %>%
    filter(
      !is.na(plot_date),
      season_plot == current_season_label,
      !is.na(Tessy_plot), trimws(Tessy_plot) != "",
      !is.na(group_plot), trimws(group_plot) != "",
      group_plot != "IKKE_SATT"
    )

  if (nrow(plot_df) == 0) {
    return(export_graph_in)
  }

  grouped_df <- plot_df %>%
    count(group_plot, Tessy_plot, name = "n") %>%
    group_by(group_plot) %>%
    mutate(percent = (n / sum(n)) * 100) %>%
    ungroup()

  x_labels_df <- grouped_df %>%
    group_by(group_plot) %>%
    summarise(group_n = sum(n), .groups = "drop") %>%
    arrange(desc(group_n), group_plot) %>%
    mutate(group_label = paste0(group_plot, " (n=", group_n, ")"))

  grouped_df <- grouped_df %>%
    left_join(x_labels_df, by = "group_plot") %>%
    mutate(group_label = factor(group_label, levels = x_labels_df$group_label))

  p_pct <- ggplot(grouped_df, aes(x = group_label, y = percent, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    coord_cartesian(ylim = c(0, 100)) +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(title = paste0("Tessy-fordeling per ", x_label, " (%) - gjeldende sesong"), x = x_label, y = "Andel (%)", fill = "Tessy") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_count <- ggplot(grouped_df, aes(x = group_label, y = n, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(title = paste0("Tessy-fordeling per ", x_label, " (antall) - gjeldende sesong"), x = x_label, y = "Antall (n)", fill = "Tessy") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_out <- export_to_ppt(export_graph_in, p_pct, paste0("Tessy per ", x_label, " (%) - gjeldende sesong"))
  export_graph_out <- export_to_ppt(export_graph_out, p_count, paste0("Tessy per ", x_label, " (antall) - gjeldende sesong"))
  export_graph_out
}

if (!is.na(patient_tessy_col)) {
  patient_df <- patient_source_df
  if (!is.na(patient_age_col)) {
    patient_df <- patient_df %>%
      mutate(
        age_value_pd = suppressWarnings(as.numeric(trimws(as.character(.data[[patient_age_col]])))),
        pasient_aldersgruppe_sc2 = as.character(age_to_group_standard(age_value_pd))
      )
  } else {
    patient_df$pasient_aldersgruppe_sc2 <- NA_character_
  }
  patient_df <- normalize_sex_column(patient_df, candidate_cols = c("pasient_kjnn", "pasient_kjonn"))

  # Move these dimensions to the patient section as requested.
  patient_df <- patient_df %>%
    mutate(
      pasient_status_plot = if ("pasient_status" %in% names(.)) ifelse(is.na(pasient_status) | pasient_status == "" | pasient_status == "IKKE_SATT", "Ukjent", as.character(pasient_status)) else "Ukjent",
      prove_kategori_group_plot = if ("prove_kategori_group" %in% names(.)) as.character(prove_kategori_group) else classify_prove_kategori_group(prove_kategori),
      pasient_vaks_plot = if ("pasient_vaks" %in% names(.)) ifelse(is.na(pasient_vaks) | trimws(as.character(pasient_vaks)) == "", "Ukjent", as.character(pasient_vaks)) else "Ukjent",
      pasient_vaks_2uipt_plot = if ("pasient_vaks_2uipt" %in% names(.)) ifelse(is.na(pasient_vaks_2uipt) | trimws(as.character(pasient_vaks_2uipt)) == "", "Ukjent", as.character(pasient_vaks_2uipt)) else "Ukjent"
    )

  norway_geojson_path <- resolve_norway_geojson_path()
  sc2_prev <- patient_df %>% dplyr::filter(season == previous_season_label)
  sc2_curr <- patient_df %>% dplyr::filter(season == current_season_label)
  if (!is.na(patient_fylke_col)) {
    p_fylke_prev <- build_fylke_map_plot_shared(
      sc2_prev,
      fylke_col = patient_fylke_col,
      shape_path = norway_geojson_path,
      fill_palette = kvantitativ_b2
    )
    p_fylke_curr <- build_fylke_map_plot_shared(
      sc2_curr,
      fylke_col = patient_fylke_col,
      shape_path = norway_geojson_path,
      fill_palette = kvantitativ_b2
    )
    if (!is.null(p_fylke_curr) && !is.null(p_fylke_prev)) {
      p_fylke_pair <- (p_fylke_curr + labs(subtitle = paste0(current_season_label, " (m=", scales::comma(nrow(sc2_curr)), ")"))) |
        (p_fylke_prev + labs(subtitle = paste0(previous_season_label, " (m=", scales::comma(nrow(sc2_prev)), ")")))
      export_graph <- export_to_ppt(export_graph, p_fylke_pair, "Map: Fylke fordeling - left current, right previous")
    }
  }
  if (!is.na(patient_fylke_col) && !is.na(patient_landsdel_col)) {
    p_landsdel_prev <- build_landsdel_map_plot_shared(
      sc2_prev,
      fylke_col = patient_fylke_col,
      landsdel_col = patient_landsdel_col,
      shape_path = norway_geojson_path,
      palette_base = kvalitativ_comb
    )
    p_landsdel_curr <- build_landsdel_map_plot_shared(
      sc2_curr,
      fylke_col = patient_fylke_col,
      landsdel_col = patient_landsdel_col,
      shape_path = norway_geojson_path,
      palette_base = kvalitativ_comb
    )
    if (!is.null(p_landsdel_curr) && !is.null(p_landsdel_prev)) {
      p_landsdel_pair <- (p_landsdel_curr + labs(subtitle = paste0(current_season_label, " (m=", scales::comma(nrow(sc2_curr)), ")"))) |
        (p_landsdel_prev + labs(subtitle = paste0(previous_season_label, " (m=", scales::comma(nrow(sc2_prev)), ")")))
      export_graph <- export_to_ppt(export_graph, p_landsdel_pair, "Map: Landsdel fordeling - left current, right previous")
    }
  }

  if (all(c("pasient_kjonn_std", "season") %in% names(patient_df))) {
    p_kjonn <- build_two_season_pie_compare(
      patient_df,
      season_col = "season",
      category_col = "pasient_kjonn_std",
      previous_label = previous_season_label,
      current_label = current_season_label,
      category_label = "Kj\u00f8nn",
      palette_base = sc2_palette
    )
    if (!is.null(p_kjonn)) {
      export_graph <- export_to_ppt(export_graph, p_kjonn, "Kj\u00f8nn: sesongsammenligning")
    }
  }

  if ("pasient_aldersgruppe_sc2" %in% names(patient_df)) {
    p_alder <- build_two_season_pie_compare(
      patient_df,
      season_col = "season",
      category_col = "pasient_aldersgruppe_sc2",
      previous_label = previous_season_label,
      current_label = current_season_label,
      category_label = "Aldersgruppe",
      palette_base = sc2_palette
    )
    if (!is.null(p_alder)) {
      export_graph <- export_to_ppt(export_graph, p_alder, "Aldersgruppe: sesongsammenligning")
    }
  }

  export_graph <- build_tessy_group_plots(patient_df, patient_fylke_col, "Fylke", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, patient_landsdel_col, "Landsdel", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, "pasient_aldersgruppe_sc2", "Age group", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, "pasient_status_plot", "Patient status", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, "prove_kategori_group_plot", "Sample category group", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, "pasient_vaks_plot", "Vaccination status", export_graph)
  export_graph <- build_tessy_group_plots(patient_df, "pasient_vaks_2uipt_plot", "Vaccinated <=2 weeks before symptom onset", export_graph)
} else {
  message("Could not create patient Tessy plots (missing Tessy column).")
}

# ============================================================================
# PRINT AND SAVE FILES/GRAPHS
# ============================================================================

# Get the current week and year
current_week <- week(Sys.Date())
current_year <- year(Sys.Date())

# Create the file names with the current week and year
file_name_result <- paste0("SARSCOV2_", current_year, "_Week", current_week, "_result.pptx")
file_name_statistikk <- paste0("SARSCOV2_", current_year, "_Week", current_week, "_statistikk.csv")

# Specify the full file paths
file_path_result <- file.path(results_root, file_name_result)
file_path_resultshare <- file.path(results_share_dir, file_name_result)
file_path_statistikk <- file.path(results_stats_dir, file_name_statistikk)

write_ppt_safe <- function(ppt_obj, target_path) {
  tryCatch(
    {
      print(ppt_obj, target = target_path)
      target_path
    },
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("is open", msg, fixed = TRUE)) {
        alt_path <- file.path(
          dirname(target_path),
          paste0(tools::file_path_sans_ext(basename(target_path)), "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".pptx")
        )
        warning("Target PPTX is open; writing to fallback file: ", alt_path)
        print(ppt_obj, target = alt_path)
        alt_path
      } else {
        stop(e)
      }
    }
  )
}

# Print outputs
result_written_path <- timed_step("Write PPTX to Results", write_ppt_safe(export_graph, file_path_result))
share_written_path <- timed_step("Write PPTX to OneDrive share", write_ppt_safe(export_graph, file_path_resultshare))
timed_step("Write statistikk CSV", write.csv2(final_pangostatistikk, file_path_statistikk, row.names = FALSE))
log_timed_message("Result PPTX path: ", result_written_path)
log_timed_message("Share PPTX path: ", share_written_path)

total_elapsed_sec <- as.numeric(difftime(Sys.time(), analysis_started_at, units = "secs"))
log_timed_message("TOTAL RUNTIME: ", sprintf("%.2f", total_elapsed_sec), "s")

# nolint end





