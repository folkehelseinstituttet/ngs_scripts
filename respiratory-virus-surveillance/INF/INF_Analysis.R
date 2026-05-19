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

invisible(timed_step("Source INF SQL query script", source(file.path(bundle_scripts_dir, "INF_SQLquery_25-26.R"))))

# ==============================================================================
# Setup
# ==============================================================================

# Load necessary libraries with reduced startup warning noise.
load_required_libraries <- function(packages) {
  lapply(packages, function(pkg) {
    withCallingHandlers(
      suppressPackageStartupMessages(library(pkg, character.only = TRUE)),
      warning = function(w) {
        if (grepl("was built under R version", conditionMessage(w), fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
  })
}

required_packages <- c(
  "ggplot2", "dplyr", "cowplot", "scales", "lubridate", "kableExtra", "zoo",
  "patchwork", "stringr", "tidyr", "flextable", "officer", "knitr", "reshape2",
  "ggrepel", "tools", "rvg"
)
invisible(load_required_libraries(required_packages))
invisible(timed_step("Source common report utilities", source("Source_files/common_report_utils.R")))
invisible(timed_step("Source shared patient/prove plot helpers", source("Source_files/shared_patient_prove_plots.R")))

Sys.setlocale("LC_TIME", "nb_NO.utf8")
export_graph_f <- read_pptx()
excel_export_sheets <- list()

axis_count_label <- "Antall (n)"
axis_share_label <- "Andel (%)"

fhi_text_dark <- tail(kvantitativ_b1, 1)
fhi_text_mid <- kvantitativ_b1[ceiling(length(kvantitativ_b1) / 2)]

# ==============================================================================
# Functions
# ==============================================================================

# Shared helpers are sourced from Source_files/common_report_utils.R.

# ==============================================================================
# fludb preprocessing
# ==============================================================================

# Identify all Ct columns so they can be standardized before analysis.
ct_columns <- grep("_ct", names(fludb), value = TRUE)

# Replace decimal commas and coerce Ct values to numeric.
for (col in ct_columns) {
  # Replace commas with periods
  fludb[[col]] <- gsub(",", ".", fludb[[col]])

  # Convert the column to numeric while handling blanks/non-numeric entries quietly.
  fludb[[col]] <- suppressWarnings(as.numeric(fludb[[col]]))
}

# Remove hidden control characters that can break flextable/PowerPoint export.
fludb <- fludb %>%
  mutate(
    across(
      where(is.character),
      ~ str_replace_all(.x, "[[:cntrl:]]", "")
    )
  )

fludb <- fludb %>%
  mutate(
    pasient_alder = as.numeric(trimws(pasient_alder)) # Trim whitespace and convert to numeric
  )


# Standardize core date, age, patient, and category fields used downstream.
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
clean_pasient_status <- function(x) {
  x_chr <- toupper(trimws(as.character(x)))
  x_chr <- gsub("\\s+", "", x_chr)
  x_chr <- sub("_ST$", "", x_chr) # Drop hospitalization suffix for status grouping.
  x_chr <- gsub(":+$", "", x_chr) # Drop trailing punctuation (e.g., P11: -> P11).
  x_chr <- ifelse(grepl("^P[0-9]+", x_chr), sub("^(P[0-9]+).*$", "\\1", x_chr), x_chr)
  x_chr <- sub("_+$", "", x_chr) # Normalize trailing underscores (e.g., P1_ -> P1).
  x_chr <- ifelse(is.na(x) | x_chr == "" | x_chr == "IKKE_SATT", "Ukjent", x_chr)
  x_chr
}

fludb <- fludb %>%
  mutate(
    prove_tatt = as.Date(prove_tatt), # Ensure `prove_tatt` is in Date format
    season = season_label_from_date(prove_tatt),
    month_year = format_month_label(prove_tatt), # Create unified month-year column
    week_year = isoweek(prove_tatt), # Extract ISO week number
    year = year(prove_tatt), # Extract the year
    pasient_aldersgruppe = case_when(
      # Create age groups based on `pasient_alder`
      pasient_alder >= 0 & pasient_alder <= 4 ~ "0-4",
      pasient_alder >= 5 & pasient_alder <= 14 ~ "5-14",
      pasient_alder >= 15 & pasient_alder <= 24 ~ "15-24",
      pasient_alder >= 25 & pasient_alder <= 59 ~ "25-59",
      pasient_alder >= 60 ~ "60+",
      TRUE ~ "Ukjent"
    ),
    pasient_status = clean_pasient_status(pasient_status),
    prove_kategori = as.character(prove_kategori),
    prove_kategori_group = classify_prove_kategori_group(prove_kategori),
    prove_project_clean = ifelse(prove_kategori_group == "Non-Sentinel", clean_project_code(prove_kategori), NA_character_)
  )

season_info <- current_and_previous_seasons(Sys.Date())
current_season_label <- season_info$current_label
previous_season_label <- season_info$previous_label

normalize_norwegian_text <- function(x) {
  iconv(x, from = "", to = "UTF-8", sub = "")
}

derive_landsdel_from_fylke <- function(fylke_vec) {
  f <- normalize_norwegian_text(as.character(fylke_vec))
  f <- trimws(f)
  f <- stringr::str_to_lower(f)

  dplyr::case_when(
    f %in% c("agder", "aust-agder", "vest-agder") ~ "Sørlandet",
    f %in% c("rogaland", "vestland", "hordaland", "sogn og fjordane", "møre og romsdal") ~ "Vestlandet",
    f %in% c("trøndelag", "sør-trøndelag", "nord-trøndelag") ~ "Trøndelag",
    f %in% c("nordland", "troms", "finnmark", "troms og finnmark") ~ "Nord-Norge",
    f %in% c("oslo", "akershus", "østfold", "buskerud", "innlandet", "vestfold", "telemark", "vestfold og telemark", "viken", "hedmark", "oppland") ~ "Østlandet",
    TRUE ~ NA_character_
  )
}

if ("pasient_landsdel" %in% names(fludb)) {
  fludb$pasient_landsdel <- normalize_norwegian_text(fludb$pasient_landsdel)
  fludb$pasient_landsdel <- dplyr::recode(
    fludb$pasient_landsdel,
    "Sorlandet" = "S\u00f8rlandet",
    "Trondelag" = "Tr\u00f8ndelag",
    "Ostlandet" = "\u00d8stlandet",
    .default = fludb$pasient_landsdel
  )
}
if ("pasient_fylke_name" %in% names(fludb)) {
  fludb$pasient_fylke_name <- normalize_norwegian_text(fludb$pasient_fylke_name)
  fludb$pasient_landsdel_from_fylke <- derive_landsdel_from_fylke(fludb$pasient_fylke_name)
}

# Rebuild subclade signature map on each run; if rebuild fails, use repo fallback.
signature_script_path <- file.path("Source_files", "Subclade_mutations_INF.ps1")
signature_map_results_path <- file.path("Results", "Subclade_mutations_INF.csv")
signature_map_fallback_path <- file.path("Source_files", "Subclade_mutations_INF.csv")

if (file.exists(signature_script_path)) {
  timed_step("Rebuild Subclade_mutations_INF.csv", {
    script_call <- tryCatch(
      system2(
        "powershell",
        c(
          "-ExecutionPolicy", "Bypass",
          "-File", signature_script_path,
          "-OutCsv", signature_map_results_path
        ),
        stdout = TRUE,
        stderr = TRUE
      ),
      error = function(e) e
    )
    if (inherits(script_call, "error")) {
      warning("Subclade_mutations_INF rebuild failed: ", conditionMessage(script_call))
    }
  })
}

if (file.exists(signature_map_results_path)) {
  signature_map_path <- signature_map_results_path
} else if (file.exists(signature_map_fallback_path)) {
  warning("Using fallback signature CSV from Source_files/Subclade_mutations_INF.csv")
  signature_map_path <- signature_map_fallback_path
} else {
  stop("Missing signature CSV. Expected Results/Subclade_mutations_INF.csv or Source_files/Subclade_mutations_INF.csv")
}

ha_signature_map <- read.csv(signature_map_path, stringsAsFactors = FALSE, check.names = FALSE)

extract_mutation_key <- function(x) {
  # Return normalized position+new-AA key (e.g., "144N") from strings like
  # "HA1:144N", "S144N", "K144N", " HA1:S144N ", "HA1:163'-'".
  x <- toupper(trimws(as.character(x)))
  if (is.na(x) || x == "") {
    return(NA_character_)
  }
  # Normalize quoted deletion notation used in some clade definitions: 163'-' -> 163-
  x <- gsub("([0-9]+)'-'", "\\1-", x, perl = TRUE)
  # Prefer full substitution token if present (e.g., S144N -> 144N)
  full_sub <- stringr::str_extract(x, "[A-Z][0-9]+[A-Z]$")
  if (!is.na(full_sub) && full_sub != "") {
    return(sub("^[A-Z]([0-9]+[A-Z])$", "\\1", full_sub))
  }
  # Handle residue deletions represented as trailing "-" (e.g., 163- or S163-).
  full_del <- stringr::str_extract(x, "[A-Z][0-9]+-$")
  if (!is.na(full_del) && full_del != "") {
    return(sub("^[A-Z]([0-9]+-)$", "\\1", full_del))
  }
  # Fallback for entries already in compact form (e.g., 144N)
  compact <- stringr::str_extract(x, "[0-9]+[A-Z-]$")
  if (!is.na(compact) && compact != "") {
    return(compact)
  }
  NA_character_
}

ha_signature_lookup <- ha_signature_map %>%
  mutate(
    ha_cluster_defining_mutations = strsplit(ha_cluster_defining_mutations, ";\\s*")
  ) %>%
  tidyr::unnest(ha_cluster_defining_mutations) %>%
  mutate(
    ha_cluster_defining_mutations = trimws(ha_cluster_defining_mutations)
  ) %>%
  filter(grepl("^HA1:", ha_cluster_defining_mutations)) %>%
  mutate(
    signature_token = vapply(ha_cluster_defining_mutations, extract_mutation_key, character(1))
  ) %>%
  filter(!is.na(signature_token), signature_token != "") %>%
  distinct(ngs_sekvens_resultat, nc_ha_subclade, signature_token, .keep_all = TRUE)

signature_token_by_subclade <- split(
  ha_signature_lookup$signature_token,
  paste(ha_signature_lookup$ngs_sekvens_resultat, ha_signature_lookup$nc_ha_subclade, sep = "||")
)

extract_cluster_mutation_string <- function(mut_str, subtype, subclade) {
  if (is.na(mut_str) || mut_str == "" || is.na(subtype) || is.na(subclade) || subclade == "") {
    return("")
  }
  key <- paste(subtype, subclade, sep = "||")
  sig <- signature_token_by_subclade[[key]]
  if (is.null(sig) || length(sig) == 0) {
    return("")
  }
  muts <- trimws(unlist(strsplit(mut_str, ";|,")))
  muts <- muts[muts != ""]
  if (length(muts) == 0) {
    return("")
  }
  toks <- vapply(muts, extract_mutation_key, character(1))
  keep <- !is.na(toks) & toks %in% sig
  if (!any(keep)) {
    return("")
  }
  paste(muts[keep], collapse = ";")
}

extract_non_signature_mutation_string <- function(mut_str, subtype, subclade) {
  if (is.na(subtype) || is.na(subclade) || subclade == "") {
    return("")
  }
  if (is.na(mut_str) || trimws(mut_str) == "") {
    return("")
  }
  key <- paste(subtype, subclade, sep = "||")
  sig <- signature_token_by_subclade[[key]]
  if (is.null(sig)) {
    sig <- character(0)
  }
  muts <- trimws(unlist(strsplit(mut_str, ";|,")))
  muts <- muts[muts != ""]
  if (length(muts) == 0) {
    return("")
  }
  toks <- vapply(muts, extract_mutation_key, character(1))
  keep <- !is.na(toks) & !(toks %in% sig) & !grepl("X", toks, ignore.case = TRUE)
  muts_kept <- muts[keep]
  if (length(muts_kept) == 0) {
    return("")
  }
  # Canonicalize kept mutations for stable labels: unique and sorted by position then aa.
  kept_tokens <- unique(vapply(muts_kept, extract_mutation_key, character(1)))
  kept_tokens <- kept_tokens[!is.na(kept_tokens) & kept_tokens != ""]
  if (length(kept_tokens) == 0) {
    return("")
  }
  kept_pos <- suppressWarnings(as.integer(stringr::str_extract(kept_tokens, "^[0-9]+")))
  ord <- order(kept_pos, kept_tokens, na.last = TRUE)
  paste(kept_tokens[ord], collapse = ";")
}

fludb$mut_ha1_cluster_defining <- mapply(
  extract_cluster_mutation_string,
  fludb$mut_ha1_1,
  fludb$ngs_sekvens_resultat,
  fludb$nc_ha_subclade,
  USE.NAMES = FALSE
)

fludb$mut_ha1_without_subclade_signature <- mapply(
  extract_non_signature_mutation_string,
  fludb$mut_ha1_1,
  fludb$ngs_sekvens_resultat,
  fludb$nc_ha_subclade,
  USE.NAMES = FALSE
)



# ==============================================================================
# Common influenza analysis datasets from fludb
# ==============================================================================

reportable_subtype_fludb <- fludb %>%
  filter(
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !(is.na(tessy_reportable_variable) |
      tessy_reportable_variable == "" |
      tessy_reportable_variable == "NA" |
      tessy_reportable_variable == "NULL")
  ) %>%
  select(
    month_year,
    ngs_sekvens_resultat,
    tessy_reportable_variable,
    nc_ha_clade,
    nc_ha_subclade
  )

clade_subclade_fludb <- reportable_subtype_fludb %>%
  filter(
    !is.na(nc_ha_clade),
    nc_ha_clade != "",
    !is.na(nc_ha_subclade),
    nc_ha_subclade != ""
  )

# ==============================================================================
# Data completeness and issues (SC2-style first section)
# ==============================================================================
export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Data completeness og issues",
  "Datakompletthet, kvalitetsavvik og standardisert pasientmetadata"
)

patient_metadata_columns <- c(
  "prove_tatt", "month_year", "week_year", "year",
  "pasient_alder", "pasient_aldersgruppe",
  "pasient_status", "pasient_landsdel", "pasient_fylke_name",
  "prove_kategori", "ngs_sekvens_resultat", "tessy_reportable_variable",
  "nc_ha_clade", "nc_ha_subclade"
)
patient_metadata_columns <- intersect(patient_metadata_columns, names(fludb))

patient_metadata_standard <- fludb %>%
  select(all_of(patient_metadata_columns))

data_completeness_tbl <- tibble(
  column = names(patient_metadata_standard),
  class = vapply(patient_metadata_standard, function(x) paste(class(x), collapse = ","), character(1)),
  non_missing_n = vapply(
    patient_metadata_standard,
    function(x) sum(!is.na(x) & trimws(as.character(x)) != ""),
    numeric(1)
  ),
  missing_n = nrow(patient_metadata_standard) - non_missing_n,
  missing_pct = round((missing_n / nrow(patient_metadata_standard)) * 100, 2),
  unique_n = vapply(patient_metadata_standard, function(x) dplyr::n_distinct(x, na.rm = TRUE), numeric(1))
) %>%
  arrange(desc(missing_pct), desc(missing_n))

export_graph_f <- save_table_to_ppt(
  export_graph_f,
  data_completeness_tbl,
  "Datakompletthet for standardiserte pasientmetadata-kolonner"
)

issue_counts <- list()

if ("key" %in% names(fludb)) {
  issue_counts[["duplicate_key_n"]] <- fludb %>%
    filter(!is.na(key), trimws(as.character(key)) != "") %>%
    count(key) %>%
    filter(n > 1) %>%
    nrow()
}

if ("prove_tatt" %in% names(fludb)) {
  issue_counts[["missing_prove_tatt_n"]] <- sum(is.na(fludb$prove_tatt))
  issue_counts[["future_prove_tatt_n"]] <- sum(fludb$prove_tatt > Sys.Date(), na.rm = TRUE)
}

if ("pasient_alder" %in% names(fludb)) {
  issue_counts[["missing_pasient_alder_n"]] <- sum(is.na(fludb$pasient_alder))
  issue_counts[["pasient_alder_lt_0_n"]] <- sum(fludb$pasient_alder < 0, na.rm = TRUE)
  issue_counts[["pasient_alder_gt_110_n"]] <- sum(fludb$pasient_alder > 110, na.rm = TRUE)
}

cov_col <- intersect(
  c("nc_coverage", "coverage_breadth_artic", "coverage_breadth_swift", "coverage_breadth_eksterne", "coverage_breadth_nano"),
  names(fludb)
)[1]
if (!is.na(cov_col)) {
  cov_vals <- suppressWarnings(as.numeric(as.character(fludb[[cov_col]])))
  issue_counts[["missing_coverage_n"]] <- sum(is.na(cov_vals))
  issue_counts[["coverage_lt_0_n"]] <- sum(cov_vals < 0, na.rm = TRUE)
  issue_counts[["coverage_gt_100_n"]] <- sum(cov_vals > 100, na.rm = TRUE)
}

issues_tbl <- tibble(
  metric = names(issue_counts),
  value = as.numeric(unlist(issue_counts))
)

export_graph_f <- save_table_to_ppt(
  export_graph_f,
  issues_tbl,
  "Data issues (QC-avvik) for pasientmetadata og dekning"
)

# Coverage by subtype and subclade (requested SC2-like coverage view)
if (!is.na(cov_col)) {
  coverage_subclade_df <- fludb %>%
    filter(
      ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
      !is.na(nc_ha_subclade), nc_ha_subclade != ""
    ) %>%
    mutate(
      coverage_value = suppressWarnings(as.numeric(as.character(.data[[cov_col]]))),
      coverage_norm = ifelse(coverage_value > 1.5, coverage_value / 100, coverage_value),
      month_date = parse_month_label(month_year)
    ) %>%
    filter(!is.na(coverage_norm), is.finite(coverage_norm))

  if (nrow(coverage_subclade_df) > 0) {
    coverage_box_plot <- ggplot(
      coverage_subclade_df,
      aes(x = nc_ha_subclade, y = coverage_norm, fill = nc_ha_subclade)
    ) +
      geom_boxplot(outlier.shape = NA, alpha = 0.6) +
      geom_jitter(width = 0.25, alpha = 0.25, size = 1) +
      facet_wrap(~ngs_sekvens_resultat, scales = "free_x") +
      scale_fill_manual(values = kvalitativ_comb) +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), expand = c(0, 0)) +
      labs(
        title = "Dekning per subtype og subklade (boxplot)",
        x = "Subklade",
        y = "Normalisert dekning",
        fill = "Subklade"
      ) +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "none")

    export_graph_f <- save_plot_to_ppt(export_graph_f, coverage_box_plot)

    coverage_trend_plot <- coverage_subclade_df %>%
      group_by(month_date, ngs_sekvens_resultat, nc_ha_subclade) %>%
      summarise(mean_coverage = mean(coverage_norm, na.rm = TRUE), .groups = "drop") %>%
      ggplot(aes(x = month_date, y = mean_coverage, color = nc_ha_subclade)) +
      geom_line(linewidth = 1) +
      facet_wrap(~ngs_sekvens_resultat, scales = "free_y") +
      scale_color_manual(values = kvalitativ_comb) +
      scale_x_date(labels = format_month_label, date_breaks = "1 month") +
      scale_y_continuous(labels = scales::percent_format(accuracy = 1), expand = c(0, 0)) +
      labs(
        title = "Månedlig dekningstrend per subtype og subklade",
        x = "Måned",
        y = "Gjennomsnittlig normalisert dekning",
        color = "Subklade"
      ) +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))

    export_graph_f <- save_plot_to_ppt(export_graph_f, coverage_trend_plot)
  }
}

# Run quality issues by virus (H1/H3/BVIC), colored by NC_quality (RSV-style)
quality_col_flu <- intersect(c("NC_quality", "nc_quality", "nc_qc_overall_status"), names(fludb))[1]
if (!is.na(cov_col) && !is.na(quality_col_flu) && all(c("ngs_run_id", "ngs_sekvens_resultat") %in% names(fludb))) {
  run_qc_window <- run_quality_window_bounds(Sys.Date(), min_months = 6L)
  fludb_run_qc <- fludb %>%
    mutate(prove_tatt = as.Date(prove_tatt)) %>%
    filter(!is.na(prove_tatt), prove_tatt >= run_qc_window$start, prove_tatt <= run_qc_window$end)

  export_graph_f <- add_section_slide(
    export_graph_f,
    "Seksjon: Run quality issues",
    paste0(
      "Per virus (H1/H3/BVIC), farge etter NC_quality. Datovindu: ",
      format(run_qc_window$start, "%Y-%m-%d"), " til ", format(run_qc_window$end, "%Y-%m-%d")
    )
  )
  run_qc_flu <- prepare_run_qc_df(
    fludb_run_qc,
    run_col = "ngs_run_id",
    cov_col = cov_col,
    qc_col = quality_col_flu,
    virus_col = "ngs_sekvens_resultat",
    color_col = quality_col_flu
  )

  if (!is.null(run_qc_flu) && nrow(run_qc_flu) > 0) {
    virus_map_qc <- c("A/H1N1" = "H1N1", "A/H3N2" = "H3N2", "B/Victoria" = "BVIC")
    for (virus_name in names(virus_map_qc)) {
      virus_label <- virus_map_qc[[virus_name]]
      rv <- run_qc_flu %>% filter(virus_group == virus_name)
      if (nrow(rv) == 0) next

      run_cov_summary_v <- run_qc_summary_table(rv)
      if (!is.null(run_cov_summary_v) && nrow(run_cov_summary_v) > 0) {
        export_graph_f <- save_table_to_ppt(export_graph_f, run_cov_summary_v, paste("Coverage QC by NGS run -", virus_label))
      }

      p_run_qc_v <- plot_run_qc_by_run_colorgroup(rv, paste("Run quality issues -", virus_label), color_label = "NC_quality")
      if (!is.null(p_run_qc_v)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_qc_v)

      p_run_cov_v <- plot_run_cov_by_run_colorgroup(rv, paste("Coverage per run -", virus_label), color_label = "NC_quality")
      if (!is.null(p_run_cov_v)) export_graph_f <- save_plot_to_ppt(export_graph_f, p_run_cov_v)
    }
  }
}

# CT values per subtype (one plot per slide, colored by subclade)
if (length(ct_columns) > 0) {
  subtype_order <- c("A/H1N1", "A/H3N2", "B/Victoria")
  subtype_short <- c("A/H1N1" = "H1", "A/H3N2" = "H3", "B/Victoria" = "BVIC")
  subtype_ct_column <- c("A/H1N1" = "pcr_h1_ct", "A/H3N2" = "pcr_h3_ct", "B/Victoria" = "pcr_bvic_ct")

  for (subtype_name in subtype_order) {
    subtype_ct_col <- subtype_ct_column[[subtype_name]]
    if (!(subtype_ct_col %in% names(fludb))) {
      subtype_ct_df <- tibble()
    } else {
      subtype_ct_df <- fludb %>%
        filter(ngs_sekvens_resultat == subtype_name) %>%
        mutate(
          ct_value = suppressWarnings(as.numeric(.data[[subtype_ct_col]])),
          month_date = parse_month_label(month_year),
          subclade_plot = ifelse(is.na(nc_ha_subclade) | nc_ha_subclade == "", "Ukjent", nc_ha_subclade)
        ) %>%
        filter(!is.na(ct_value), is.finite(ct_value), !is.na(month_date)) %>%
        select(month_date, subclade_plot, ct_value)
    }

    subtype_ct_df <- subtype_ct_df %>%
      group_by(month_date, subclade_plot) %>%
      mutate(month_total_n = n()) %>%
      ungroup()

    if (nrow(subtype_ct_df) == 0) {
      ct_month_plot <- ggplot() +
        annotate(
          "text",
          x = 0,
          y = 0,
          label = paste("Ingen CT-data tilgjengelig for", subtype_short[[subtype_name]]),
          size = 6
        ) +
        labs(
          title = paste("Ct-verdier per måned -", subtype_short[[subtype_name]]),
          subtitle = paste("Ct-kolonne:", subtype_ct_col),
          x = "Måned",
          y = "Ct-verdi"
        ) +
        theme_void()
    } else {
      ct_month_plot <- ggplot(
        subtype_ct_df,
        aes(
          x = month_date,
          y = ct_value,
          color = subclade_plot,
          group = interaction(month_date, subclade_plot)
        )
      ) +
        geom_boxplot(outlier.shape = NA, alpha = 0.35, position = position_dodge(width = 20)) +
        geom_jitter(alpha = 0.25, size = 0.9, width = 4) +
        scale_color_manual(values = kvalitativ_comb) +
        scale_x_date(labels = format_month_label, date_breaks = "1 month") +
        scale_y_continuous(limits = c(0, 40), breaks = seq(0, 40, 5), expand = c(0, 0)) +
        labs(
          title = paste("Ct-verdier per måned -", subtype_short[[subtype_name]]),
          subtitle = paste("Ct-kolonne:", subtype_ct_col),
          x = "Måned",
          y = "Ct-verdi",
          color = "Subklade"
        ) +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1))
    }

    if (nrow(subtype_ct_df) > 0) {
      ct_month_plot <- build_ct_month_plot(
        subtype_ct_df,
        date_col = "month_date",
        ct_col = "ct_value",
        color_col = "subclade_plot",
        title_txt = paste("Ct-verdier per måned -", subtype_short[[subtype_name]]),
        subtitle_txt = paste("Ct-kolonne:", subtype_ct_col),
        color_label = "Subklade"
      )
    }

    export_graph_f <- save_plot_to_ppt(
      export_graph_f,
      ct_month_plot,
      title = paste("Ct-verdier per måned -", subtype_short[[subtype_name]])
    )
  }
}

excel_export_sheets[["pasientmetadata_standard"]] <- patient_metadata_standard
excel_export_sheets[["data_completeness"]] <- data_completeness_tbl
excel_export_sheets[["data_issues"]] <- issues_tbl


# ==============================================================================
# Sample tables from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Prøvetabeller",
  "Sammendragstabeller beregnet direkte fra fludb"
)


# Calculate Sample category and pasient status tables
prove_cat <- fludb %>%
  filter(tessy_reportable_variable != "") %>%
  mutate(
    prove_kategori = ifelse(
      is.na(clean_project_code(prove_kategori)),
      "Ukjent",
      clean_project_code(prove_kategori)
    )
  ) %>%
  group_by(pasient_status, prove_kategori) %>%
  count(name = "n") %>%
  pivot_wider(names_from = prove_kategori, values_from = n)

export_graph_f <- save_table_to_ppt(
  export_graph_f,
  prove_cat,
  "Prøvekategori etter pasientstatus"
)

# Calculate and create the second flextable
sample_month_levels <- fludb %>%
  distinct(month_year) %>%
  mutate(month_date = parse_month_label(month_year)) %>%
  arrange(month_date) %>%
  pull(month_year)

prove_cat_m_long <- fludb %>%
  filter(tessy_reportable_variable != "") %>% # Ensure non-empty tessy_reportable_variable
  mutate(
    prove_kategori = prove_kategori_group,
    month_year = factor(month_year, levels = sample_month_levels)
  ) %>%
  group_by(pasient_status, prove_kategori, month_year) %>%
  count(name = "n")

prove_cat_m <- prove_cat_m_long %>%
  pivot_wider(names_from = month_year, values_from = n, values_fill = 0)

export_graph_f <- save_table_to_ppt(
  export_graph_f,
  prove_cat_m,
  "Prøvekategori per måned etter pasientstatus"
)


# Add a stacked percentage plot to complement the monthly table.
month_axis_label_nb <- intToUtf8(c(77, 229, 110, 101, 100))
prove_cat_m_plot_title <- paste0(
  "Pr",
  intToUtf8(248),
  "vekategori per m",
  intToUtf8(229),
  "ned etter pasientstatus"
)

prove_cat_m_plot <- prove_cat_m_long %>%
  mutate(month_year = parse_month_label(as.character(month_year))) %>%
  group_by(month_year, prove_kategori) %>%
  mutate(percentage = n / sum(n) * 100) %>%
  ungroup() %>%
  ggplot(aes(x = month_year, y = percentage, fill = pasient_status)) +
  geom_col(position = "fill") +
  facet_wrap(~prove_kategori) +
  scale_x_date(labels = format_month_label, date_breaks = "1 month") +
  scale_y_continuous(labels = percent_format(scale = 1), expand = c(0, 0)) +
  labs(
    title = prove_cat_m_plot_title,
    x = month_axis_label_nb,
    y = axis_share_label,
    fill = "Pasientstatus"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom"
  )

export_graph_f <- save_plot_to_ppt(export_graph_f, prove_cat_m_plot)

# Add heatmap companion for "Prøvekategori per måned etter pasientstatus".
prove_cat_m_heat <- prove_cat_m_long %>%
  mutate(month_date = parse_month_label(as.character(month_year))) %>%
  group_by(month_date, prove_kategori) %>%
  mutate(percentage = 100 * n / sum(n)) %>%
  ungroup() %>%
  ggplot(aes(x = month_date, y = pasient_status, fill = percentage)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = sprintf("%.0f", percentage)), size = 2.6, color = fhi_text_dark) +
  facet_wrap(~prove_kategori, scales = "free_y") +
  scale_fill_gradientn(
    colors = kvantitativ_b1,
    labels = scales::percent_format(scale = 1)
  ) +
  scale_x_date(labels = format_month_label, date_breaks = "1 month") +
  labs(
    title = "Prøvekategori per måned etter pasientstatus (varmekart)",
    x = month_axis_label_nb,
    y = "Pasientstatus",
    fill = "Andel (%)"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom"
  )

export_graph_f <- save_plot_to_ppt(
  export_graph_f,
  prove_cat_m_heat,
  title = "Prøvekategori per måned etter pasientstatus (heatmap)"
)

# ==============================================================================
# Influenza frequency dataset from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Influensafrekvens",
  "Frekvenstabeller og månedlige subtypeoppsummeringer"
)

# Keep only typed influenza results with usable WHO/ECDC reporting labels.

# Clade-level counts
frequency_clade_count <- reportable_subtype_fludb %>%
  group_by(
    month_year,
    ngs_sekvens_resultat,
    tessy_reportable_variable,
    nc_ha_clade,
    nc_ha_subclade
  ) %>%
  count(name = "n")

# Subtype-level totals
frequency_subtype_totals <- reportable_subtype_fludb %>%
  group_by(month_year, ngs_sekvens_resultat) %>%
  count(name = "n") %>%
  mutate(tessy_reportable_variable = ngs_sekvens_resultat)

# Pivot both
frequency_clade_pivot <- frequency_clade_count %>%
  pivot_wider(names_from = month_year, values_from = n, values_fill = 0)

frequency_subtype_pivot <- frequency_subtype_totals %>%
  pivot_wider(names_from = month_year, values_from = n, values_fill = 0)

# Specify the character type for clade and subclade columns in the subtype totals table.
frequency_subtype_pivot <- frequency_subtype_pivot %>%
  mutate(nc_ha_clade = as.character(NA), nc_ha_subclade = as.character(NA))

# Combine the data frames
frequency_table_df <- bind_rows(frequency_clade_pivot, frequency_subtype_pivot) %>%
  ungroup()


# Define the table order so subtotal rows stay above their related clades/subclades.
desired_order <- c(
  "A/H1N1",
  "genAH1/Hungary/286/2024",
  "genAH1/Lisboa/188/2023",
  "genAH1/Netherlands/10468/2023",
  "genAH1/Victoria/4897/2022",
  "genAH1/Missouri/11/2025",
  "genAH1NOClade",
  "genAH1SubgroupNotListed",
  "A/H3N2",
  "genAH3/Croatia/10136RV/2023",
  "genAH3/Lisboa/216/2023",
  "genAH3/Netherlands/10685/2024",
  "genAH3/Thailand/8/2022",
  "genAH3/Switzerland/59652/2024",
  "genAH3/Singapore/GP20238/2024",
  "genAH3/Norway/8765/2025",
  "genAH3/Victoria/211/2025",
  "genAH3NOClade",
  "genAH3SubgroupNotListed",
  "B/Victoria",
  "genBVicB/Austria/1359417/2021",
  "genBVicB/Catalonia/2279261NS/2023",
  "genBVicB/Greece/5509/2024",
  "genBVicB/Stockholm/3/2022",
  "genBVicB/Switzerland/329/2024",
  "genBVicB/Kanagawa/AC2414/2025",
  "genBVicB/ENG/120/2025",
  "genBVicNOClade",
  "genBVicSubgroupNotListed",
  "genBYam/Phuket/3073/2013",
  "genBYamNOClade",
  ""
)

# Detect month columns dynamically before sorting and computing totals.
month_cols <- names(frequency_table_df)[grep("^\\w{3}-\\d{4}$", names(frequency_table_df))]
# Check if all month_cols exist and are rightly formatted

# order the months
sorted_months <- month_cols[order(as.Date(
  paste0("01-", month_cols),
  format = "%d-%b-%Y"
))]

# Ensure that the sorted_months list has valid columns present in the frequency table.
sorted_months <- sorted_months[sorted_months %in% names(frequency_table_df)]

# Final formatting with checks
frequency_table_df <- frequency_table_df %>%
  mutate(
    tessy_reportable_variable = factor(
      tessy_reportable_variable,
      levels = desired_order
    )
  ) %>%
  arrange(tessy_reportable_variable) %>%
  rename(
    `WHO/ECDC kategori` = tessy_reportable_variable,
    Klade = nc_ha_clade,
    Subklade = nc_ha_subclade
  ) %>%
  mutate(Totalt = rowSums(across(all_of(sorted_months)), na.rm = TRUE)) %>%
  select(`WHO/ECDC kategori`, Klade, Subklade, all_of(sorted_months), Totalt)


# Get total rows by subtype
frequency_subtype_reference <- frequency_table_df %>%
  filter(`WHO/ECDC kategori` %in% c("A/H1N1", "A/H3N2", "B/Victoria")) %>%
  select(`WHO/ECDC kategori`, all_of(sorted_months))

# Map each WHO/ECDC category back to its subtype total for percentage calculations.
get_subtype <- function(name) {
  if (grepl("^genAH1", name)) {
    return("A/H1N1")
  }
  if (grepl("^genAH3", name)) {
    return("A/H3N2")
  }
  if (grepl("^genBVic", name)) {
    return("B/Victoria")
  }
  return(NA)
}
frequency_table_df <- frequency_table_df %>%
  mutate(across(all_of(sorted_months), as.character))


# Append monthly percentages for clade/subclade rows using subtype-level totals.
for (i in seq_len(nrow(frequency_table_df))) {
  subtype <- get_subtype(frequency_table_df$`WHO/ECDC kategori`[i])
  if (!is.na(subtype)) {
    for (month in sorted_months) {
      count <- as.numeric(frequency_table_df[i, month])

      # Check that total retrieval is correct
      total <- as.numeric(frequency_subtype_reference[
        frequency_subtype_reference$`WHO/ECDC kategori` == subtype,
        month
      ])
      if (!is.na(total) && total > 0) {
        pct <- round((count / total) * 100, 1)
        frequency_table_df[i, month] <- paste0(count, " (", pct, "%)")
      } else {
        frequency_table_df[i, month] <- paste0(count, " (0.0%)")
      }
    }
  }
}
# Handling NA replacements
frequency_table_df[is.na(frequency_table_df)] <- "-"

# Keep the full table for file export, but limit the PowerPoint version to the last 3 months.
recent_months <- tail(sorted_months, 3)
frequency_table_ppt_df <- frequency_table_df %>%
  select(`WHO/ECDC kategori`, Klade, Subklade, all_of(recent_months), Totalt)

# Create flextable
freqt_flextable <- flextable(frequency_table_ppt_df) %>%
  autofit()

# Save the table to PowerPoint
export_graph_f <- save_table_to_ppt(
  export_graph_f,
  frequency_table_ppt_df,
  "Frekvenstabell for WHO/ECDC-kategorier, klader og subklader"
)

# ==============================================================================
# Monthly subtype count charts from fludb-derived clade_count
# ==============================================================================

clade_count <- frequency_clade_count

# Ensure month_year is Date
clade_count$month_year <- as.Date(
  paste0("01-", clade_count$month_year),
  format = "%d-%b-%Y"
)

# Set locale to Norwegian Bokmål
Sys.setlocale("LC_TIME", "nb_NO.UTF-8")

# Filter from Feb 2022 onward
clade_filtered <- clade_count %>%
  filter(month_year >= as.Date("2022-02-01"))

# Duplicate overview plots removed in favor of the dedicated subtype section below.
unique_seq <- character(0)

# Loop and create combined graphs
for (seq_name in unique_seq) {
  # ----- CLADE PLOT -----

  df_clade <- clade_filtered %>%
    filter(ngs_sekvens_resultat == seq_name) %>%
    group_by(month_year, nc_ha_clade) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    group_by(month_year) %>%
    mutate(percent = n / sum(n) * 100) %>%
    ungroup()

  p_clade <- ggplot(
    df_clade,
    aes(x = month_year, y = percent, fill = nc_ha_clade)
  ) +
    geom_area() + # Change from geom_bar to geom_area for stacked area chart
    scale_fill_manual(values = kvalitativ_a, name = NULL) + # Remove legend title
    scale_x_date(
      date_breaks = "1 month",
      labels = format_month_label,
      expand = c(0, 0)
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 12), # Increase x-axis text size
      legend.title = element_blank() # Ensure no legend title
    ) +
    labs(title = "Klade", x = "", y = axis_share_label)

  # ----- SUBCLADE PLOT -----

  # Prepare the subclade data
  df_subclade <- clade_filtered %>%
    filter(ngs_sekvens_resultat == seq_name) %>%
    group_by(month_year, nc_ha_subclade) %>%
    summarise(n = sum(n), .groups = "drop") %>%
    group_by(month_year) %>%
    mutate(percent = n / sum(n) * 100) %>%
    ungroup()

  # Plotting
  p_subclade <- ggplot(
    df_subclade,
    aes(x = month_year, y = percent, fill = nc_ha_subclade)
  ) +
    geom_area(position = "fill") + # Use "fill" to normalize stacking
    scale_fill_manual(values = kvalitativ_a, name = NULL) + # Adjust color scale
    scale_x_date(
      date_breaks = "1 month",
      labels = format_month_label,
      expand = c(0, 0)
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 12),
      legend.title = element_blank()
    ) +
    labs(title = "Subklade", x = "", y = axis_share_label)

  # Display the plot

  # ----- COMBINE AND EXPORT -----

  combined_plot <- p_clade /
    p_subclade +
    plot_layout(heights = c(1, 1)) +
    plot_annotation(
      title = paste("Fordeling av klade og subklade per måned:", seq_name)
    )

  export_graph_f <- save_plot_to_ppt(export_graph_f, combined_plot)
}


# Remove all temporary data frames
rm(
  frequency_clade_count,
  frequency_subtype_totals,
  frequency_clade_pivot,
  frequency_subtype_pivot,
  frequency_subtype_reference
)


# ==============================================================================
# Clade and subclade plots from fludb-derived clade_subclade_fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Klade- og subkladeplott",
  "Sesongfordeling, månedsplott og arealdiagrammer per subtype"
)

create_grouped_df_with_percentage <- function(data, group_col) {
  # Calculate monthly counts and within-month percentages for a dynamic grouping column.
  grouped_df <- data %>%
    group_by(month_year) %>%
    mutate(total_monthly_count = n()) %>% # Total count per month
    group_by(month_year, !!sym(group_col)) %>%
    summarise(
      count = n(),
      total_monthly_count = first(total_monthly_count), # Retrieve total count for computation
      percentage = (count / total_monthly_count) * 100, # Calculate percentage
      .groups = "drop"
    ) %>%
    select(-total_monthly_count) # Optionally remove if you only want percentage information
  return(grouped_df)
}

# Ensure proper ordering of month_year
order_month_year <- function(data) {
  # Attempt conversion to date format, handling the first day of the month
  data$month_year <- paste0("01-", data$month_year)
  data$month_year <- as.Date(data$month_year, format = "%d-%b-%Y")

  # Check for conversion success and remove NAs
  if (any(is.na(data$month_year))) {
    stop("Date conversion failed. Check input format for consistency.")
  }

  # Sort factor levels based on the unique sorted dates
  data <- droplevels(data[!is.na(data$month_year), ])
  data$month_year <- factor(
    data$month_year,
    levels = sort(unique(data$month_year))
  )
  return(data)
}

# Prepare subtype-specific clade/subclade datasets.
df_h1n1 <- clade_subclade_fludb %>%
  filter(ngs_sekvens_resultat == "A/H1N1")

df_h3n2 <- clade_subclade_fludb %>%
  filter(ngs_sekvens_resultat == "A/H3N2")

df_bvic <- clade_subclade_fludb %>%
  filter(ngs_sekvens_resultat == "B/Victoria")

# ==============================================================================
# Clade and subclade season summaries from fludb-derived clade_subclade_fludb
# ==============================================================================

# Function to summarize by clade and subclade for each subtype
summarize_by_clade_subclade <- function(df) {
  clade_summary <- df %>%
    group_by(nc_ha_clade) %>%
    summarize(count = n(), .groups = "drop")

  subclade_summary <- df %>%
    group_by(nc_ha_subclade) %>%
    summarize(count = n(), .groups = "drop")

  return(list(
    clade_summary = clade_summary,
    subclade_summary = subclade_summary
  ))
}

# Summarize data
h1n1_summary <- summarize_by_clade_subclade(df_h1n1)
h3n2_summary <- summarize_by_clade_subclade(df_h3n2)
bvic_summary <- summarize_by_clade_subclade(df_bvic)

# Function to create pie charts for clade and subclade with custom colors
create_combined_pie_chart <- function(
  clade_summary,
  subclade_summary,
  type,
  palette
) {
  total_n <- sum(clade_summary$count, na.rm = TRUE)
  season_tag <- paste0("current season (n=", total_n, ")")
  clade_chart <- ggplot(
    clade_summary,
    aes(x = "", y = count, fill = nc_ha_clade)
  ) +
    geom_bar(stat = "identity", width = 1) +
    coord_polar(theta = "y") +
    scale_fill_manual(
      values = kvalitativ_comb,
      labels = paste0(clade_summary$nc_ha_clade, " (n=", clade_summary$count, ")")
    ) +
    labs(fill = "Klade") +
    theme_void() +
    ggtitle(paste(type, "Fordeling av klade -", season_tag))

  subclade_chart <- ggplot(
    subclade_summary,
    aes(x = "", y = count, fill = nc_ha_subclade)
  ) +
    geom_bar(stat = "identity", width = 1) +
    coord_polar(theta = "y") +
    scale_fill_manual(
      values = kvalitativ_comb,
      labels = paste0(subclade_summary$nc_ha_subclade, " (n=", subclade_summary$count, ")")
    ) +
    labs(fill = "Subklade") +
    theme_void() +
    ggtitle(paste(type, "Fordeling av subklade -", season_tag))

  # Combine the charts using patchwork
  combined_chart <- clade_chart / subclade_chart
  return(combined_chart)
}

# Create combined pie charts for each subtype using kvalitativ_a for colors
h1n1_combined_chart <- create_combined_pie_chart(
  h1n1_summary$clade_summary,
  h1n1_summary$subclade_summary,
  "A/H1N1",
  kvalitativ_a
)
h3n2_combined_chart <- create_combined_pie_chart(
  h3n2_summary$clade_summary,
  h3n2_summary$subclade_summary,
  "A/H3N2",
  kvalitativ_a
)
bvic_combined_chart <- create_combined_pie_chart(
  bvic_summary$clade_summary,
  bvic_summary$subclade_summary,
  "B/Victoria",
  kvalitativ_a
)


# Removed duplicate subtype pie slides; keep single canonical subtype sections later.

# ==============================================================================
# Monthly clade and subclade bar charts from fludb-derived clade_subclade_fludb
# ==============================================================================

df_h1n1_clade_percentage <- create_grouped_df_with_percentage(
  df_h1n1,
  "nc_ha_clade"
) %>%
  order_month_year()
df_h1n1_subclade_percentage <- create_grouped_df_with_percentage(
  df_h1n1,
  "nc_ha_subclade"
) %>%
  order_month_year()

df_h3n2_clade_percentage <- create_grouped_df_with_percentage(
  df_h3n2,
  "nc_ha_clade"
) %>%
  order_month_year()
df_h3n2_subclade_percentage <- create_grouped_df_with_percentage(
  df_h3n2,
  "nc_ha_subclade"
) %>%
  order_month_year()

df_bvic_clade_percentage <- create_grouped_df_with_percentage(
  df_bvic,
  "nc_ha_clade"
) %>%
  order_month_year()
df_bvic_subclade_percentage <- create_grouped_df_with_percentage(
  df_bvic,
  "nc_ha_subclade"
) %>%
  order_month_year()

# Function to create a bar chart for a given dataset and grouping column
create_bar_chart <- function(data, title, legend_title, remove_x_axis = FALSE) {
  p <- ggplot(
    data,
    aes(x = as.Date(as.character(month_year)), y = percentage, fill = Group)
  ) +
    geom_bar(stat = "identity", position = "stack") +
    labs(
      title = title,
      x = NULL,
      y = axis_share_label,
      fill = legend_title
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "bottom",
      legend.text = element_text(size = 10),
      axis.text.x = element_text(size = 12),
      axis.title.y = element_text(size = 14)
    ) +
    scale_x_date(
      labels = format_month_label,
      breaks = sort(unique(as.Date(as.character(data$month_year))))
    )

  if (remove_x_axis) {
    p <- p +
      theme(
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title.x = element_blank()
      )
  } else {
    p <- p + theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 12))
  }

  return(p)
}

# Combine clade and subclade data into a single dataframe
combine_clade_subclade <- function(
  clade_df,
  subclade_df,
  clade_col,
  subclade_col
) {
  clade_df <- clade_df %>%
    mutate(Type = "Klade", Group = !!sym(clade_col)) %>%
    select(month_year, percentage, Type, Group)

  subclade_df <- subclade_df %>%
    mutate(Type = "Subklade", Group = !!sym(subclade_col)) %>%
    select(month_year, percentage, Type, Group)

  combined_df <- bind_rows(clade_df, subclade_df)
  return(combined_df)
}

# Prepare combined dataframes
df_h1n1_combined <- combine_clade_subclade(
  df_h1n1_clade_percentage,
  df_h1n1_subclade_percentage,
  "nc_ha_clade",
  "nc_ha_subclade"
)
df_h3n2_combined <- combine_clade_subclade(
  df_h3n2_clade_percentage,
  df_h3n2_subclade_percentage,
  "nc_ha_clade",
  "nc_ha_subclade"
)
df_bvic_combined <- combine_clade_subclade(
  df_bvic_clade_percentage,
  df_bvic_subclade_percentage,
  "nc_ha_clade",
  "nc_ha_subclade"
)

# Create clade and subclade charts separately, then combine
create_combined_chart <- function(df_combined, type) {
  # Create clade chart with the specified palette
  clade_chart <- create_bar_chart(
    df_combined %>% filter(Type == "Klade"),
    paste(type, "fordeling av klade per måned:"),
    legend_title = "Klade",
    remove_x_axis = TRUE
  ) +
    scale_fill_manual(values = kvalitativ_a)

  # Create subclade chart with the specified palette
  subclade_chart <- create_bar_chart(
    df_combined %>% filter(Type == "Subklade"),
    paste(type, "fordeling av subklade per måned:"),
    legend_title = "Subklade"
  ) +
    scale_fill_manual(values = kvalitativ_b)
  # Combine the charts
  combined_chart <- clade_chart / subclade_chart
  return(combined_chart)
}

# Create combined charts
h1n1_combined_chart <- create_combined_chart(df_h1n1_combined, "A/H1N1")
h3n2_combined_chart <- create_combined_chart(df_h3n2_combined, "A/H3N2")
bvic_combined_chart <- create_combined_chart(df_bvic_combined, "B/Victoria")

export_graph_f <- save_plot_to_ppt(export_graph_f, h1n1_combined_chart)
export_graph_f <- save_plot_to_ppt(export_graph_f, h3n2_combined_chart)
export_graph_f <- save_plot_to_ppt(export_graph_f, bvic_combined_chart)


# ==============================================================================
# Monthly clade and subclade area charts from fludb-derived clade_subclade_fludb
# ==============================================================================

fill_missing_months <- function(data, group_col) {
  # Add missing month/group combinations so area charts do not drop empty periods.
  complete_data <- data %>%
    select(month_year, !!sym(group_col), percentage) %>%
    distinct() %>%
    tidyr::expand(month_year, !!sym(group_col)) %>%
    left_join(data, by = c("month_year", as.character(sym(group_col)))) %>%
    replace_na(list(percentage = 0)) # Fill missing percentages with 0

  return(complete_data)
}


# Apply function to fill missing months for clade and subclade percentages
df_h1n1_clade_filled <- fill_missing_months(df_h1n1_clade_percentage, "nc_ha_clade")
df_h1n1_subclade_filled <- fill_missing_months(df_h1n1_subclade_percentage, "nc_ha_subclade")


df_h3n2_clade_filled <- fill_missing_months(df_h3n2_clade_percentage, "nc_ha_clade")
df_h3n2_subclade_filled <- fill_missing_months(df_h3n2_subclade_percentage, "nc_ha_subclade")

df_bvic_clade_filled <- fill_missing_months(df_bvic_clade_percentage, "nc_ha_clade")
df_bvic_subclade_filled <- fill_missing_months(df_bvic_subclade_percentage, "nc_ha_subclade")

create_stacked_area_chart <- function(data, title, group_col, legend_title, palette) {
  # Reuse the same plotting logic for clade and subclade area charts.
  p <- ggplot(
    data,
    aes(
      x = as.Date(as.character(month_year)),
      y = percentage,
      fill = !!sym(group_col) # Reference actual column for mapping
    )
  ) +
    geom_area(position = "stack") +
    labs(
      title = title,
      x = NULL,
      y = axis_share_label, # Label for y axis
      fill = legend_title # Custom label for legend
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.position = "bottom",
      legend.text = element_text(size = 10),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 12),
      axis.title.y = element_text(size = 14)
    ) +
    scale_x_date(
      labels = format_month_label,
      breaks = sort(unique(as.Date(as.character(data$month_year))))
    ) +
    scale_fill_manual(values = palette)

  return(p)
}

# Call the function with the desired legend titles
create_combined_area_chart <- function(clade_data, subclade_data, type, clade_palette, subclade_palette) {
  # Stack the clade and subclade charts vertically for a subtype-specific summary.
  # Create clade area chart
  clade_area_chart <- create_stacked_area_chart(
    clade_data,
    paste(type, "Klade fordeling per måned:"),
    group_col = "nc_ha_clade", # Pass the actual column name
    legend_title = "Klade", # Set legend title as "Klade"
    palette = clade_palette
  )

  # Create subclade area chart
  subclade_area_chart <- create_stacked_area_chart(
    subclade_data,
    paste(type, "Subklade fordeling per måned:"),
    group_col = "nc_ha_subclade", # Pass the actual column name
    legend_title = "Subklade", # Set legend title as "Subklade"
    palette = subclade_palette
  )

  # Combine the area charts using patchwork
  combined_area_chart <- clade_area_chart / subclade_area_chart
  return(combined_area_chart)
}

# Create and display the charts using the updated function calls
h1n1_combined_area_chart <- create_combined_area_chart(
  df_h1n1_clade_filled,
  df_h1n1_subclade_filled,
  "A/H1N1",
  kvalitativ_a,
  kvalitativ_b
)
h3n2_combined_area_chart <- create_combined_area_chart(
  df_h3n2_clade_filled,
  df_h3n2_subclade_filled,
  "A/H3N2",
  kvalitativ_a,
  kvalitativ_b
)
bvic_combined_area_chart <- create_combined_area_chart(
  df_bvic_clade_filled,
  df_bvic_subclade_filled,
  "B/Victoria",
  kvalitativ_a,
  kvalitativ_b
)


export_graph_f <- save_plot_to_ppt(export_graph_f, h1n1_combined_area_chart)
export_graph_f <- save_plot_to_ppt(export_graph_f, h3n2_combined_area_chart)
export_graph_f <- save_plot_to_ppt(export_graph_f, bvic_combined_area_chart)

# ==============================================================================
# Drug resistance datasets from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Antiviral resistens",
  "Resistenstabeller og mutasjonsoppsummeringer"
)

# Grouping and counting combined mutations and resistance results
dr_Oesel_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_oseltamivir, dr_na_mut) %>%
  filter(
    !is.na(dr_na_mut) &
      dr_na_mut != "NA" &
      dr_na_mut != "No Mutations" &
      dr_na_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

dr_Peram_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_peramivir, dr_na_mut) %>%
  filter(
    !is.na(dr_na_mut) &
      dr_na_mut != "NA" &
      dr_na_mut != "No Mutations" &
      dr_na_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

dr_Zanam_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_zanamivir, dr_na_mut) %>%
  filter(
    !is.na(dr_na_mut) &
      dr_na_mut != "NA" &
      dr_na_mut != "No Mutations" &
      dr_na_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

dr_Lanin_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_laninamivir, dr_na_mut) %>%
  filter(
    !is.na(dr_na_mut) &
      dr_na_mut != "NA" &
      dr_na_mut != "No Mutations" &
      dr_na_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

dr_Balox_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_baloxavir, dr_pa_mut) %>%
  filter(
    !is.na(dr_pa_mut) &
      dr_pa_mut != "NA" &
      dr_pa_mut != "No Mutations" &
      dr_pa_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()

dr_Adama_i_mut <- fludb %>%
  group_by(ngs_sekvens_resultat, dr_res_adamantine, dr_m2_mut) %>%
  filter(
    !is.na(dr_m2_mut) &
      dr_m2_mut != "NA" &
      dr_m2_mut != "No Mutations" &
      dr_m2_mut != "" &
      ngs_sekvens_resultat != ""
  ) %>%
  count() %>%
  ungroup() %>%
  as.data.frame()


antiviral <- fludb %>%
  select(
    key,
    ngs_sekvens_resultat,
    prove_tatt,
    dr_res_adamantine,
    dr_res_baloxavir,
    dr_res_oseltamivir,
    dr_res_peramivir,
    dr_res_zanamivir,
    dr_res_laninamivir
  )


# Define a function to calculate resistance percentages, ignoring NA for the specific drug
calculate_resistance <- function(data, column_name) {
  non_na_data <- data %>% filter(!is.na(get(column_name)))
  total_resistance <- sum(non_na_data[[column_name]] %in% c("AAHRI", "AARI"))
  total_non_resistance <- sum(non_na_data[[column_name]] %in% c("AANS", "AANI"))
  total_tested <- total_resistance + total_non_resistance
  percentage_resistance <- ifelse(
    total_tested > 0,
    (total_resistance / total_tested) * 100,
    NA
  )
  return(list(
    total_resistance = total_resistance,
    total_tested = total_tested,
    percentage_resistance = percentage_resistance
  ))
}

# Initialize a list to store the results
results_list <- list()

# Loop over unique NGS subtypes
for (subtype in unique(antiviral$ngs_sekvens_resultat)) {
  # Filter data for current subtype
  data_subtype <- antiviral %>% filter(ngs_sekvens_resultat == subtype)

  # Calculate resistance for each drug
  res_adamantine <- calculate_resistance(data_subtype, "dr_res_adamantine")
  res_baloxavir <- calculate_resistance(data_subtype, "dr_res_baloxavir")
  res_oseltamivir <- calculate_resistance(data_subtype, "dr_res_oseltamivir")
  res_peramivir <- calculate_resistance(data_subtype, "dr_res_peramivir")
  res_zanamivir <- calculate_resistance(data_subtype, "dr_res_zanamivir")
  res_laninamivir <- calculate_resistance(data_subtype, "dr_res_laninamivir")

  # Format results
  format_result <- function(resistance) {
    if (!is.na(resistance$percentage_resistance)) {
      paste0(
        resistance$total_resistance,
        "/",
        resistance$total_tested,
        " (",
        round(resistance$percentage_resistance, 1),
        "%)"
      )
    } else {
      NA
    }
  }

  # Store formatted results in a data frame for the subtype
  results_list[[subtype]] <- data.frame(
    Influensa = subtype,
    Adamantine = format_result(res_adamantine),
    Baloxavir = format_result(res_baloxavir),
    Oseltamivir = format_result(res_oseltamivir),
    Peramivir = format_result(res_peramivir),
    Zanamivir = format_result(res_zanamivir),
    Laninamivir = format_result(res_laninamivir)
  )
}

# Combine results into a single data frame
result <- bind_rows(results_list)

# Define a list of data frames and their respective captions
table_data <- list(
  list(data = result, caption = "Tabell 1. Oppsummering av antiviral resistens"),
  list(
    data = dr_Oesel_i_mut,
    caption = "Tabell 2. Oseltamivir-resistens med NA-mutasjon"
  ),
  list(
    data = dr_Peram_i_mut,
    caption = "Tabell 3. Peramivir-resistens med NA-mutasjon"
  ),
  list(
    data = dr_Zanam_i_mut,
    caption = "Tabell 4. Zanamivir-resistens med NA-mutasjon"
  ),
  list(
    data = dr_Lanin_i_mut,
    caption = "Tabell 5. Laninamivir-resistens med NA-mutasjon"
  ),
  list(
    data = dr_Balox_i_mut,
    caption = "Tabell 6. Baloxavir-resistens"
  ),
  list(
    data = dr_Adama_i_mut,
    caption = "Tabell 7. Adamantan-resistens med M2-mutasjon"
  )
)

# Loop through each item in the list to generate and export tables
for (table_info in table_data) {
  # Save the original data frame to the PowerPoint presentation
  export_graph_f <- save_table_to_ppt(
    export_graph_f,
    table_info$data,
    table_info$caption
  )
}

# ==============================================================================
# Patient metadata summaries from fludb
# ==============================================================================

if (FALSE) {
export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Pasientmetadata",
  "Metadatafigurer og fordelinger beregnet fra fludb"
)

# Function to create a pie chart with counts
create_pie_chart <- function(
  data,
  fill_var,
  fill_label,
  presentation,
  layout = "Title and Content",
  master = "Office Theme"
) {
  # Create a vector of labels that include counts
  labels_with_counts <- paste(data[[fill_var]], "\nn=", data$count)

  pie_chart <- ggplot(data, aes(x = "", y = count, fill = .data[[fill_var]])) +
    geom_bar(stat = "identity", width = 1) + # Bar chart (needed for pie chart)
    coord_polar("y", start = 0) + # Convert to pie chart
    theme_void() + # Remove background and axis
    scale_fill_manual(values = kvalitativ_comb, labels = labels_with_counts) + # Color palette with labels
    labs(fill = fill_label) + # Label for legend
    theme(legend.position = "right") # Position legend on the right

  # Print the chart

  # Save to PowerPoint
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    pie_chart,
    layout,
    master,
    title = paste("Fordeling:", fill_label)
  )

  return(export_graph_f)
}


# Function to create a percentage stacked bar chart
create_percentage_stacked_bar_chart <- function(
  data,
  x_var,
  y_var,
  fill_var,
  fill_label,
  presentation,
  layout = "Title and Content",
  master = "Office Theme"
) {
  # Calculate percentages
  data <- data %>%
    group_by(.data[[x_var]]) %>%
    mutate(percent = .data[[y_var]] / sum(.data[[y_var]]) * 100)

  stacked_bar_chart <- ggplot(
    data,
    aes(x = .data[[x_var]], y = percent, fill = .data[[fill_var]])
  ) +
    geom_bar(stat = "identity", position = "fill") + # Percentage stacked bar chart
    labs(x = x_var, y = axis_share_label, fill = fill_label) + # Axis labels
    scale_fill_manual(values = kvalitativ_comb) + # Use the color palette
    theme_minimal() + # Minimal theme
    theme(legend.position = "right") + # Position legend on the right
    geom_text(
      aes(label = paste0(round(percent, 1), "%")),
      position = position_fill(vjust = 0.5),
      color = fhi_text_dark
    ) # Add text labels

  # Print the chart

  # Save to PowerPoint
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    stacked_bar_chart,
    layout,
    master,
    title = paste("Andeler:", x_var, "og", fill_label)
  )

  return(export_graph_f)
}


# Function to create a standard bar chart
create_standard_bar_chart <- function(
  data,
  x_var,
  y_var,
  fill_var,
  fill_label,
  presentation,
  layout = "Title and Content",
  master = "Office Theme"
) {
  # Create the bar chart using counts
  standard_bar_chart <- ggplot(
    data,
    aes(x = .data[[x_var]], y = .data[[y_var]], fill = .data[[fill_var]])
  ) +
    geom_bar(stat = "identity") + # Standard bar chart
    labs(x = x_var, y = axis_count_label, fill = fill_label) + # Axis labels
    scale_fill_manual(values = kvalitativ_comb) + # Use the color palette
    theme_minimal() + # Minimal theme
    theme(legend.position = "right") + # Position legend on the right
    geom_text(
      aes(label = .data[[y_var]]), # Add text labels with counts
      position = position_stack(vjust = 0.5),
      color = fhi_text_dark
    ) # Adjust label position

  # Print the chart

  # Save to PowerPoint
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    standard_bar_chart,
    layout,
    master,
    title = paste("Antall:", x_var, "og", fill_label)
  )

  return(export_graph_f)
}

create_andel_antall_combined_plot <- function(
  data,
  x_var,
  fill_var,
  count_var = "n",
  x_label = NULL,
  title_base = NULL
) {
  if (is.null(x_label)) x_label <- x_var
  if (is.null(title_base)) title_base <- x_var

  p_andel <- ggplot(data, aes(x = .data[[x_var]], y = .data[[count_var]], fill = .data[[fill_var]])) +
    geom_col(position = "fill") +
    scale_fill_manual(values = kvalitativ_comb) +
    scale_y_continuous(labels = percent_format(scale = 1), expand = c(0, 0)) +
    labs(title = NULL, x = NULL, y = axis_share_label, fill = fill_var) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right")

  p_antall <- ggplot(data, aes(x = .data[[x_var]], y = .data[[count_var]], fill = .data[[fill_var]])) +
    geom_col() +
    scale_fill_manual(values = kvalitativ_comb) +
    labs(title = NULL, x = NULL, y = axis_count_label, fill = fill_var) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "none")

  p_andel + p_antall +
    plot_layout(ncol = 1, heights = c(1, 1), guides = "collect") &
    theme(legend.position = "right")
}


# Create the summarized data for Prove Kategori
prove_kat <- fludb %>%
  filter(tessy_reportable_variable != "") %>%
  mutate(prove_kategori = prove_kategori_group) %>%
  group_by(prove_kategori) %>%
  summarise(count = n(), .groups = "drop") # Count samples for each category

# Create the pie chart for Prove Kategori
prove_kat_plot <- create_pie_chart(
  prove_kat,
  "prove_kategori",
  "Prove Kategori"
)

# Create the summarized data for Pasient Status
pasient_hosp <- fludb %>%
  filter(pasient_status != "") %>% # Remove empty pasient_status
  group_by(pasient_status) %>% # Group by pasient_status
  summarise(count = n(), .groups = "drop") # Count samples for each category


# Create the pie chart for Pasient Status
pasient_hospgr <- create_pie_chart(
  pasient_hosp,
  "pasient_status",
  "Pasient Status"
)

# Create the summarized data for Pasient Status and Prove Kategori
prove_kat_combined <- fludb %>%
  filter(pasient_status != "") %>% # Remove empty pasient_status
  mutate(
    prove_kategori = prove_kategori_group
  ) %>%
  group_by(pasient_status, prove_kategori) %>%
  count(name = "n") # Count samples for each combination

prove_kat_combined_plot <- create_andel_antall_combined_plot(
  prove_kat_combined,
  x_var = "pasient_status",
  fill_var = "prove_kategori",
  count_var = "n",
  x_label = "Pasientstatus",
  title_base = "Pasientstatus"
)
export_graph_f <- save_plot_to_ppt(export_graph_f, prove_kat_combined_plot, title = "Pasientstatus")

# Create the summarized data for Pasient Status and subclade by subtype
passtat_subclade <- fludb %>%
  filter(
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !is.na(nc_ha_subclade),
    nc_ha_subclade != ""
  ) %>%
  group_by(ngs_sekvens_resultat, pasient_status, nc_ha_subclade) %>%
  count(name = "n") %>%
  group_by(ngs_sekvens_resultat, pasient_status) %>%
  mutate(percent = n / sum(n) * 100) %>%
  ungroup()

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_passtat <- passtat_subclade %>% filter(ngs_sekvens_resultat == subtype_name)
  if (nrow(subtype_passtat) == 0) next

  combined_passtat_plot <- create_andel_antall_combined_plot(
    subtype_passtat,
    x_var = "pasient_status",
    fill_var = "nc_ha_subclade",
    count_var = "n",
    x_label = "Pasientstatus",
    title_base = "Pasientstatus"
  )
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    combined_passtat_plot,
    title = paste(subtype_name, "- Pasientstatus")
  )
}

# Create the summarized data for Pasient_aldersgruppe
pasage <- fludb %>%
  filter(tessy_reportable_variable != "") %>%
  group_by(pasient_aldersgruppe) %>% # Group by prove_kategori
  summarise(count = n(), .groups = "drop") # Count samples for each category

# Create the pie chart for Pasient_aldersgruppe
pas_age_plot <- create_pie_chart(
  pasage,
  "pasient_aldersgruppe",
  "Pasient aldersgruppe NGS"
)

# Create summarized data for Pasient Aldersgruppe and subclade by subtype
pasage_subclade <- fludb %>%
  filter(
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !is.na(nc_ha_subclade),
    nc_ha_subclade != ""
  ) %>%
  group_by(ngs_sekvens_resultat, pasient_aldersgruppe, nc_ha_subclade) %>%
  count(name = "n") %>%
  group_by(ngs_sekvens_resultat, pasient_aldersgruppe) %>%
  mutate(percent = n / sum(n) * 100) %>%
  ungroup()

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_pasage <- pasage_subclade %>% filter(ngs_sekvens_resultat == subtype_name)
  if (nrow(subtype_pasage) == 0) next

  combined_pasage_plot <- create_andel_antall_combined_plot(
    subtype_pasage,
    x_var = "pasient_aldersgruppe",
    fill_var = "nc_ha_subclade",
    count_var = "n",
    x_label = "Pasientaldersgruppe",
    title_base = "Pasientaldersgruppe"
  )
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    combined_pasage_plot,
    title = paste(subtype_name, "- Pasientaldersgruppe")
  )
}

# Create the summarized data for Pasient Landsdel
pasladel <- fludb %>%
  filter(tessy_reportable_variable != "") %>%
  group_by(pasient_landsdel) %>% # Group by prove_kategori
  summarise(count = n(), .groups = "drop") # Count samples for each category

# Create the pie chart for Pasient_aldersgruppe
pasladel_plot <- create_pie_chart(
  pasladel,
  "pasient_landsdel",
  "Pasient Landsdel NGS"
)

# Create summarized data for Pasient Landsdel and subclade by subtype
pasladel_subclade <- fludb %>%
  filter(
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !is.na(nc_ha_subclade),
    nc_ha_subclade != ""
  ) %>%
  group_by(ngs_sekvens_resultat, pasient_landsdel, nc_ha_subclade) %>%
  count(name = "n") %>%
  group_by(ngs_sekvens_resultat, pasient_landsdel) %>%
  mutate(percent = n / sum(n) * 100) %>%
  ungroup()

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_pasladel <- pasladel_subclade %>% filter(ngs_sekvens_resultat == subtype_name)
  if (nrow(subtype_pasladel) == 0) next

  combined_pasladel_plot <- create_andel_antall_combined_plot(
    subtype_pasladel,
    x_var = "pasient_landsdel",
    fill_var = "nc_ha_subclade",
    count_var = "n",
    x_label = "Landsdel",
    title_base = "Pasient landsdel"
  )
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    combined_pasladel_plot,
    title = paste(subtype_name, "- Pasient landsdel")
  )
}
}


# ==============================================================================
# HA mutation datasets from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: HA-mutasjoner",
  "Varmekart, epitopoppsummeringer og mutasjonstrender"
)

present_subclades_tbl <- fludb %>%
  filter(
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !is.na(nc_ha_subclade),
    nc_ha_subclade != ""
  ) %>%
  count(ngs_sekvens_resultat, nc_ha_subclade, name = "n") %>%
  left_join(
    ha_signature_map %>%
      select(ngs_sekvens_resultat, nc_ha_subclade, ha_cluster_defining_mutations),
    by = c("ngs_sekvens_resultat", "nc_ha_subclade")
  ) %>%
  mutate(
    ha_cluster_defining_mutations = ifelse(
      is.na(ha_cluster_defining_mutations) | ha_cluster_defining_mutations == "",
      "Ingen signaturmutasjoner funnet",
      ha_cluster_defining_mutations
    )
  ) %>%
  arrange(ngs_sekvens_resultat, nc_ha_subclade)

export_graph_f <- save_table_to_ppt(
  export_graph_f,
  present_subclades_tbl,
  "Subklader i datasettet og cluster-definerende HA-mutasjoner"
)

# Filter data for the last 12 months and format date
flu_mut_data <- fludb %>%
  filter(ngs_sekvens_resultat %in% c("A/H3N2")) %>%
  mutate(
    Sampledate = as.Date(prove_tatt),
    Substitution = gsub(";", ",", mut_ha1_cluster_defining),
    YearMonth = format_month_label(Sampledate)
  ) %>%
  select(Sampledate, mut_ha1_cluster_defining, ngs_sekvens_resultat, YearMonth)

spm_flu <- flu_mut_data %>%
  group_by(YearMonth, ngs_sekvens_resultat) %>%
  count(name = "TotalSeq") %>%
  ungroup()

mutations <- c("S145N", "N158K", "K189R")

# Create binary columns indicating mutation presence
for (mutation in mutations) {
  flu_mut_data[[mutation]] <- as.integer(str_detect(
    flu_mut_data$mut_ha1_cluster_defining,
    mutation
  ))
}

# Combine mutations into a single column
flu_mut_data <- flu_mut_data %>%
  mutate(
    Combination = apply(flu_mut_data[, mutations], 1, function(x) {
      paste(names(x)[x == 1], collapse = ",")
    })
  )

# Summarize occurrences of mutation combinations by month and flu type
counts <- flu_mut_data %>%
  group_by(YearMonth, ngs_sekvens_resultat, Combination) %>%
  summarise(Count = n(), .groups = "drop")

# Join with total sequences per month per flu type
counts <- counts %>%
  left_join(spm_flu, by = c("YearMonth", "ngs_sekvens_resultat")) %>%
  mutate(Percentage = (Count / TotalSeq) * 100) %>%
  select(YearMonth, ngs_sekvens_resultat, Combination, Percentage)

# Convert YearMonth to Date format and prepare heatmap data
countm <- counts %>%
  mutate(YearMonth = parse_month_label(YearMonth))

heatmap_data <- dcast(
  countm,
  YearMonth + ngs_sekvens_resultat ~ Combination,
  value.var = "Percentage",
  fill = 0
)

# Melt the data for plotting
heatmap_data_melted <- melt(
  heatmap_data,
  id.vars = c("YearMonth", "ngs_sekvens_resultat")
)

# Replace NA or empty mutation combinations with "ingen mutasjoner"
heatmap_data[is.na(heatmap_data)] <- 0 # Ensure missing values are treated as 0
heatmap_data <- heatmap_data %>%
  rename_with(~ replace(., . == "Var.3", "ingen mutasjoner"))

# Melt the data for plotting
heatmap_data_melted <- melt(
  heatmap_data,
  id.vars = c("YearMonth", "ngs_sekvens_resultat")
)

# Replace empty combination names with "ingen mutasjoner"
heatmap_data_melted$variable[
  heatmap_data_melted$variable == ""
] <- "ingen mutasjoner"

# Plot heatmap with text labels
hmap_flu <- ggplot(
  heatmap_data_melted,
  aes(x = YearMonth, y = variable, fill = value)
) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.1f", value)), size = 3, color = fhi_text_dark) + # Add numbers in tiles
  scale_fill_gradientn(colours = kvantitativ_b1) +
  scale_x_date(labels = format_month_label, date_breaks = "1 month") +
  facet_wrap(~ngs_sekvens_resultat, scales = "free_y") +
  labs(
    title = "",
    x = "",
    y = "",
    fill = "Prosentandel av all H3N2 sekvenser"
  ) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1))


# ==============================================================================
# Long-format HA mutation datasets from fludb
# ==============================================================================

HA_mut <- fludb %>%
  mutate(my = as.yearmon(prove_tatt, format = "%Y %b")) %>%
  mutate(
    ha_mutations = pmap_chr(
      list(nc_ha_deletion, nc_ha_insertion, nc_ha_frameshift, mut_ha1_1),
      ~ {
        vals <- c(...)
        vals <- vals[!is.na(vals)]
        vals <- vals[vals != ""] # Changed from "NA" to empty string check
        vals <- vals[!grepl("^No", vals)]
        paste(vals, collapse = ";")
      }
    )
  ) %>%
  mutate(ha_mutations = str_remove_all(ha_mutations, "HA1:")) %>%
  filter(ha_mutations != "") %>%
  mutate(ha_mutations = str_split(ha_mutations, ";|,", simplify = FALSE)) %>%
  unnest(ha_mutations) %>%
  mutate(ha_mutations = trimws(ha_mutations)) %>%
  filter(!str_detect(ha_mutations, "X")) %>% # <-- Remove rows where mutation contains "X"
  mutate(
    signature_token = vapply(ha_mutations, extract_mutation_key, character(1))
  ) %>%
  select(
    ha_mutations,
    signature_token,
    ngs_sekvens_resultat,
    prove_tatt,
    nc_ha_clade,
    nc_ha_subclade,
    key
  ) %>%
  filter(!is.na(ha_mutations)) %>% # Remove rows where ha_mutations is NA
  filter(ha_mutations != "NA") %>% # Remove rows where ha_mutations is the string "NA"
  left_join(
    ha_signature_lookup %>%
      select(ngs_sekvens_resultat, nc_ha_subclade, signature_token) %>%
      mutate(is_cluster_defining = TRUE),
    by = c("ngs_sekvens_resultat", "nc_ha_subclade", "signature_token")
  ) %>%
  filter(isTRUE(is_cluster_defining)) %>%
  mutate(cluster_defining_mutation = ha_mutations)


HA_mut_l <- HA_mut %>%
  mutate(Number = as.integer(gsub("\\D", "", ha_mutations))) %>%
  mutate(Sampledate = as.Date(prove_tatt, format = "%Y %b %d"))


HA_mut_vac <- fludb %>%
  mutate(my = as.yearmon(prove_tatt, format = "%Y %b")) %>%
  mutate(
    ha_mutations = pmap_chr(
      list(
        nc_ha_deletion,
        nc_ha_insertion,
        nc_ha_frameshift,
        mut_ha1_vac
      ),
      # Updated here
      ~ {
        vals <- c(...)
        vals <- vals[!is.na(vals)]
        vals <- vals[vals != ""]
        vals <- vals[!grepl("^No", vals)]
        paste(vals, collapse = ";")
      }
    )
  ) %>%
  mutate(ha_mutations = str_remove_all(ha_mutations, "HA1:")) %>%
  filter(ha_mutations != "") %>%
  mutate(ha_mutations = str_split(ha_mutations, ";|,", simplify = FALSE)) %>%
  unnest(ha_mutations) %>%
  mutate(ha_mutations = trimws(ha_mutations)) %>%
  filter(!str_detect(ha_mutations, "X")) %>%
  mutate(
    signature_token = vapply(ha_mutations, extract_mutation_key, character(1))
  ) %>%
  select(
    ha_mutations,
    signature_token,
    ngs_sekvens_resultat,
    prove_tatt,
    nc_ha_clade,
    nc_ha_subclade,
    key
  ) %>%
  filter(!is.na(ha_mutations)) %>%
  filter(ha_mutations != "NA") %>%
  left_join(
    ha_signature_lookup %>%
      select(ngs_sekvens_resultat, nc_ha_subclade, signature_token) %>%
      mutate(is_cluster_defining = TRUE),
    by = c("ngs_sekvens_resultat", "nc_ha_subclade", "signature_token")
  ) %>%
  filter(isTRUE(is_cluster_defining)) %>%
  mutate(cluster_defining_mutation = ha_mutations)

HA_mut_vac_l <- HA_mut_vac %>%
  mutate(Number = as.integer(gsub("\\D", "", ha_mutations))) %>%
  mutate(Sampledate = as.Date(prove_tatt, format = "%Y %b %d"))


# ==============================================================================
# HA epitope annotation and summaries from HA mutation datasets
# ==============================================================================

# Define the amino acid positions for H3N2 each epitope
epitope_A <- c(
  122,
  124,
  126,
  130,
  131,
  132,
  133,
  135,
  137,
  138,
  140,
  142,
  143,
  144,
  145,
  146,
  150,
  152,
  168
)
epitope_B <- c(
  128,
  129,
  155,
  156,
  157,
  158,
  159,
  160,
  163,
  165,
  186,
  187,
  188,
  189,
  190,
  192,
  193,
  194,
  196,
  197,
  198
)
epitope_C <- c(
  44,
  45,
  46,
  47,
  48,
  50,
  51,
  53,
  54,
  273,
  275,
  276,
  278,
  279,
  280,
  294,
  297,
  299,
  300,
  304,
  305,
  307,
  308,
  309,
  310,
  311,
  312
)
epitope_D <- c(
  96,
  102,
  103,
  117,
  121,
  167,
  170,
  171,
  172,
  173,
  174,
  175,
  176,
  177,
  179,
  182,
  201,
  203,
  207,
  208,
  209,
  212,
  213,
  214,
  215,
  216,
  217,
  218,
  219,
  226,
  227,
  228,
  229,
  230,
  238,
  240,
  242,
  244,
  246,
  247,
  248
)
epitope_E <- c(
  57,
  59,
  62,
  63,
  67,
  75,
  78,
  80,
  81,
  82,
  83,
  86,
  87,
  88,
  91,
  92,
  94,
  109,
  260,
  261,
  262,
  265
)

# Define the amino acid positions for H1N1 each epitope (https://bmcbioinformatics.biomedcentral.com/articles/10.1186/s12859-018-2042-4)
epitope_Sa <- c(141, 142, 170, 171, 172, 173, 174, 176, 177, 178, 179, 180, 181)
epitope_Sb <- c(201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212)
epitope_Ca1 <- c(183, 184, 185, 186, 187, 220, 221, 222, 252, 253, 254)
epitope_Ca2 <- c(154, 155, 156, 157, 158, 159, 238, 239)
epitope_Cb <- c(87, 88, 89, 90, 91, 92)

# Define the amino acid positions for B/VIC each epitope (https://www.sciencedirect.com/science/article/pii/S0042682216303968)
epitope_120_loop <- c(
  48,
  56,
  75,
  116,
  117,
  118,
  119,
  120,
  121,
  122,
  123,
  124,
  125,
  126,
  127,
  128,
  129,
  130,
  131,
  132,
  133,
  134,
  135,
  136,
  137,
  177,
  179,
  180,
  181
)
epitope_150_loop <- c(141, 142, 143, 144, 145, 146, 147, 148, 149, 150)
epitope_160_loop <- c(162, 163, 164, 165, 166, 167)
epitope_190_helix <- c(194, 195, 196, 197, 198, 199, 200, 201, 202)


# Create a new column for Epitope
HA_mut_l$Epitope <- NA # Initialize the column with NA values
HA_mut_vac_l$Epitope <- NA

# Define a helper function to assign epitopes
assign_epitope <- function(dataset) {
  dataset$Epitope <- ifelse(
    dataset$ngs_sekvens_resultat == "A/H3N2",
    ifelse(
      dataset$Number %in% epitope_A,
      "A",
      ifelse(
        dataset$Number %in% epitope_B,
        "B",
        ifelse(
          dataset$Number %in% epitope_C,
          "C",
          ifelse(
            dataset$Number %in% epitope_D,
            "D",
            ifelse(dataset$Number %in% epitope_E, "E", NA)
          )
        )
      )
    ),
    ifelse(
      dataset$ngs_sekvens_resultat == "A/H1N1",
      ifelse(
        dataset$Number %in% epitope_Sa,
        "Sa",
        ifelse(
          dataset$Number %in% epitope_Sb,
          "Sb",
          ifelse(
            dataset$Number %in% epitope_Ca1,
            "Ca1",
            ifelse(
              dataset$Number %in% epitope_Ca2,
              "Ca2",
              ifelse(dataset$Number %in% epitope_Cb, "Cb", NA)
            )
          )
        )
      ),
      ifelse(
        dataset$ngs_sekvens_resultat == "B/Victoria",
        ifelse(
          dataset$Number %in% epitope_120_loop,
          "120_loop",
          ifelse(
            dataset$Number %in% epitope_150_loop,
            "150_loop",
            ifelse(
              dataset$Number %in% epitope_160_loop,
              "160_loop",
              ifelse(dataset$Number %in% epitope_190_helix, "190_helix", NA)
            )
          )
        ),
        NA
      )
    )
  )
  return(dataset)
}

# Assign epitopes to both datasets
HA_mut_l <- assign_epitope(HA_mut_l)
HA_mut_vac_l <- assign_epitope(HA_mut_vac_l)


# Process HA mutations data
HA_mut_vac_sum <- HA_mut_vac_l %>%
  group_by(
    key,
    ngs_sekvens_resultat,
    nc_ha_clade,
    nc_ha_subclade,
    prove_tatt
  ) %>%
  summarize(
    unique_mutations = n_distinct(ha_mutations),
    mutations_with_epitope = sum(!is.na(Epitope)),
    .groups = "drop" # Ensure grouping is dropped after summarize
  ) %>%
  mutate(
    month_year = format_month_label(ymd(prove_tatt)),
    ngs_sekvens_resultat = factor(
      ngs_sekvens_resultat,
      levels = c("A/H1N1", "A/H3N2", "B/Victoria")
    )
  )

# Calculate statistics and format them
safe_stat_min <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return(NA_real_)
  }
  min(x)
}

safe_stat_max <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0) {
    return(NA_real_)
  }
  max(x)
}

result <- HA_mut_vac_sum %>%
  group_by(month_year, nc_ha_clade, nc_ha_subclade, ngs_sekvens_resultat) %>%
  summarize(
    unique_mutations_stat = paste(
      "Avg:",
      round(mean(unique_mutations), 2),
      "(Min:",
      safe_stat_min(unique_mutations),
      "| Max:",
      safe_stat_max(unique_mutations),
      ")"
    ),
    mutations_with_epitope_stat = paste(
      "Avg:",
      round(mean(mutations_with_epitope), 2),
      "(Min:",
      safe_stat_min(mutations_with_epitope),
      "| Max:",
      safe_stat_max(mutations_with_epitope),
      ")"
    ),
    .groups = "drop"
  ) %>%
  arrange(ngs_sekvens_resultat)

# Reshape data to have separate columns for unique and epitope mutations
combined_data <- result %>%
  pivot_wider(
    names_from = month_year,
    values_from = c(unique_mutations_stat, mutations_with_epitope_stat),
    names_glue = "{month_year}_{.value}"
  ) %>%
  select(ngs_sekvens_resultat, nc_ha_clade, nc_ha_subclade, everything())

# Create header details for flextable
header_keys <- names(combined_data)
get_month_year <- function(col_names) {
  unique(sub(
    "(_unique_mutations_stat|_mutations_with_epitope_stat)$",
    "",
    col_names
  ))
}
month_years <- get_month_year(header_keys[
  !header_keys %in% head(header_keys, 3)
])
mutation_types <- c("unique_mutations_stat", "mutations_with_epitope_stat")
all_ordered_mutations <- unlist(lapply(month_years, function(month) {
  paste0(month, "_", mutation_types)
}))
ordered_cols <- c(
  "ngs_sekvens_resultat",
  "nc_ha_clade",
  "nc_ha_subclade",
  all_ordered_mutations
)
combined_data <- combined_data %>%
  select(all_of(ordered_cols))

# Construct the header dataframe
header_df <- data.frame(
  col_keys = ordered_cols,
  month_year = c(rep("", 3), rep(month_years, each = 2)),
  mutations_type = c(
    rep("", 3),
    rep(
      c("Unike mutasjoner", "Epitopmutasjoner"),
      length(month_years)
    )
  ),
  stringsAsFactors = FALSE
)

# Define borders for table headers
separating_border <- fp_border(color = fhi_text_dark, width = 1)

# Build the flextable with reordered columns
combined_flextable <- flextable(combined_data) %>%
  set_header_df(mapping = header_df, key = "col_keys") %>%
  merge_h(part = "header")

summary_stat_cols <- if (ncol(combined_data) > 3) 4:ncol(combined_data) else integer(0)
if (length(summary_stat_cols) > 0) {
  combined_flextable <- combined_flextable %>%
    align(j = summary_stat_cols, align = "center", part = "header") %>%
    border(
      j = summary_stat_cols,
      part = "header",
      border.left = separating_border
    )
}

combined_flextable <- combined_flextable %>%
  merge_v(j = c("ngs_sekvens_resultat", "nc_ha_clade", "nc_ha_subclade"))

unique_mut_cols <- grep("_unique_mutations_stat$", ordered_cols)
if (length(unique_mut_cols) > 0) {
  combined_flextable <- combined_flextable %>%
    color(
      j = unique_mut_cols,
      part = "body",
      color = fhi_text_dark
    )
}

epitope_mut_cols <- grep("_mutations_with_epitope_stat$", ordered_cols)
if (length(epitope_mut_cols) > 0) {
  combined_flextable <- combined_flextable %>%
    color(
      j = epitope_mut_cols,
      part = "body",
      color = fhi_text_mid
    )
}

combined_flextable <- combined_flextable %>%
  theme_vanilla() %>%
  autofit()

# Prepare a slide with the flextable
export_graph_f <- add_slide(
  export_graph_f,
  layout = "Title and Content",
  master = "Office Theme"
)
export_graph_f <- ph_with(
  export_graph_f,
  value = combined_flextable,
  location = ph_location_type(type = "body")
)
export_graph_f <- ph_with(
  export_graph_f,
  value = "Oppsummering av HA-mutasjoner og epitopmutasjoner",
  location = ph_location_type(type = "title")
)

# Process HA mutation trends from fludb
ha_mutation_trend_source <- fludb %>%
  transmute(
    key,
    subtype = ngs_sekvens_resultat,
    subclade = nc_ha_subclade,
    mutation_profile = mut_ha1_without_subclade_signature,
    sample_date = as.Date(prove_tatt)
  ) %>%
  filter(
    subtype %in% c("A/H1N1", "A/H3N2", "B/Victoria"),
    !is.na(sample_date),
    !is.na(subclade),
    subclade != "",
    !is.na(mutation_profile),
    mutation_profile != "NA"
  ) %>%
  distinct(key, .keep_all = TRUE) %>%
  mutate(
    month_date = floor_date(sample_date, unit = "month"),
    month_label = format_month_label(month_date),
    mutation_profile = str_squish(mutation_profile),
    mutation_profile = vapply(
      strsplit(mutation_profile, ";", fixed = TRUE),
      function(tokens) {
        tokens <- trimws(tokens)
        tokens <- tokens[tokens != ""]
        if (length(tokens) == 0) {
          ""
        } else {
          paste(sort(unique(tokens)), collapse = ";")
        }
      },
      character(1)
    ),
    mutation_profile = ifelse(
      is.na(mutation_profile) | mutation_profile == "",
      subclade,
      paste0(subclade, " + ", mutation_profile)
    )
  )

ha_mutation_subtype_order <- c("A/H1N1", "A/H3N2", "B/Victoria")
last_four_month_start <- floor_date(Sys.Date(), unit = "month") %m-% months(3)

for (current_subtype in ha_mutation_subtype_order) {
  subtype_trend_source <- ha_mutation_trend_source %>%
    filter(subtype == current_subtype)

  if (nrow(subtype_trend_source) == 0) {
    next
  }

  subtype_month_totals <- fludb %>%
    transmute(
      key,
      subtype = ngs_sekvens_resultat,
      sample_date = as.Date(prove_tatt)
    ) %>%
    filter(subtype == current_subtype, !is.na(sample_date)) %>%
    distinct(key, .keep_all = TRUE) %>%
    mutate(
      month_date = floor_date(sample_date, unit = "month"),
      month_label = format_month_label(month_date)
    ) %>%
    group_by(month_date, month_label) %>%
    summarise(total_subtype = dplyr::n(), .groups = "drop") %>%
    arrange(month_date)

  all_subtype_months <- subtype_month_totals$month_date
  all_subtype_month_labels <- subtype_month_totals$month_label
  recent_subtype_month_labels <- subtype_month_totals %>%
    filter(month_date >= last_four_month_start) %>%
    pull(month_label)

  subtype_trend_counts <- subtype_trend_source %>%
    count(subclade, mutation_profile, month_date, month_label, name = "count") %>%
    left_join(
      subtype_month_totals,
      by = c("month_date", "month_label")
    ) %>%
    mutate(
      total_subtype = tidyr::replace_na(total_subtype, 0L),
      percent_of_subtype = if_else(total_subtype > 0, 100 * count / total_subtype, 0)
    )

  subtype_profile_filter <- subtype_trend_counts %>%
    group_by(subclade, mutation_profile) %>%
    summarise(
      recent_four_month_count = sum(
        if_else(month_date >= last_four_month_start, count, 0L),
        na.rm = TRUE
      ),
      total_count = sum(count, na.rm = TRUE),
      .groups = "drop"
    )

  subtype_trend_filtered <- subtype_trend_counts %>%
    inner_join(
      subtype_profile_filter,
      by = c("subclade", "mutation_profile")
    )

  if (nrow(subtype_trend_filtered) == 0) {
    next
  }

  subclade_levels <- subtype_trend_filtered %>%
    distinct(subclade) %>%
    arrange(subclade) %>%
    pull(subclade)

  for (subclade_index in seq_along(subclade_levels)) {
    current_subclade <- subclade_levels[[subclade_index]]

    subclade_totals <- subtype_profile_filter %>%
      filter(subclade == current_subclade) %>%
      arrange(desc(total_count), desc(recent_four_month_count), mutation_profile)

    subclade_counts <- subtype_trend_filtered %>%
      filter(subclade == current_subclade) %>%
      select(
        -total_subtype,
        -percent_of_subtype,
        -recent_four_month_count,
        -total_count
      )

    subclade_long <- subclade_counts %>%
      complete(
        mutation_profile,
        month_date = all_subtype_months,
        fill = list(count = 0)
      ) %>%
      left_join(
        subtype_month_totals,
        by = "month_date",
        relationship = "many-to-one"
      ) %>%
      mutate(
        month_label = coalesce(month_label.x, month_label.y),
        subtype = current_subtype,
        subclade = current_subclade,
        total_subtype = tidyr::replace_na(total_subtype, 0L),
        percent_of_subtype = if_else(total_subtype > 0, 100 * count / total_subtype, 0)
      ) %>%
      left_join(
        subclade_totals %>%
          select(mutation_profile, recent_four_month_count, total_count),
        by = "mutation_profile",
        relationship = "many-to-one"
      ) %>%
      mutate(month_label = factor(month_label, levels = all_subtype_month_labels)) %>%
      select(
        subtype,
        subclade,
        mutation_profile,
        month_date,
        month_label,
        count,
        total_subtype,
        percent_of_subtype,
        recent_four_month_count,
        total_count
      )

    subclade_full_table <- subclade_long %>%
      arrange(month_date, mutation_profile) %>%
      mutate(month_label = as.character(month_label)) %>%
      select(mutation_profile, month_label, count) %>%
      pivot_wider(
        names_from = month_label,
        values_from = count,
        values_fill = 0
      ) %>%
      left_join(
        subclade_totals %>%
          select(mutation_profile, recent_four_month_count, total_count),
        by = "mutation_profile"
      ) %>%
      relocate(recent_four_month_count, total_count, .after = mutation_profile) %>%
      rename(
        Mutasjonsprofil = mutation_profile,
        `Siste 4 mnd` = recent_four_month_count,
        Totalt = total_count
      )

    subclade_ppt_table <- subclade_long %>%
      filter(month_date >= last_four_month_start) %>%
      arrange(month_date, mutation_profile) %>%
      mutate(month_label = as.character(month_label)) %>%
      select(mutation_profile, month_label, count) %>%
      pivot_wider(
        names_from = month_label,
        values_from = count,
        values_fill = 0
      ) %>%
      left_join(
        subclade_totals %>%
          select(mutation_profile, total_count),
        by = "mutation_profile"
      ) %>%
      select(mutation_profile, any_of(recent_subtype_month_labels), total_count) %>%
      arrange(desc(total_count), mutation_profile) %>%
      rename(
        Mutasjonsprofil = mutation_profile,
        Totalt = total_count
      )

    subclade_heatmap_data <- subclade_long %>%
      mutate(month_label = factor(month_label, levels = rev(all_subtype_month_labels))) %>%
      arrange(month_date, mutation_profile) %>%
      select(
        Måned = month_label,
        Mutasjonsprofil = mutation_profile,
        Antall = count,
        Totalt_subtype = total_subtype,
        Prosent_av_subtype = percent_of_subtype
      )

    subclade_line_data <- subclade_long %>%
      arrange(month_date, mutation_profile) %>%
      transmute(
        Måned = as.character(month_label),
        Dato = month_date,
        Mutasjonsprofil = mutation_profile,
        Antall = count,
        Totalt_subtype = total_subtype,
        Prosent_av_subtype = percent_of_subtype
      )

    subtype_sheet_stub <- case_when(
      current_subtype == "A/H1N1" ~ "H1",
      current_subtype == "A/H3N2" ~ "H3",
      current_subtype == "B/Victoria" ~ "BVic",
      TRUE ~ "subtype"
    )
    sheet_stub <- sanitize_excel_sheet_name(
      paste0(subtype_sheet_stub, "_", subclade_index, "_", current_subclade),
      max_length = 20
    )
    excel_export_sheets[[paste0(sheet_stub, "_tabell")]] <- subclade_full_table
    excel_export_sheets[[paste0(sheet_stub, "_heatmap")]] <- subclade_heatmap_data
    excel_export_sheets[[paste0(sheet_stub, "_linje")]] <- subclade_line_data

    export_graph_f <- save_table_to_ppt(
      export_graph_f,
      subclade_ppt_table,
      paste("HA-mutasjonstrender -", current_subtype, "-", current_subclade)
    )

    # Remove overly common/stable mutation profiles to declutter heatmap.
    common_profile_stats <- subclade_long %>%
      group_by(mutation_profile) %>%
      summarise(
        overall_mean_pct = mean(percent_of_subtype, na.rm = TRUE),
        variability = max(percent_of_subtype, na.rm = TRUE) - min(percent_of_subtype, na.rm = TRUE),
        .groups = "drop"
      )
    keep_profiles <- common_profile_stats %>%
      filter(!(overall_mean_pct > 60 & variability < 10)) %>%
      pull(mutation_profile)
    filtered_subclade_long <- subclade_long %>%
      filter(mutation_profile %in% keep_profiles)
    if (nrow(filtered_subclade_long) == 0) {
      filtered_subclade_long <- subclade_long
    }
    profile_count <- filtered_subclade_long %>%
      distinct(mutation_profile) %>%
      nrow()
    y_label_size <- dplyr::case_when(
      profile_count <= 15 ~ 8,
      profile_count <= 30 ~ 7,
      profile_count <= 50 ~ 6,
      profile_count <= 80 ~ 5,
      TRUE ~ 4
    )

    subclade_heatmap_plot <- ggplot(
      filtered_subclade_long %>%
        mutate(month_label = factor(month_label, levels = all_subtype_month_labels)),
      aes(x = month_label, y = mutation_profile, fill = percent_of_subtype)
    ) +
      geom_tile(color = NA) +
      scale_fill_gradientn(
        colours = kvantitativ_b1,
        labels = percent_format(scale = 1)
      ) +
      labs(
        title = paste("HA-mutasjonstrender varmekart -", current_subtype, "-", current_subclade),
        x = "Måned",
        y = "Mutasjonsprofil",
        fill = paste("Andel av alle", current_subtype, "(%)")
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        axis.text.y = element_text(size = y_label_size)
      )

    export_graph_f <- save_plot_to_ppt(
      export_graph_f,
      subclade_heatmap_plot,
      title = paste("HA-mutasjonstrender varmekart -", current_subtype, "-", current_subclade)
    )

    subclade_line_plot <- ggplot(
      filtered_subclade_long,
      aes(
        x = month_date,
        y = percent_of_subtype / 100,
        group = mutation_profile,
        colour = mutation_profile
      )
    ) +
      geom_line(linewidth = 1) +
      scale_x_date(
        date_breaks = "1 month",
        labels = format_month_label,
        expand = c(0, 0)
      ) +
      scale_y_continuous(
        labels = scales::percent_format(accuracy = 1),
        expand = c(0, 0)
      ) +
      labs(
        title = paste("HA-mutasjonstrender linjer -", current_subtype, "-", current_subclade),
        x = "Måned",
        y = paste("Andel av alle", current_subtype)
      ) +
      theme_classic() +
      theme(
        axis.text.x = element_text(angle = 90, hjust = 0.5, vjust = 0.5),
        legend.position = "none"
      ) +
      scale_colour_manual(
        values = setNames(
          fhi_discrete_palette(
            dplyr::n_distinct(subclade_long$mutation_profile),
            kvalitativ_comb
          ),
          sort(unique(subclade_long$mutation_profile))
        )
      ) +
      geom_text_repel(
        data = filtered_subclade_long %>%
          group_by(mutation_profile) %>%
          filter(month_date == max(month_date), percent_of_subtype > 0) %>%
          ungroup(),
        aes(
          label = sprintf(
            "%s %s",
            scales::percent(percent_of_subtype / 100, accuracy = 1),
            mutation_profile
          )
        ),
        direction = "y",
        force = 3,
        nudge_x = 70,
        na.rm = TRUE,
        segment.size = 0.2,
        segment.linetype = 2,
        min.segment.length = 0,
        box.padding = 0.5,
        max.overlaps = Inf,
        show.legend = FALSE
      )

    export_graph_f <- save_plot_to_ppt(
      export_graph_f,
      subclade_line_plot,
      title = paste("HA-mutasjonstrender linjer -", current_subtype, "-", current_subclade)
    )
  }
}


# ==============================================================================
# Recent HA mutation plots from HA_mut_l
# ==============================================================================
start_date <- (as.Date(Sys.Date()) - 60)
end_date <- as.Date(Sys.Date())

# Build default epitope-plot source from mut_ha1_1 with subclade-defining
# mutations removed (mut_ha1_without_subclade_signature).
HA_mut_l_fallback <- fludb %>%
  mutate(
    ha_mutations = as.character(mut_ha1_without_subclade_signature)
  ) %>%
  filter(ha_mutations != "") %>%
  mutate(ha_mutations = str_split(ha_mutations, ";|,", simplify = FALSE)) %>%
  unnest(ha_mutations) %>%
  mutate(
    ha_mutations = trimws(ha_mutations),
    Number = as.integer(gsub("\\D", "", ha_mutations)),
    Sampledate = as.Date(prove_tatt, format = "%Y %b %d")
  ) %>%
  filter(!str_detect(ha_mutations, "X"), !is.na(ha_mutations), ha_mutations != "NA")

ha_lollipop_source <- assign_epitope(HA_mut_l_fallback)

domainmutcp_base <- ha_lollipop_source %>%
  mutate(Sampledate = as.Date(Sampledate)) %>%
  filter(!is.na(Sampledate)) %>%
  group_by(
    Sampledate,
    ha_mutations,
    ngs_sekvens_resultat,
    nc_ha_clade,
    nc_ha_subclade,
    Number,
    Epitope
  ) %>%
  summarise(n = n(), .groups = "drop")

build_subtype_lollipop_data <- function(subtype_name) {
  subtype_df <- domainmutcp_base %>%
    filter(ngs_sekvens_resultat == subtype_name)

  if (nrow(subtype_df) == 0) {
    return(list(
      data = subtype_df,
      window_label = "Ingen data tilgjengelig"
    ))
  }

  candidate_60 <- subtype_df %>%
    filter(Sampledate >= (as.Date(Sys.Date()) - 60))
  candidate_180 <- subtype_df %>%
    filter(Sampledate >= (as.Date(Sys.Date()) - 180))

  if (nrow(candidate_60) > 0) {
    use_df <- candidate_60
    window_label <- paste(as.Date(Sys.Date()) - 60, "til", as.Date(Sys.Date()))
  } else if (nrow(candidate_180) > 0) {
    use_df <- candidate_180
    window_label <- paste(as.Date(Sys.Date()) - 180, "til", as.Date(Sys.Date()), "(fallback)")
  } else {
    use_df <- subtype_df
    window_label <- paste(min(subtype_df$Sampledate), "til", max(subtype_df$Sampledate), "(all tilgjengelig data)")
  }

  agg_df <- use_df %>%
    group_by(
      ha_mutations,
      ngs_sekvens_resultat,
      nc_ha_clade,
      nc_ha_subclade,
      Number,
      Epitope
    ) %>%
    summarise(n = sum(n), .groups = "drop")

  list(
    data = agg_df,
    window_label = window_label
  )
}


# ==============================================================================
# Domain mutation plots by subtype
# ==============================================================================
create_epitope_lollipop_plot <- function(df, subtype_label, subtitle_label, facet_by_subclade = TRUE) {
  if (nrow(df) == 0) {
    return(
      ggplot() +
        annotate("text", x = 0, y = 0, label = paste("Ingen HA-epitope-data for", subtype_label), size = 6) +
        labs(
          title = paste("Lollipop: epitop-posisjoner i HA-proteinet (", subtype_label, ")", sep = ""),
          subtitle = subtitle_label,
          x = "AA-posisjon (HA)",
          y = "Antall sekvenser (n)"
        ) +
        theme_void()
    )
  }

  df_plot <- df %>%
    mutate(
      mutation_label = ifelse(is.na(ha_mutations) | ha_mutations == "", as.character(Number), ha_mutations),
      epitope_label = ifelse(is.na(Epitope) | Epitope == "", "Ukjent", Epitope),
      subclade_label = ifelse(is.na(nc_ha_subclade) | nc_ha_subclade == "", "Ukjent", nc_ha_subclade)
    ) %>%
    filter(!is.na(Number), !is.na(n), is.finite(Number), is.finite(n), n > 0) %>%
    arrange(desc(n), Number)

  if (nrow(df_plot) == 0) {
    return(
      ggplot() +
        annotate("text", x = 0, y = 0, label = paste("Ingen plottbare HA-epitope-data for", subtype_label), size = 6) +
        labs(
          title = paste("Lollipop: epitop-posisjoner i HA-proteinet (", subtype_label, ")", sep = ""),
          subtitle = subtitle_label,
          x = "AA-posisjon (HA)",
          y = "Antall sekvenser (n)"
        ) +
        theme_void()
    )
  }

  # Reduce label clutter: label only a small set per subclade.
  label_df <- df_plot

  # Use a synthetic vertical layout coordinate for label readability.
  # This removes the visual coupling to count on the y-axis (count is shown by point size).
  df_plot <- df_plot %>%
    group_by(subclade_label) %>%
    arrange(Number, .by_group = TRUE) %>%
    mutate(y_layout = row_number()) %>%
    ungroup()

  label_df <- label_df %>%
    group_by(subclade_label) %>%
    arrange(Number, .by_group = TRUE) %>%
    mutate(y_layout = row_number()) %>%
    ungroup()

  epitope_levels <- sort(unique(df_plot$epitope_label))
  epitope_palette <- setNames(
    fhi_discrete_palette(length(epitope_levels), kvalitativ_b),
    epitope_levels
  )
  if ("Ukjent" %in% names(epitope_palette)) {
    epitope_palette["Ukjent"] <- "#000000"
  }

  base_plot <- ggplot(df_plot, aes(x = Number, y = y_layout, color = epitope_label)) +
    geom_segment(aes(xend = Number, y = 0, yend = y_layout), linewidth = 0.5, alpha = 0.45) +
    geom_point(aes(size = n), alpha = 0.9) +
    geom_text_repel(
      data = label_df,
      aes(label = mutation_label),
      size = 2.8,
      max.overlaps = Inf,
      segment.alpha = 0.5,
      box.padding = 0.3,
      point.padding = 0.25,
      direction = "y",
      min.segment.length = 0,
      show.legend = FALSE
    ) +
    scale_color_manual(values = epitope_palette) +
    scale_size_continuous(name = "Antall (n)") +
    labs(
      title = paste("Lollipop: epitop-posisjoner i HA-proteinet (", subtype_label, ")", sep = ""),
      subtitle = subtitle_label,
      x = "AA-posisjon (HA)",
      y = NULL,
      color = "Epitope"
    ) +
    theme_classic() +
    theme(
      legend.position = "bottom",
      axis.text.y = element_blank(),
      axis.ticks.y = element_blank(),
      axis.line.y = element_blank()
    )

  if (facet_by_subclade) {
    base_plot <- base_plot +
      facet_wrap(~subclade_label, ncol = 1, scales = "free_y")
  }

  base_plot
}

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_lollipop <- build_subtype_lollipop_data(subtype_name)
  lollipop_plot <- create_epitope_lollipop_plot(
    subtype_lollipop$data,
    subtype_name,
    subtype_lollipop$window_label,
    facet_by_subclade = TRUE
  )
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    lollipop_plot,
    title = paste("Lollipop: epitop-posisjoner i HA-proteinet (", subtype_name, ")", sep = "")
  )
}

# Dot-plot style summaries (SC2-inspired): mutation load by subclade over tid.
mutation_dot_df <- ha_lollipop_source %>%
  mutate(
    Sampledate = as.Date(Sampledate),
    month_date = floor_date(Sampledate, "month"),
    subclade_label = ifelse(is.na(nc_ha_subclade) | nc_ha_subclade == "", "Ukjent", nc_ha_subclade)
  ) %>%
  filter(!is.na(month_date), !is.na(ngs_sekvens_resultat)) %>%
  group_by(ngs_sekvens_resultat, month_date, subclade_label) %>%
  summarise(
    unique_mutations_n = n_distinct(ha_mutations),
    sample_n = n(),
    .groups = "drop"
  )

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_dot_df <- mutation_dot_df %>% filter(ngs_sekvens_resultat == subtype_name)
  if (nrow(subtype_dot_df) == 0) next
  p_dot_mut <- ggplot(
    subtype_dot_df,
    aes(x = month_date, y = unique_mutations_n)
  ) +
    geom_point(aes(size = sample_n, color = subclade_label), alpha = 0.85, position = position_jitter(width = 0, height = 0.15)) +
    scale_x_date(labels = format_month_label, date_breaks = "1 month") +
    scale_color_manual(values = kvalitativ_comb) +
    labs(
      title = paste("Mutasjoner per subklade over tid -", subtype_name),
      x = "Måned",
      y = "Antall mutasjoner",
      size = "Antall sekvenser (n)",
      color = "Subklade"
    ) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right")
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_dot_mut)
}

# Dot-plot for epitope mutations over tid per subtype.
epitope_dot_df <- ha_lollipop_source %>%
  mutate(
    Sampledate = as.Date(Sampledate),
    month_date = floor_date(Sampledate, "month"),
    subclade_label = ifelse(is.na(nc_ha_subclade) | nc_ha_subclade == "", "Ukjent", nc_ha_subclade)
  ) %>%
  filter(!is.na(month_date), !is.na(ngs_sekvens_resultat)) %>%
  group_by(ngs_sekvens_resultat, month_date, subclade_label) %>%
  summarise(
    unique_mutations_n = n_distinct(ha_mutations[!is.na(Epitope) & Epitope != ""]),
    sample_n = n(),
    .groups = "drop"
  )

for (subtype_name in c("A/H1N1", "A/H3N2", "B/Victoria")) {
  subtype_epi_df <- epitope_dot_df %>% filter(ngs_sekvens_resultat == subtype_name)
  if (nrow(subtype_epi_df) == 0) next
  p_dot_epi <- ggplot(
    subtype_epi_df,
    aes(x = month_date, y = unique_mutations_n)
  ) +
    geom_point(aes(size = sample_n, color = subclade_label), alpha = 0.85, position = position_jitter(width = 0, height = 0.15)) +
    scale_x_date(labels = format_month_label, date_breaks = "1 month") +
    scale_color_manual(values = kvalitativ_comb) +
    labs(
      title = paste("Epitop mutasjoner per subklade over tid -", subtype_name),
      x = "Måned",
      y = "Antall mutasjoner",
      size = "Antall sekvenser (n)",
      color = "Subklade"
    ) +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "right")
  export_graph_f <- save_plot_to_ppt(export_graph_f, p_dot_epi)
}


# ==============================================================================
# HA mutation line plots from HA_mut
# ==============================================================================

HAcount <- HA_mut %>%
  mutate(month_year = format_month_label(as.Date(prove_tatt))) %>% # create month_year variable
  group_by(month_year, ha_mutations, ngs_sekvens_resultat) %>% # group by month_year and ha_mutations
  count(name = "n") %>% # count occurrences per group
  ungroup()

sekv <- HA_mut %>%
  select(key, ngs_sekvens_resultat, prove_tatt) %>%
  mutate(month_year = format_month_label(as.Date(prove_tatt))) %>%
  distinct(key, .keep_all = TRUE) %>% # Keep only the first occurrence of each "key"
  group_by(month_year, ngs_sekvens_resultat) %>% # Group by month_year and ngs_sekvens_resultat
  mutate(total_vsek = n()) %>% # Calculate the total count for each group
  ungroup() %>%
  select(-key, -prove_tatt) %>% # Remove the "key" column from the final result
  distinct(month_year, ngs_sekvens_resultat, .keep_all = TRUE)


HAcount <- HAcount %>%
  left_join(
    sekv,
    by = c("month_year", "ngs_sekvens_resultat"),
    relationship = "many-to-many"
  ) %>%
  mutate(
    Percent = n / total_vsek,
    Sampledate = parse_month_label(month_year)
  )


# Get unique collapsed pangos
# Loop through each unique ngs_sekvens_resultat (e.g., "A/H1N1", "A/H3N2", "B/Victoria")
for (lineage in unique(HAcount$ngs_sekvens_resultat)) {
  # Filter the data for the current lineage
  plot_data <- HAcount %>%
    filter(ngs_sekvens_resultat == lineage) # Filter by ngs_sekvens_resultat.y to get each lineage's data

  # Proceed with plotting the data for this lineage
  plot <- ggplot(
    plot_data,
    aes(
      x = Sampledate,
      y = Percent,
      group = ha_mutations,
      colour = ha_mutations
    )
  ) +
    geom_line(linewidth = 1) +
    scale_x_date(
      date_breaks = "1 month",
      labels = format_month_label,
      expand = c(0, 0)
    ) +
    ylab(axis_share_label) +
    xlab("Måned") +
    ggtitle(paste("HA mutasjoner -", lineage)) + # Updated to show lineage in title
    theme_classic() +
    theme(
      plot.title = element_text(
        color = fhi_text_dark,
        size = 20,
        hjust = 0.5,
        face = "bold"
      ),
      axis.text.x = element_text(
        color = fhi_text_dark,
        size = 10,
        angle = 90,
        hjust = .5,
        vjust = .5,
        face = "plain"
      ),
      axis.text.y = element_text(
        color = fhi_text_dark,
        size = 10,
        angle = 0,
        hjust = 1,
        vjust = 0.5,
        face = "plain"
      ),
      axis.title.x = element_text(
        color = fhi_text_dark,
        size = 15,
        angle = 0,
        hjust = .5,
        vjust = 0.5,
        face = "bold"
      ),
      axis.title.y = element_text(
        color = fhi_text_dark,
        size = 15,
        angle = 90,
        hjust = .5,
        vjust = .5,
        face = "bold"
      )
    ) +
    scale_colour_manual(
      values = setNames(
        fhi_discrete_palette(dplyr::n_distinct(plot_data$ha_mutations), kvalitativ_comb),
        sort(unique(plot_data$ha_mutations))
      ),
      guide = "none"
    ) +
    scale_y_continuous(
      labels = scales::percent_format(accuracy = 1),
      expand = c(0, 0)
    ) +
    geom_text_repel(
      data = subset(
        plot_data,
        Sampledate == max(Sampledate) &
          Percent < 0.99
      ),
      aes(
        label = sprintf(
          "%s %s",
          scales::percent(Percent),
          tools::toTitleCase(ha_mutations)
        ),
        color = ha_mutations
      ),
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

  # Print the individual plot

  # Print the individual plot to a PowerPoint slide
  export_graph_f <- save_plot_to_ppt(
    export_graph_f,
    plot,
    title = paste("HA-mutasjonslinjer -", lineage)
  )
}


# ==============================================================================
# Glycosylation dataset from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Glykosylering",
  "Glykosyleringssteder over tid per subtype"
)

# Step 1: Create the gly dataframe by combining nc_ha_gly and nc_ha_gly2, ignoring "NA" values
gly <- fludb %>%
  mutate(
    # Combine nc_ha_gly and nc_ha_gly2, excluding "NA" values
    combined_gly = paste(
      ifelse(is.na(nc_ha_gly_1) | nc_ha_gly_1 == "NA", "", nc_ha_gly_1),
      ifelse(
        is.na(nc_ha_gly_2) |
          nc_ha_gly_2 == "NA",
        "",
        nc_ha_gly_2
      ),
      sep = ";"
    )
  ) %>%
  # Clean up the combined_gly column
  mutate(
    combined_gly = gsub("^;|;$", "", combined_gly),
    # Remove leading/trailing semicolons
    combined_gly = gsub(";;", ";", combined_gly) # Remove double semicolons
  ) %>%
  select(month_year, ngs_sekvens_resultat, combined_gly) %>% # Select relevant columns
  filter(
    combined_gly != "",
    # Keep only non-empty combined_gly
    ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria") # Filter for specific subtypes
  )

# Step 2: Create individual glycosylation counts
individual_gly <- gly %>%
  separate_rows(combined_gly, sep = ";") %>% # Split combined_gly into separate rows
  filter(combined_gly != "") %>% # Remove empty strings
  group_by(month_year, ngs_sekvens_resultat, combined_gly) %>% # Group by relevant columns
  summarise(n = n(), .groups = "drop") # Count occurrences of each mutation

# Step 3: Create total counts for each month and subtype
subtcount <- gly %>%
  group_by(month_year, ngs_sekvens_resultat) %>%
  summarise(total = n(), .groups = "drop") # Total counts of records

# Step 4: Calculate percentages
individual_gly_percentm <- individual_gly %>%
  left_join(subtcount, by = c("month_year", "ngs_sekvens_resultat")) %>% # Join total counts
  mutate(
    percent = (n / total) * 100,
    # Calculate percentage
    Sampledate = as.Date(
      paste0(sub("-", " ", month_year), " 01"),
      format = "%b %Y %d"
    ) # Create a date for plotting
  ) %>%
  select(
    Sampledate,
    month_year,
    ngs_sekvens_resultat,
    combined_gly,
    n,
    total,
    percent
  ) # Select relevant columns

# Step 5: Extract the numeric part from combined_gly and create new columns for sorting
individual_gly_percentm <- individual_gly_percentm %>%
  mutate(
    gly_numeric = suppressWarnings(as.numeric(str_extract(combined_gly, "(?<=:)\\d+(?=:)"))),
    # Extract the numeric value
    gly_type = gsub(":.*", "", combined_gly) # Extract the type (HA1, HA2)
  ) %>%
  arrange(gly_type, gly_numeric) # Arrange first by type (HA1, HA2) and then by numeric value

# Step 6: Convert combined_gly to a factor ordered by type and numeric values
individual_gly_percentm$combined_gly <- factor(
  individual_gly_percentm$combined_gly,
  levels = unique(individual_gly_percentm$combined_gly[order(
    match(individual_gly_percentm$gly_type, c("HA1", "HA2")),
    individual_gly_percentm$gly_numeric
  )])
)

# Step 7: Create the heatmap
glygr <- ggplot(
  individual_gly_percentm,
  aes(x = Sampledate, y = combined_gly, fill = percent)
) +
  geom_tile(color = NA) + # Create tiles for the heatmap
  facet_wrap(~ngs_sekvens_resultat, scales = "free_y") + # Create facets for each subtype
  scale_fill_gradientn(
    colors = kvantitativ_b1,
    labels = percent_format(scale = 1)
  ) + # Use kvantitativ_b1 color scale
  scale_x_date(labels = format_month_label, breaks = scales::date_breaks("1 month")) + # Format x-axis as des-2025
  labs(
    title = "Andel glykosyleringssteder over tid per influensasubtype",
    x = "",
    y = "Glykosyleringssteder",
    fill = "Prosent"
  ) +
  theme_minimal() + # Use minimal theme for clarity
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) # Rotate x-axis text for better readability

export_graph_f <- save_plot_to_ppt(export_graph_f, glygr)


# ==============================================================================
# Frameshift, insertion, and deletion dataset from fludb
# ==============================================================================

export_graph_f <- add_section_slide(
  export_graph_f,
  "Seksjon: Frameshift, insersjoner og delesjoner",
  "Mutasjonsvarmekart per gen og subtype"
)

# Step 1: Filter the dataset for relevant subtypes and select columns
filtered_fludb <- fludb %>%
  filter(ngs_sekvens_resultat %in% c("A/H1N1", "A/H3N2", "B/Victoria")) %>%
  select(
    month_year,
    ngs_sekvens_resultat,
    "nc_ha_frameshift",
    "nc_ha_insertion",
    "nc_ha_deletion",
    "nc_na_frameshift",
    "nc_na_insertion",
    "nc_na_deletion",
    "nc_m1_frameshift",
    "nc_m1_insertion",
    "nc_m1_deletion",
    "nc_m2_frameshift",
    "nc_m2_insertion",
    "nc_m2_deletion",
    "nc_pa_frameshift",
    "nc_pa_insertion",
    "nc_pa_deletion",
    "nc_pb1_frameshift",
    "nc_pb1_insertion",
    "nc_pb1_deletion",
    "nc_pb2_frameshift",
    "nc_pb2_insertion",
    "nc_pb2_deletion",
    "nc_np_frameshift",
    "nc_np_insertion",
    "nc_np_deletion",
    "nc_ns_frameshift",
    "nc_ns_insertion",
    "nc_ns_deletion"
  )

# List of mutation types to process
mutation_columns <- c(
  "nc_ha_frameshift",
  "nc_ha_insertion",
  "nc_ha_deletion",
  "nc_na_frameshift",
  "nc_na_insertion",
  "nc_na_deletion",
  "nc_m1_frameshift",
  "nc_m1_insertion",
  "nc_m1_deletion",
  "nc_m2_frameshift",
  "nc_m2_insertion",
  "nc_m2_deletion",
  "nc_pa_frameshift",
  "nc_pa_insertion",
  "nc_pa_deletion",
  "nc_pb1_frameshift",
  "nc_pb1_insertion",
  "nc_pb1_deletion",
  "nc_pb2_frameshift",
  "nc_pb2_insertion",
  "nc_pb2_deletion",
  "nc_np_frameshift",
  "nc_np_insertion",
  "nc_np_deletion",
  "nc_ns_frameshift",
  "nc_ns_insertion",
  "nc_ns_deletion"
)

# Step 2: Create individual mutation counts for specified mutation types
create_individual_counts <- function(data, mutation_col) {
  data %>%
    separate_rows(!!sym(mutation_col), sep = ";") %>% # Split the specified column into separate rows
    filter(!is.na(!!sym(mutation_col)) & !!sym(mutation_col) != "") %>% # Remove empty strings and NAs
    group_by(month_year, ngs_sekvens_resultat, !!sym(mutation_col)) %>% # Group by relevant columns
    summarise(n = n(), .groups = "drop") # Count occurrences of each mutation
}

# Step 3: Create total counts for each month and subtype for each mutation type
create_subtcount <- function(data) {
  data %>%
    group_by(month_year, ngs_sekvens_resultat) %>%
    summarise(total = n(), .groups = "drop") # Total counts of records
}

# Step 4: Calculate percentages for each mutation type
calculate_percentages <- function(
  individual_data,
  subtcount_data,
  mutation_col
) {
  individual_data %>%
    left_join(subtcount_data, by = c("month_year", "ngs_sekvens_resultat")) %>% # Join total counts
    mutate(
      percent = (n / total) * 100, # Calculate percentage
      Sampledate = as.Date(
        paste0(sub("-", " ", month_year), " 01"),
        format = "%b %Y %d"
      ) # Create a date for plotting
    ) %>%
    select(
      Sampledate,
      month_year,
      ngs_sekvens_resultat,
      !!sym(mutation_col),
      n,
      total,
      percent
    ) # Select relevant columns
}

# Step 5: Extract the numeric part from mutation for sorting
extract_numeric_and_sort <- function(data, mutation_col) {
  data %>%
    mutate(
      mutation_numeric = suppressWarnings(as.numeric(
        str_extract(!!sym(mutation_col), "(?<=:)\\d+(?=:)")
      )), # Extract numeric value when present
      mutation_type = gsub(":.*", "", !!sym(mutation_col)) # Extract type (if applicable)
    ) %>%
    arrange(mutation_type, mutation_numeric) # Arrange first by type and then by numeric value
}

# Step 6: Create heatmaps for each mutation type
create_heatmap <- function(data, title, mutation_col) {
  ggplot(data, aes(x = Sampledate, y = !!sym(mutation_col), fill = percent)) +
    geom_tile(color = NA) + # Create tiles for the heatmap
    facet_wrap(~ngs_sekvens_resultat, scales = "free_y") + # Create facets for each subtype
    scale_fill_gradientn(
      colors = kvantitativ_b1,
      labels = percent_format(scale = 1)
    ) + # Use kvantitativ_b1 color scale
    scale_x_date(
      labels = format_month_label,
      breaks = scales::date_breaks("1 month")
    ) + # Format x-axis as des-2025
    labs(title = title, x = "", y = "Mutasjonssteder", fill = "Prosent") +
    theme_minimal() + # Use minimal theme for clarity
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) # Rotate x-axis text for better readability
}

# Loop through each mutation type and generate heatmaps
for (mutation in mutation_columns) {
  # Create individual counts
  individual_counts <- create_individual_counts(filtered_fludb, mutation)

  # Create total counts for the mutation type
  subtcount <- create_subtcount(filtered_fludb)

  # Calculate percentages
  individual_percent <- calculate_percentages(
    individual_counts,
    subtcount,
    mutation
  )

  # Extract numeric values and sort
  sorted_data <- extract_numeric_and_sort(individual_percent, mutation)

  # Create and print heatmap
  heatmap_title <- paste0(
    gsub("_", " ", mutation),
    " andel over tid per influensasubtype"
  )
  heatmap <- create_heatmap(sorted_data, heatmap_title, mutation)
  export_graph_f <- save_plot_to_ppt(export_graph_f, heatmap)
}

# ==============================================================================
# Export
# ==============================================================================

# Get the current week and year
current_week <- week(Sys.Date())
current_year <- year(Sys.Date())
results_root <- Sys.getenv("INF_RESULTS_DIR", unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Results")
results_share_root <- Sys.getenv(
  "INF_RESULTS_SHARE_DIR",
  unset = "C:/Users/aroh/OneDrive - Folkehelseinstituttet/Sesong 2025_26"
)


# Create the file name including the season
file_name_result <- paste0(
  "Influenza_",
  "_Week.",
  current_week,
  "-",
  current_year,
  "_result.pptx"
)
# Specify the full file paths
file_path_result <- file.path(
  results_root,
  file_name_result
)
file_path_resultshare <- file.path(
  results_share_root,
  file_name_result
)

export_graph_f <- add_section_slide(
  export_graph_f,
  "Population Under Surveillance"
)

add_meta_plot <- function(plot_obj, plot_title) {
  if (is.null(plot_obj)) return(invisible(NULL))
  export_graph_f <<- save_plot_to_ppt(export_graph_f, plot_obj, title = plot_title)
}

norway_geojson_path <- resolve_norway_geojson_path()
flu_prev <- fludb %>% filter(season == previous_season_label)
flu_curr <- fludb %>% filter(season == current_season_label)

p_fylke_prev <- build_fylke_map_plot_shared(
  flu_prev,
  fylke_col = "pasient_fylke_name",
  shape_path = norway_geojson_path,
  fill_palette = kvantitativ_b2
)
p_fylke_curr <- build_fylke_map_plot_shared(
  flu_curr,
  fylke_col = "pasient_fylke_name",
  shape_path = norway_geojson_path,
  fill_palette = kvantitativ_b2
)
if (!is.null(p_fylke_curr) && !is.null(p_fylke_prev)) {
  n_curr_map <- nrow(flu_curr)
  n_prev_map <- nrow(flu_prev)
  p_fylke_pair <- (p_fylke_prev + labs(subtitle = paste0(previous_season_label, " (m=", scales::comma(n_prev_map), ")"))) |
    (p_fylke_curr + labs(subtitle = paste0(current_season_label, " (m=", scales::comma(n_curr_map), ")")))
  add_meta_plot(p_fylke_pair, "Map: Fylke fordeling - left current, right previous")
}

p_landsdel_prev <- build_landsdel_map_plot_shared(
  flu_prev,
  fylke_col = "pasient_fylke_name",
  landsdel_col = "pasient_landsdel_from_fylke",
  shape_path = norway_geojson_path,
  palette_base = kvalitativ_comb
)
p_landsdel_curr <- build_landsdel_map_plot_shared(
  flu_curr,
  fylke_col = "pasient_fylke_name",
  landsdel_col = "pasient_landsdel_from_fylke",
  shape_path = norway_geojson_path,
  palette_base = kvalitativ_comb
)
if (!is.null(p_landsdel_curr) && !is.null(p_landsdel_prev)) {
  n_curr_map <- nrow(flu_curr)
  n_prev_map <- nrow(flu_prev)
  p_landsdel_pair <- (p_landsdel_prev + labs(subtitle = paste0(previous_season_label, " (m=", scales::comma(n_prev_map), ")"))) |
    (p_landsdel_curr + labs(subtitle = paste0(current_season_label, " (m=", scales::comma(n_curr_map), ")")))
  add_meta_plot(p_landsdel_pair, "Map: Landsdel fordeling - left current, right previous")
}

# Kjønn: current season vs previous season, pie side-by-side + monthly comparison
if (all(c("pasient_kjnn", "season", "prove_tatt") %in% names(fludb))) {
  kjonn_compare <- fludb %>%
    mutate(
      pasient_kjnn = ifelse(is.na(pasient_kjnn) | trimws(as.character(pasient_kjnn)) == "", "Ukjent", as.character(pasient_kjnn))
    ) %>%
    filter(season %in% c(current_season_label, previous_season_label))

  pie_builder <- function(dat, season_lbl) {
    d <- dat %>%
      filter(season == season_lbl) %>%
      count(pasient_kjnn, name = "n")
    if (nrow(d) == 0) return(NULL)
    season_n <- sum(d$n, na.rm = TRUE)
    d <- d %>%
      mutate(
        pct = ifelse(season_n > 0, 100 * n / season_n, 0),
        label_txt = paste0("N=", scales::comma(n))
      )
    ggplot(d, aes(x = "", y = n, fill = pasient_kjnn)) +
      geom_col(width = 1) +
      geom_text(
        aes(label = label_txt),
        position = position_stack(vjust = 0.5),
        size = 3
      ) +
      coord_polar(theta = "y") +
      scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$pasient_kjnn), kvalitativ_comb)) +
      labs(title = paste0(season_lbl, " (N=", scales::comma(season_n), ")"), fill = "Kjønn") +
      theme_void()
  }

  p_kj_prev <- pie_builder(kjonn_compare, previous_season_label)
  p_kj_curr <- pie_builder(kjonn_compare, current_season_label)
  if (!is.null(p_kj_prev) && !is.null(p_kj_curr)) {
    n_prev <- kjonn_compare %>% filter(season == previous_season_label) %>% nrow()
    n_curr <- kjonn_compare %>% filter(season == current_season_label) %>% nrow()
    p_kj_pies <- p_kj_prev + p_kj_curr + patchwork::plot_layout(ncol = 2, guides = "collect") &
      theme(legend.position = "right")
    add_meta_plot(
      p_kj_pies,
      paste0(
        "Kjønn: ", previous_season_label, " (N=", scales::comma(n_prev), ") vs ",
        current_season_label, " (N=", scales::comma(n_curr), ") (pie)"
      )
    )
  }

  month_levels_season <- c("Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug")
  kjonn_month <- kjonn_compare %>%
    mutate(
      month_num = lubridate::month(prove_tatt),
      month_in_season = ((month_num - 9) %% 12) + 1L,
      month_lbl = factor(month_levels_season[month_in_season], levels = month_levels_season)
    ) %>%
    count(season, month_lbl, pasient_kjnn, name = "n")

  if (nrow(kjonn_month) > 0) {
    p_kj_month <- ggplot(kjonn_month, aes(x = month_lbl, y = n, fill = pasient_kjnn)) +
      geom_col(position = "stack") +
      facet_wrap(~season, ncol = 1) +
      scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(kjonn_month$pasient_kjnn), kvalitativ_comb)) +
      labs(title = "Kjønn per måned: nåværende vs forrige sesong", x = "Måned i sesong", y = "Antall (n)", fill = "Kjønn") +
      theme_minimal() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1))
    add_meta_plot(p_kj_month, "Kjønn per måned: sesongsammenligning")
  }
}

# Aldersgruppe: season comparison in same side-by-side format as Kjønn.
if (all(c("pasient_aldersgruppe", "season") %in% names(fludb))) {
  alder_compare <- fludb %>%
    mutate(
      pasient_aldersgruppe = ifelse(
        is.na(pasient_aldersgruppe) | trimws(as.character(pasient_aldersgruppe)) == "",
        "Ukjent",
        as.character(pasient_aldersgruppe)
      )
    ) %>%
    filter(season %in% c(current_season_label, previous_season_label))

  p_alder_pies <- build_two_season_pie_compare(
    alder_compare,
    season_col = "season",
    category_col = "pasient_aldersgruppe",
    previous_label = previous_season_label,
    current_label = current_season_label,
    category_label = "Aldersgruppe",
    palette_base = kvalitativ_comb
  )
  add_meta_plot(p_alder_pies, "Aldersgruppe: sesongsammenligning")
}

# SC2-guided harmonized patient/prove panels for FLU
tessy_color_col <- intersect(c("tessy_reportable_variable", "Tessy", "tessy"), names(fludb))[1]
virus_col <- if ("ngs_sekvens_resultat" %in% names(fludb)) "ngs_sekvens_resultat" else NULL
virus_map <- c("A/H1N1" = "H1N1", "A/H3N2" = "H3N2", "B/Victoria" = "BVIC")
if (!is.na(tessy_color_col) && !is.null(virus_col) && "prove_tatt" %in% names(fludb)) {
  flu_dims <- c(
    "pasient_fylke_name" = "Fylke",
    "pasient_landsdel_from_fylke" = "Landsdel",
    "pasient_aldersgruppe" = "Age group",
    "pasient_status" = "Patient status",
    "prove_kategori_group" = "Sample category group"
  )
  flu_dims <- flu_dims[names(flu_dims) %in% names(fludb)]

  export_graph_f <- add_section_slide(
    export_graph_f,
    "Patient Related Analysis"
  )
  norway_geojson_path <- resolve_norway_geojson_path()

  for (virus_key in names(virus_map)) {
    virus_label <- virus_map[[virus_key]]
    flu_v <- fludb %>%
      filter(
        season == current_season_label,
        .data[[virus_col]] == virus_key,
        !is.na(.data[[tessy_color_col]]),
        trimws(as.character(.data[[tessy_color_col]])) != ""
      )
    if (nrow(flu_v) == 0) next

    # Add maps per type (fylke + landsdel) in this shared section.
    if ("pasient_fylke_name" %in% names(flu_v)) {
      p_fylke <- build_fylke_map_plot_shared(
        flu_v,
        fylke_col = "pasient_fylke_name",
        shape_path = norway_geojson_path,
        fill_palette = kvantitativ_b2
      )
      if (!is.null(p_fylke)) {
        export_graph_f <- save_plot_to_ppt(
          export_graph_f,
          p_fylke,
          title = paste0(virus_label, " - Fylke fordeling")
        )
      }
    }
    if (all(c("pasient_fylke_name", "pasient_landsdel_from_fylke") %in% names(flu_v))) {
      p_landsdel <- build_landsdel_map_plot_shared(
        flu_v,
        fylke_col = "pasient_fylke_name",
        landsdel_col = "pasient_landsdel_from_fylke",
        shape_path = norway_geojson_path,
        palette_base = kvalitativ_comb
      )
      if (!is.null(p_landsdel)) {
        export_graph_f <- save_plot_to_ppt(
          export_graph_f,
          p_landsdel,
          title = paste0(virus_label, " - Landsdel fordeling")
        )
      }
    }

    for (dim_col in names(flu_dims)) {
      dim_label <- flu_dims[[dim_col]]
      p_pair <- build_group_distribution_plots(
        flu_v,
        x_col = dim_col,
        color_col = tessy_color_col,
        x_label = dim_label,
        color_label = "Tessy",
        title_prefix = paste0(virus_label, " Tessy by ", dim_label, " - current season"),
        palette_base = kvalitativ_comb
      )
      if (is.null(p_pair)) next
      p_combined <- (p_pair$count_plot | p_pair$percent_plot) +
        patchwork::plot_layout(guides = "collect") &
        theme(legend.position = "bottom")
      export_graph_f <- save_plot_to_ppt(
        export_graph_f,
        p_combined,
        title = paste0(virus_label, " by ", dim_label, " (count + %)")
      )
    }
  }
}

excel_export_file_name_xlsx <- paste0(
  "Influenza_",
  "_Week.",
  current_week,
  "-",
  current_year,
  "_tabeller.xlsx"
)
excel_export_prefix_csv <- sub("\\.xlsx$", "", excel_export_file_name_xlsx)

excel_export_path_result_xlsx <- file.path(
  results_root,
  excel_export_file_name_xlsx
)
excel_export_path_share_xlsx <- file.path(
  results_share_root,
  excel_export_file_name_xlsx
)

excel_export_sheets <- c(
  list(WHO_ECDC_frekvenstabell = frequency_table_df),
  excel_export_sheets
)
names(excel_export_sheets) <- make.unique(names(excel_export_sheets), sep = "_")

if (requireNamespace("openxlsx", quietly = TRUE)) {
  openxlsx::write.xlsx(
    excel_export_sheets,
    file = excel_export_path_result_xlsx,
    overwrite = TRUE
  )
  openxlsx::write.xlsx(
    excel_export_sheets,
    file = excel_export_path_share_xlsx,
    overwrite = TRUE
  )
  cat(
    sprintf(
      "Excel-tabeller lagret:\n- %s\n- %s\n",
      excel_export_path_result_xlsx,
      excel_export_path_share_xlsx
    )
  )
} else {
  for (sheet_name in names(excel_export_sheets)) {
    csv_file_name <- paste0(
      excel_export_prefix_csv,
      "_",
      sanitize_excel_sheet_name(sheet_name),
      ".csv"
    )
    write.csv(
      excel_export_sheets[[sheet_name]],
      file = file.path(
        results_root,
        csv_file_name
      ),
      row.names = FALSE,
      fileEncoding = "UTF-8"
    )
    write.csv(
      excel_export_sheets[[sheet_name]],
      file = file.path(
        results_share_root,
        csv_file_name
      ),
      row.names = FALSE,
      fileEncoding = "UTF-8"
    )
  }
  cat(
    sprintf(
      "openxlsx er ikke tilgjengelig. Tabeller lagret som CSV-filer med prefiks:\n- %s\n- %s\n",
      file.path(
        results_root,
        excel_export_prefix_csv
      ),
      file.path(
        results_share_root,
        excel_export_prefix_csv
      )
    )
  )
}

invisible(timed_step(
  "Write PPTX to Results",
  invisible(capture.output(print(export_graph_f, target = file_path_result)))
))
invisible(timed_step(
  "Write PPTX to OneDrive share",
  invisible(capture.output(print(export_graph_f, target = file_path_resultshare)))
))

slide_count <- length(export_graph_f)
cat(
  sprintf(
    "PowerPoint lagret med %d lysbilder (lysbilde 1-%d):\n- %s\n- %s\n",
    slide_count,
    slide_count,
    file_path_result,
    file_path_resultshare
  )
)
total_elapsed_sec <- as.numeric(difftime(Sys.time(), analysis_started_at, units = "secs"))
log_timed_message("TOTAL RUNTIME: ", sprintf("%.2f", total_elapsed_sec), "s")
# nolint end
