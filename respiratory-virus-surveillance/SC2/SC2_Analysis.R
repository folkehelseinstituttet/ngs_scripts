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
  "odbc", "RSQLite", "DBI", "tidyverse", "ggrepel", "scales", "tools",
  "openxlsx", "here", "ISOweek", "RColorBrewer",
  "officer", "tsibble", "car", "writexl", "knitr", "gridExtra", "readxl",
  "data.table", "kableExtra", "webshot", "magick", "xml2",
  "patchwork", "gt", "flextable", "cowplot", "zoo", "reshape2",
  "janitor", "rvg", "sparkline", "treemapify"
)

# Use CRAN mirror in Germany for package installs/updates.
options(repos = c(CRAN = "https://cran.uni-muenster.de/"))

# Show warnings immediately and keep error messages visible in terminal.
options(warn = 1, show.error.messages = TRUE)

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
try(Sys.setlocale(locale = "nb_NO.UTF-8"), silent = TRUE)

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
  annotate("text", x = 0, y = 0.2, label = "SARS-CoV-2 Surveillance", size = 13, fontface = "bold", family = "sans") +
  annotate("text", x = 0, y = -0.1, label = paste0("Week ", current_week_title, " - ", current_year_title), size = 8, family = "sans") +
  xlim(-1, 1) + ylim(-1, 1) +
  theme_void()

export_graph <- export_to_ppt(export_graph, title_plot, paste0("SARS-CoV-2 Week ", current_week_title))
export_graph <- add_section_slide(export_graph, "Data Quality Checks", "Data integrity, completeness and consistency")



# ============================================================================
# DATA LOAD - SQL (BN)
# ============================================================================

timed_step("Source SC2_SQLquery_BNCOVID19.R", source(file.path(bundle_scripts_dir, "SC2_SQLquery_BNCOVID19.R")))
timed_step("Source SC2_SQLquery_25-26.R", source(file.path(bundle_scripts_dir, "SC2_SQLquery_25-26.R")))
timed_step("Source SC2_Classificaiton.R", source(file.path(bundle_scripts_dir, "SC2_Classificaiton.R")))

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
      title = paste0("Tessy distribution by ", x_label, " (%) - current season"),
      x = paste0(x_label, " (n)"),
      y = "Percent (%)",
      fill = "Tessy"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_count <- ggplot(grouped_df, aes(x = group_label, y = n, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(
      title = paste0("Tessy distribution by ", x_label, " (counts) - current season"),
      x = paste0(x_label, " (n)"),
      y = "Count",
      fill = "Tessy"
    ) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_out <- export_to_ppt(export_graph_in, p_pct, paste0("Tessy by ", x_label, " (%) - current season"))
  export_graph_out <- export_to_ppt(export_graph_out, p_count, paste0("Tessy by ", x_label, " (count) - current season"))
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

  # Coverage by Tessy and origin contribution over time.
  if (!is.na(eda_cov_col)) {
    coverage_df <- eda_df %>%
      mutate(
        coverage_value = suppressWarnings(as.numeric(as.character(.data[[eda_cov_col]])))
      ) %>%
      filter(!is.na(coverage_value), !is.na(Tessy_plot), trimws(Tessy_plot) != "")

    if (nrow(coverage_df) > 0) {
      coverage_df <- coverage_df %>%
        mutate(
          coverage_value_norm = ifelse(coverage_value > 1.5, coverage_value / 100, coverage_value)
        )

      p_coverage_tessy <- ggplot(coverage_df, aes(x = reorder(Tessy_plot, coverage_value_norm, median, na.rm = TRUE), y = coverage_value_norm)) +
        geom_boxplot(fill = fhi_discrete_palette(1, sc2_palette)[1], alpha = 0.35, outlier.alpha = 0.3) +
        coord_flip() +
        labs(
          title = "Coverage breadth by Tessy classification",
          x = "Tessy",
          y = "Coverage (normalized 0-1)"
        ) +
        theme_minimal(base_size = 12)
      export_graph <- export_to_ppt(export_graph, p_coverage_tessy, "Coverage by Tessy")
    }
  }

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

  # Numeric outlier scan (IQR-based) for all numeric columns.
  numeric_cols <- names(eda_df)[vapply(eda_df, is.numeric, logical(1))]
  if (length(numeric_cols) > 0) {
    outlier_scan <- lapply(numeric_cols, function(col_name) {
      x <- eda_df[[col_name]]
      x <- x[!is.na(x)]
      if (length(x) < 10) {
        return(NULL)
      }
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
    }
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
          x = "NGS run setup / run id",
          y = "Percent (%)",
          fill = "Status"
        ) +
        theme_minimal(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))

      p_ngs_perf_n <- ggplot(ngs_perf, aes(x = run_setup, y = n, fill = qc_status)) +
        geom_col(position = "stack") +
        scale_fill_manual(values = fhi_discrete_palette(n_distinct(ngs_perf$qc_status), sc2_palette)) +
        labs(
          title = "NGS run setup: included vs failed counts",
          x = "NGS run setup / run id",
          y = "Count",
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
        "Coverage QC by NGS run (summary table)"
      )

      if ("Tessy_plot" %in% names(ngs_cov_run_df) && any(!is.na(ngs_cov_run_df$Tessy_plot) & trimws(ngs_cov_run_df$Tessy_plot) != "")) {
        top_tessy_run <- ngs_cov_run_df %>%
          filter(!is.na(Tessy_plot), trimws(Tessy_plot) != "") %>%
          count(Tessy_plot, sort = TRUE) %>%
          slice_head(n = 8) %>%
          pull(Tessy_plot)

        ngs_cov_run_df <- ngs_cov_run_df %>%
          mutate(
            Tessy_plot = ifelse(is.na(Tessy_plot) | trimws(Tessy_plot) == "", "Unknown", Tessy_plot),
            Tessy_plot = ifelse(Tessy_plot %in% top_tessy_run, Tessy_plot, "Other")
          )

        p_cov_run_box <- ggplot(ngs_cov_run_df, aes(x = run_setup, y = cov_norm)) +
          geom_boxplot(fill = "grey90", color = "grey30", outlier.shape = NA) +
          geom_jitter(aes(color = Tessy_plot), width = 0.2, height = 0, alpha = 0.7, size = 1.6) +
          scale_color_manual(values = fhi_discrete_palette(n_distinct(ngs_cov_run_df$Tessy_plot), sc2_palette)) +
          labs(
            title = "Coverage by NGS run setup",
            subtitle = "Box/whisker per run; each sample colored by Tessy (top 8 + Other)",
            x = "NGS run setup / run id",
            y = "Normalized coverage (0-1)",
            color = "Tessy"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      } else {
        p_cov_run_box <- ggplot(ngs_cov_run_df, aes(x = run_setup, y = cov_norm)) +
          geom_boxplot(fill = "grey90", color = "grey30", outlier.shape = NA) +
          geom_jitter(width = 0.2, height = 0, alpha = 0.6, size = 1.5, color = "#1f77b4") +
          labs(
            title = "Coverage by NGS run setup",
            subtitle = "Box/whisker per run; Tessy not available for point coloring",
            x = "NGS run setup / run id",
            y = "Normalized coverage (0-1)"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))
      }

      export_graph <- export_to_ppt(export_graph, p_cov_run_box, "Coverage by run setup (boxplot + sample points)")
    }

    # Coverage by month colored by subclade/lineage.
    if (!is.na(ngs_subclade_col)) {
      ngs_cov_month_df <- ngs_qc_df %>%
        mutate(
          month_date = floor_date(plot_date, unit = "month"),
          subclade_plot = as.character(.data[[ngs_subclade_col]]),
          subclade_plot = ifelse(is.na(subclade_plot) | trimws(subclade_plot) == "", "Unknown", subclade_plot)
        ) %>%
        filter(!is.na(cov_norm), !is.na(month_date))

      if (nrow(ngs_cov_month_df) > 0) {
        top_subclades <- ngs_cov_month_df %>%
          count(subclade_plot, sort = TRUE) %>%
          slice_head(n = 10) %>%
          pull(subclade_plot)

        ngs_cov_month_df <- ngs_cov_month_df %>%
          mutate(subclade_plot = ifelse(subclade_plot %in% top_subclades, subclade_plot, "Other")) %>%
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
            title = "Coverage by month colored by subclade",
            subtitle = "Median coverage per month; top 10 subclades shown separately",
            x = "Month",
            y = "Normalized coverage (0-1)",
            color = "Subclade",
            size = "n"
          ) +
          theme_minimal(base_size = 12) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))

        export_graph <- export_to_ppt(export_graph, p_cov_month_subclade, "Coverage by month and subclade")
      }
    }

  }
}


# ============================================================================
# SEQUENCE SUMMARY - WEEK/MONTH
# ============================================================================

export_graph <- add_section_slide(export_graph, "Coverage", "Coverage breadth and sequencing performance")
timed_step("Source SC2_Seqs_per_month.R", source(file.path(bundle_scripts_dir, "SC2_Seqs_per_month.R")))

# ============================================================================
# PANGOLIN ANALYSIS - OVERVIEW
# ============================================================================

export_graph <- add_section_slide(export_graph, "Pangolin And Tessy Per Month", "Monthly lineage and Tessy composition")
timed_step("Source SC2_Pangolin_p_m.R", source(file.path(bundle_scripts_dir, "SC2_Pangolin_p_m.R")))
timed_step("Source SC2_Tessy_p_m.R", source(file.path(bundle_scripts_dir, "SC2_Tessy_p_m.R")))

# ============================================================================
# MUTATION ANALYSIS - COMBINATIONS
# ============================================================================

export_graph <- add_section_slide(export_graph, "Mutation Analysis", "Mutation combinations, frequencies and domains")
timed_step("Source SC2_Spike_mut_of_interest.R", source(file.path(bundle_scripts_dir, "SC2_Spike_mut_of_interest.R")))

# ============================================================================
# MUTATION ANALYSIS - PANGOLIN FOCUS
# ============================================================================

timed_step("Source SC2_Spike_mut_freq.R", source(file.path(bundle_scripts_dir, "SC2_Spike_mut_freq.R")))

# ============================================================================
# FRAMESHIFT / INSERTION / DELETION ANALYSIS (SC2)
# ============================================================================

export_graph <- add_section_slide(
  export_graph,
  "Frameshift/Insertion/Deletion",
  "Mutation trends split by type, then gene (facetted by Tessy)"
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
        TRUE ~ "Other"
      ),
      mutation_gene = sub("^(nc_[^_]+)_.*$", "\\1", mutation_col)
    ) %>%
    filter(
      mutation_raw != "",
      !tolower(mutation_raw) %in% c("na", "n/a", "none", "no mutations", "ikke_satt")
    )

  # Correct denominator: number of samples per month/Tessy in source data.
  sc2_month_totals <- sc2_indel_df %>%
    distinct(indel_month, Tessy_group, .keep_all = TRUE) %>%
    count(indel_month, Tessy_group, name = "total")

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
            subtitle = "Facetted by Tessy",
            x = "",
            y = "Mutasjon",
            fill = "Andel"
          ) +
          theme_minimal(base_size = 11) +
          theme(axis.text.x = element_text(angle = 45, hjust = 1))

        export_graph <- export_to_ppt(
          export_graph,
          indel_heatmap,
          paste0("SC2 ", m_type, " - ", gene_name, " by Tessy")
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
  print(table)

  # Save the original data.frame to the PowerPoint presentation
  export_graph <- export_to_ppt(export_graph, table_info$data, table_info$caption)
}

# ============================================================================
# CT DISTRIBUTION BY TESSY (LAST 6 MONTHS)
# ============================================================================
export_graph <- add_section_slide(export_graph, "CT Values Quality", "PCR CT distributions by Tessy")

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
        title = "PCR SC2 EXT CT by Tessy category (last 6 months)",
        subtitle = "Grey: samples | Light blue box: IQR | Blue: mean | Orange diamond: median",
        x = "PCR_SC2_EXT_CT (zoomed)",
        y = "Tessy category",
        color = "Pangolin short"
      ) +
      theme_minimal(base_size = 12)
    export_graph <- export_to_ppt(export_graph, ct_by_tessy_plot, "PCR SC2 EXT CT by Tessy category (last 6 months)")
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
      pasient_aldersgruppe = case_when(
        pasient_alder_num >= 0 & pasient_alder_num <= 4 ~ "0-4",
        pasient_alder_num >= 5 & pasient_alder_num <= 14 ~ "5-14",
        pasient_alder_num >= 15 & pasient_alder_num <= 24 ~ "15-24",
        pasient_alder_num >= 25 & pasient_alder_num <= 59 ~ "25-59",
        pasient_alder_num >= 60 ~ "60+",
        TRUE ~ "Ukjent"
      ),
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
        "Age-group distribution by ECDC Variant Classification",
        ifelse(sentinel_only, " (Sentinel only)", ""),
        " (last ", month_window, " months)"
      ),
      x = "ECDC Variant Classification",
      y = "Percent (%)",
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
    export_graph <- export_to_ppt(export_graph, age_tessy_6m_plot, "Age-group percent by Tessy - last 6 months")
  } else {
    message("Could not create age-group Tessy plot for the last 6 months (missing required columns or rows).")
  }

  age_tessy_3m_plot <- build_age_tessy_plot(3)
  if (!is.null(age_tessy_3m_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_3m_plot, "Age-group percent by Tessy - last 3 months")
  } else {
    message("Could not create age-group Tessy plot for the last 3 months (missing required columns or rows).")
  }

  age_tessy_6m_sentinel_plot <- build_age_tessy_plot(6, sentinel_only = TRUE)
  if (!is.null(age_tessy_6m_sentinel_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_6m_sentinel_plot, "Age-group percent by Tessy (Sentinel only) - last 6 months")
  }

  age_tessy_3m_sentinel_plot <- build_age_tessy_plot(3, sentinel_only = TRUE)
  if (!is.null(age_tessy_3m_sentinel_plot)) {
    export_graph <- export_to_ppt(export_graph, age_tessy_3m_sentinel_plot, "Age-group percent by Tessy (Sentinel only) - last 3 months")
  }
}

# ============================================================================
# PATIENT/TESSY DISTRIBUTION BY REGION AND AGE
# ============================================================================
export_graph <- add_section_slide(export_graph, "Population Under Surveillance")

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
    labs(title = paste0("Tessy distribution by ", x_label, " (%) - current season"), x = paste0(x_label, " (n)"), y = "Percent (%)", fill = "Tessy") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  p_count <- ggplot(grouped_df, aes(x = group_label, y = n, fill = Tessy_plot)) +
    geom_col(position = "stack") +
    scale_fill_manual(values = fhi_discrete_palette(n_distinct(grouped_df$Tessy_plot), sc2_palette)) +
    labs(title = paste0("Tessy distribution by ", x_label, " (counts) - current season"), x = paste0(x_label, " (n)"), y = "Count", fill = "Tessy") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  export_graph_out <- export_to_ppt(export_graph_in, p_pct, paste0("Tessy by ", x_label, " (%) - current season"))
  export_graph_out <- export_to_ppt(export_graph_out, p_count, paste0("Tessy by ", x_label, " (count) - current season"))
  export_graph_out
}

if (!is.na(patient_tessy_col)) {
  patient_df <- patient_source_df
  if (!is.na(patient_age_col)) {
    patient_df <- patient_df %>%
      mutate(
        age_value_pd = suppressWarnings(as.numeric(trimws(as.character(.data[[patient_age_col]])))),
        pasient_aldersgruppe_sc2 = case_when(
          age_value_pd >= 0 & age_value_pd <= 4 ~ "0-4",
          age_value_pd >= 5 & age_value_pd <= 14 ~ "5-14",
          age_value_pd >= 15 & age_value_pd <= 24 ~ "15-24",
          age_value_pd >= 25 & age_value_pd <= 59 ~ "25-59",
          age_value_pd >= 60 ~ "60+",
          TRUE ~ "Ukjent"
        )
      )
  } else {
    patient_df$pasient_aldersgruppe_sc2 <- NA_character_
  }

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

  if (all(c("pasient_kjnn", "season") %in% names(patient_df))) {
    p_kjonn <- build_two_season_pie_compare(
      patient_df,
      season_col = "season",
      category_col = "pasient_kjnn",
      previous_label = previous_season_label,
      current_label = current_season_label,
      category_label = "Kjønn",
      palette_base = sc2_palette
    )
    if (!is.null(p_kjonn)) {
      export_graph <- export_to_ppt(export_graph, p_kjonn, "Kjønn: sesongsammenligning")
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


