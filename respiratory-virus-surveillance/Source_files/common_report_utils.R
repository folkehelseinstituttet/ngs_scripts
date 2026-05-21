# Shared report helpers for Influenza and SARS-CoV-2 analyses.
## ============================================================================
## SHARED REPORT UTILITIES
## Structure:
## 1) Core utility functions
## 2) Shared dictionaries/constants
## 3) Plotting and export helpers
## ============================================================================

## -------------------------
## 1) Core utility functions
## -------------------------
utils::globalVariables(
  c(
    ".data", "cat", "color_group", "ct_value", "cov_norm", "fv", "label_txt",
    "month_date", "n", "pct", "percent", "run_id", "virus_group", "xv"
  )
)

## Label/date helpers
format_month_label <- function(x) {
  tolower(format(as.Date(x), "%b-%Y"))
}

parse_month_label <- function(x) {
  as.Date(paste0("01-", x), format = "%d-%b-%Y")
}

season_start_year_from_date <- function(x) {
  d <- as.Date(x)
  y <- lubridate::year(d)
  w <- suppressWarnings(lubridate::isoweek(d))
  ifelse(!is.na(w) & w >= 35, y, y - 1L)
}

season_label_from_start_year <- function(start_year) {
  sy <- as.integer(start_year)
  ey <- sy + 1L
  paste0("Season", sprintf("%02d", sy %% 100L), "_", sprintf("%02d", ey %% 100L))
}

season_label_from_date <- function(x) {
  season_label_from_start_year(season_start_year_from_date(x))
}

season_window_bounds <- function(start_year) {
  sy <- as.integer(start_year)
  list(
    start = as.Date(sprintf("%04d-08-29", sy)),
    end = as.Date(sprintf("%04d-08-28", sy + 1L))
  )
}

current_and_previous_seasons <- function(today = Sys.Date()) {
  cur_start_year <- as.integer(season_start_year_from_date(today))
  list(
    current_start_year = cur_start_year,
    current_label = season_label_from_start_year(cur_start_year),
    previous_start_year = cur_start_year - 1L,
    previous_label = season_label_from_start_year(cur_start_year - 1L)
  )
}

# Run-quality window:
# use current season only, but if current season is shorter than min_months,
# include prior-season dates to fill a full min_months lookback.
run_quality_window_bounds <- function(today = Sys.Date(), min_months = 6L) {
  d_today <- as.Date(today)
  season_info <- current_and_previous_seasons(d_today)
  season_bounds <- season_window_bounds(season_info$current_start_year)
  six_month_start <- lubridate::`%m-%`(
    d_today,
    lubridate::period(months = as.integer(min_months))
  )
  start_date <- min(season_bounds$start, six_month_start, na.rm = TRUE)
  list(
    start = as.Date(start_date),
    end = d_today,
    current_season_start = as.Date(season_bounds$start),
    current_season_end = as.Date(season_bounds$end)
  )
}

normalize_norwegian_text <- function(x) {
  x_chr <- as.character(x)
  x_chr[is.na(x_chr)] <- ""

  mojibake_fixes <- c(
    "TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¿ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â½ndelag" = "TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ndelag",
    "TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ndelag" = "TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ndelag",
    "SÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸r-TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ndelag" = "SÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸r-TrÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ndelag",
    "MÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸re og Romsdal" = "MÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸re og Romsdal",
    "ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“stfold" = "ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œstfold",
    "SÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸rlandet" = "SÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸rlandet",
    "ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¹ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“stlandet" = "ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œstlandet"
  )

  out <- enc2utf8(x_chr)
  out <- iconv(out, from = "", to = "UTF-8", sub = "")
  out[is.na(out)] <- ""

  for (i in seq_along(mojibake_fixes)) {
    out <- gsub(names(mojibake_fixes)[i], unname(mojibake_fixes[i]), out, fixed = TRUE)
  }

  out
}

normalize_geography_key <- function(x) {
  x_norm <- normalize_norwegian_text(x)
  x_norm <- trimws(x_norm)
  x_norm <- stringr::str_to_lower(x_norm)
  x_norm <- iconv(x_norm, from = "UTF-8", to = "ASCII//TRANSLIT", sub = "")
  x_norm[is.na(x_norm)] <- ""
  x_norm <- stringr::str_replace_all(x_norm, "[^a-z0-9]+", " ")
  stringr::str_squish(x_norm)
}

normalize_fylke_value <- function(x) {
  key <- normalize_geography_key(x)
  mapped <- unname(fylke_value_dictionary[key])
  mapped[is.na(mapped) & key == ""] <- "Ukjent"
  mapped[is.na(mapped)] <- normalize_norwegian_text(x)[is.na(mapped)]
  mapped <- trimws(mapped)
  mapped[mapped == ""] <- "Ukjent"
  mapped
}

normalize_landsdel_value <- function(x) {
  key <- normalize_geography_key(x)
  mapped <- unname(landsdel_value_dictionary[key])
  mapped[is.na(mapped) & key == ""] <- "Ukjent"
  mapped[is.na(mapped)] <- normalize_norwegian_text(x)[is.na(mapped)]
  mapped <- trimws(mapped)
  mapped[mapped == ""] <- "Ukjent"
  mapped
}

derive_landsdel_from_fylke <- function(fylke_vec) {
  fylke_std <- normalize_fylke_value(fylke_vec)
  key <- normalize_geography_key(fylke_std)
  mapped <- unname(fylke_to_landsdel_dictionary[key])
  mapped[is.na(mapped)] <- "Ukjent"
  mapped
}

normalize_geography_columns <- function(
  df,
  fylke_col = "pasient_fylke_name",
  landsdel_col = "pasient_landsdel",
  preserve_raw = TRUE
) {
  if (is.null(df) || nrow(df) == 0) return(df)

  derived_landsdel <- NULL

  if (!is.null(fylke_col) && fylke_col %in% names(df)) {
    raw_col <- paste0(fylke_col, "_raw")
    if (preserve_raw && !raw_col %in% names(df)) df[[raw_col]] <- df[[fylke_col]]
    df[[fylke_col]] <- normalize_fylke_value(df[[fylke_col]])
    map_col <- paste0(fylke_col, "_map")
    df[[map_col]] <- unname(fylke_to_current_map_dictionary[normalize_geography_key(df[[fylke_col]])])
    df[[map_col]][is.na(df[[map_col]])] <- "Ukjent"
    derived_landsdel <- derive_landsdel_from_fylke(df[[fylke_col]])
    df$pasient_landsdel_from_fylke <- derived_landsdel
  }

  if (!is.null(landsdel_col) && landsdel_col %in% names(df)) {
    raw_col <- paste0(landsdel_col, "_raw")
    if (preserve_raw && !raw_col %in% names(df)) df[[raw_col]] <- df[[landsdel_col]]
    df[[landsdel_col]] <- normalize_landsdel_value(df[[landsdel_col]])
  } else if (!is.null(derived_landsdel)) {
    df[[landsdel_col]] <- derived_landsdel
  }

  if (!is.null(derived_landsdel)) {
    replace_idx <- is.na(df[[landsdel_col]]) | trimws(as.character(df[[landsdel_col]])) %in% c("", "Ukjent")
    df[[landsdel_col]][replace_idx] <- derived_landsdel[replace_idx]
  }

  df
}

fhi_discrete_palette <- function(n, palette = kvalitativ_comb) {
  if (n <= length(palette)) {
    palette[seq_len(n)]
  } else {
    grDevices::colorRampPalette(palette)(n)
  }
}

## -------------------------
## 2) Shared dictionaries/constants
## -------------------------
## FHI color palettes
kvalitativ_a <- c("#ec7c73", "#40436d", "#61d2b2", "#a93c38", "#f9dc8c", "#7176c9", "#e0f0f7", "#09181f")
kvalitativ_b <- c("#65a9c5", "#2a6a82", "#f0af5e", "#fee9e6", "#179463", "#c8e1ec")
kvalitativ_comb <- c(
  "#ec7c73", "#40436d", "#61d2b2", "#a93c38", "#f9dc8c", "#7176c9", "#e0f0f7",
  "#09181f", "#65a9c5", "#2a6a82", "#f0af5e", "#fee9e6", "#179463", "#c8e1ec"
)
kvantitativ_b2 <- c(
  "#f2fafe", "#e0f0f7", "#c8e1ec", "#8fc5dc", "#65a9c5",
  "#4089a7", "#2a6a82", "#234e5f", "#16323d", "#09181f"
)
kvantitativ_b1 <- c(
  "#fafbff", "#ebedff", "#d8ddff", "#b0b8fa", "#8e96f3",
  "#7176c9", "#595d9d", "#40436d", "#292b47", "#131428"
)
kvantitativ_r1 <- c(
  "#fff6f5", "#fee9e6", "#ffd2cc", "#fda49b", "#ec7c73",
  "#d74b46", "#a93c38", "#7b2623", "#4f1a17", "#2c0807"
)
kvantitativ_gu1 <- c(
  "#fff7ee", "#faead5", "#f9dc8c", "#f0af5e", "#d39244",
  "#ac763a", "#83592d", "#5f4122", "#3c2917", "#221305"
)
kvantitativ_gr1 <- c(
  "#f2fbfa", "#d9f4ed", "#b5e8d9", "#61d2b2", "#00b782",
  "#179463", "#396e4d", "#2d4f35", "#203323", "#0d1b0a"
)
divergerende_3_1_3 <- c("#7b2623", "#d74b46", "#fda49b", "#ffffff", "#8fc5dc", "#4089a7", "#234e5f")
divergerende_6_1_6 <- c(
  "#7b2623", "#a93c38", "#d74b46", "#ec7c73", "#fda49b", "#ffd2cc", "#ffffff",
  "#c8e1ec", "#8fc5dc", "#65a9c5", "#4089a7", "#2a6a82", "#234e5f"
)
sc2_palette <- kvalitativ_comb

## Shared patient normalization helpers
# Canonical labels used across pathogens.
sex_levels_standard <- c("Female", "Male", "Ukjent")
age_group_levels_standard <- c("0-4", "5-14", "15-24", "25-59", "60+", "Ukjent")

# Dictionary for observed sex values across FLU/RSV/SC2 SQL outputs.
sex_value_dictionary <- c(
  "F" = "Female",
  "f" = "Female",
  "K" = "Female",
  "k" = "Female",
  "M" = "Male",
  "m" = "Male",
  "U" = "Ukjent",
  "u" = "Ukjent",
  "N" = "Ukjent",
  "0" = "Ukjent"
)

# Fylke normalization is based on observed SC2 raw outputs and harmonized for
# cross-pathogen cleaning. Ambiguous historical merged counties are preserved as
# canonical historical labels, while *_map columns carry the current-map-safe
# version used for shapefile joins when needed.
fylke_value_dictionary <- c(
  "0" = "Ukjent",
  "99" = "Ukjent",
  "na" = "Ukjent",
  "n a" = "Ukjent",
  "n a n" = "Ukjent",
  "none" = "Ukjent",
  "unknown" = "Ukjent",
  "ukjent" = "Ukjent",
  "mangler" = "Ukjent",
  "ikke oppgitt" = "Ukjent",
  "agder" = "Agder",
  "aust agder" = "Agder",
  "vest agder" = "Agder",
  "akershus" = "Akershus",
  "buskerud" = "Buskerud",
  "finnmark" = "Finnmark",
  "finnmark finnmarku finmarkku" = "Finnmark",
  "hedmark" = "Innlandet",
  "oppland" = "Innlandet",
  "innlandet" = "Innlandet",
  "innlandt" = "Innlandet",
  "innlandet sisdajve" = "Innlandet",
  "more og romsdal" = "Møre og Romsdal",
  "mre og romsdal" = "Møre og Romsdal",
  "nordland" = "Nordland",
  "nordland nordlannda nordlanda nordlaante" = "Nordland",
  "oslo" = "Oslo",
  "rogaland" = "Rogaland",
  "telemark" = "Telemark",
  "troms" = "Troms",
  "troms romsa tromssa" = "Troms",
  "trondelag" = "Trøndelag",
  "trafa ndelag" = "Trøndelag",
  "sor trondelag" = "Trøndelag",
  "sor trndelag" = "Trøndelag",
  "nord trondelag" = "Trøndelag",
  "trondelag troondelage" = "Trøndelag",
  "vestfold" = "Vestfold",
  "vestland" = "Vestland",
  "hordaland" = "Vestland",
  "sogn og fjordane" = "Vestland",
  "ostfold" = "Østfold",
  "viken" = "Viken",
  "viksen" = "Viken",
  "vestfold og telemark" = "Vestfold og Telemark",
  "troms og finnmark" = "Troms og Finnmark"
)

fylke_to_current_map_dictionary <- c(
  "agder" = "Agder",
  "akershus" = "Akershus",
  "buskerud" = "Buskerud",
  "finnmark" = "Finnmark",
  "innlandet" = "Innlandet",
  "more og romsdal" = "Møre og Romsdal",
  "nordland" = "Nordland",
  "oslo" = "Oslo",
  "rogaland" = "Rogaland",
  "telemark" = "Telemark",
  "troms" = "Troms",
  "trondelag" = "Trøndelag",
  "trafa ndelag" = "Trøndelag",
  "vestfold" = "Vestfold",
  "vestland" = "Vestland",
  "ostfold" = "Østfold",
  "viken" = "Ukjent",
  "vestfold og telemark" = "Ukjent",
  "troms og finnmark" = "Ukjent",
  "ukjent" = "Ukjent"
)

landsdel_value_dictionary <- c(
  "sorlandet" = "Sørlandet",
  "srlandet" = "Sørlandet",
  "vestlandet" = "Vestlandet",
  "ostlandet" = "Østlandet",
  "stlandet" = "Østlandet",
  "midt norge" = "Midt-Norge",
  "midtnorge" = "Midt-Norge",
  "midt norge trondelag" = "Midt-Norge",
  "nord norge" = "Nord-Norge",
  "nordnorge" = "Nord-Norge",
  "ukjent" = "Ukjent"
)

fylke_to_landsdel_dictionary <- c(
  "agder" = "Sørlandet",
  "akershus" = "Østlandet",
  "buskerud" = "Østlandet",
  "finnmark" = "Nord-Norge",
  "innlandet" = "Østlandet",
  "more og romsdal" = "Vestlandet",
  "nordland" = "Nord-Norge",
  "oslo" = "Østlandet",
  "rogaland" = "Vestlandet",
  "telemark" = "Østlandet",
  "troms" = "Nord-Norge",
  "trondelag" = "Midt-Norge",
  "trafa ndelag" = "Midt-Norge",
  "vestfold" = "Østlandet",
  "vestland" = "Vestlandet",
  "ostfold" = "Østlandet",
  "viken" = "Østlandet",
  "vestfold og telemark" = "Østlandet",
  "troms og finnmark" = "Nord-Norge",
  "ukjent" = "Ukjent"
)

normalize_sex_value <- function(x) {
  x_chr <- as.character(x)
  x_chr <- trimws(x_chr)
  x_chr[is.na(x_chr)] <- ""
  x_chr[x_chr == ""] <- "U"
  mapped <- unname(sex_value_dictionary[x_chr])
  mapped[is.na(mapped)] <- "Ukjent"
  factor(mapped, levels = sex_levels_standard)
}

normalize_sex_column <- function(df, candidate_cols = c("pasient_kjnn", "pasient_kjonn")) {
  if (is.null(df) || nrow(df) == 0) {
    df$pasient_kjonn_std <- factor(character(0), levels = sex_levels_standard)
    return(df)
  }
  hit <- candidate_cols[candidate_cols %in% names(df)]
  if (length(hit) == 0) {
    df$pasient_kjonn_std <- factor(rep("Ukjent", nrow(df)), levels = sex_levels_standard)
    return(df)
  }
  df$pasient_kjonn_std <- normalize_sex_value(df[[hit[1]]])
  df
}

age_to_group_standard <- function(age_vec) {
  age_num <- suppressWarnings(as.numeric(trimws(as.character(age_vec))))
  out <- dplyr::case_when(
    !is.na(age_num) & age_num >= 0 & age_num <= 4 ~ "0-4",
    !is.na(age_num) & age_num >= 5 & age_num <= 14 ~ "5-14",
    !is.na(age_num) & age_num >= 15 & age_num <= 24 ~ "15-24",
    !is.na(age_num) & age_num >= 25 & age_num <= 59 ~ "25-59",
    !is.na(age_num) & age_num >= 60 ~ "60+",
    TRUE ~ "Ukjent"
  )
  factor(out, levels = age_group_levels_standard)
}

# Structured palette map (tone-based) + flattened lookup.
palette <- list(
  B1 = c(
    `98` = "#FAFBFF",
    `95` = "#EBEDFF",
    `90` = "#D8DDFF",
    `80` = "#B0B8FA",
    `70` = "#8E96F3",
    `60` = "#7176C9",
    `50` = "#595D9D",
    `40` = "#40436D",
    `30` = "#292B47",
    `20` = "#131428"
  ),
  B2 = c(
    `98` = "#F2FAFE",
    `95` = "#E0F0F7",
    `90` = "#C8E1EC",
    `80` = "#8FC5DC",
    `70` = "#65A9C5",
    `60` = "#4089A7",
    `50` = "#2A6A82",
    `40` = "#234E5F",
    `30` = "#16323D",
    `20` = "#09181F"
  ),
  GU1 = c(
    `98` = "#FFF7EE",
    `95` = "#FAEAD5",
    `90` = "#F9DC8C",
    `80` = "#F0AF5E",
    `70` = "#D39244",
    `60` = "#AC763A",
    `50` = "#83592D",
    `40` = "#5F4122",
    `30` = "#3C2917",
    `20` = "#221305"
  ),
  GR1 = c(
    `98` = "#F2FBFA",
    `95` = "#D9F4ED",
    `90` = "#B5E8D9",
    `80` = "#61D2B2",
    `70` = "#00B782",
    `60` = "#179463",
    `50` = "#396E4D",
    `40` = "#2D4F35",
    `30` = "#203323",
    `20` = "#0D1B0A"
  ),
  R1 = c(
    `98` = "#FFF6F5",
    `95` = "#FEE9E6",
    `90` = "#FFD2CC",
    `80` = "#FDA49B",
    `70` = "#EC7C73",
    `60` = "#D74B46",
    `50` = "#A93C38",
    `40` = "#7B2623",
    `30` = "#4F1A17",
    `20` = "#2C0807"
  )
)

palette_all <- c(
  B1_98 = "#FAFBFF",
  B1_95 = "#EBEDFF",
  B1_90 = "#D8DDFF",
  B1_80 = "#B0B8FA",
  B1_70 = "#8E96F3",
  B1_60 = "#7176C9",
  B1_50 = "#595D9D",
  B1_40 = "#40436D",
  B1_30 = "#292B47",
  B1_20 = "#131428",
  B2_98 = "#F2FAFE",
  B2_95 = "#E0F0F7",
  B2_90 = "#C8E1EC",
  B2_80 = "#8FC5DC",
  B2_70 = "#65A9C5",
  B2_60 = "#4089A7",
  B2_50 = "#2A6A82",
  B2_40 = "#234E5F",
  B2_30 = "#16323D",
  B2_20 = "#09181F",
  GU1_98 = "#FFF7EE",
  GU1_95 = "#FAEAD5",
  GU1_90 = "#F9DC8C",
  GU1_80 = "#F0AF5E",
  GU1_70 = "#D39244",
  GU1_60 = "#AC763A",
  GU1_50 = "#83592D",
  GU1_40 = "#5F4122",
  GU1_30 = "#3C2917",
  GU1_20 = "#221305",
  GR1_98 = "#F2FBFA",
  GR1_95 = "#D9F4ED",
  GR1_90 = "#B5E8D9",
  GR1_80 = "#61D2B2",
  GR1_70 = "#00B782",
  GR1_60 = "#179463",
  GR1_50 = "#396E4D",
  GR1_40 = "#2D4F35",
  GR1_30 = "#203323",
  GR1_20 = "#0D1B0A",
  R1_98 = "#FFF6F5",
  R1_95 = "#FEE9E6",
  R1_90 = "#FFD2CC",
  R1_80 = "#FDA49B",
  R1_70 = "#EC7C73",
  R1_60 = "#D74B46",
  R1_50 = "#A93C38",
  R1_40 = "#7B2623",
  R1_30 = "#4F1A17",
  R1_20 = "#2C0807"
)

## -------------------------
## 3) Plotting and export helpers
## -------------------------
## PowerPoint helpers
save_plot_to_ppt <- function(
  presentation,
  plot,
  layout = "Title and Content",
  master = "Office Theme",
  title = NULL
) {
  plot_rvg <- rvg::dml(ggobj = plot)
  slide_title <- title

  if (is.null(slide_title) && !is.null(plot$labels$title)) {
    slide_title <- plot$labels$title
  }
  if (is.null(slide_title) || !nzchar(slide_title)) {
    slide_title <- "Figur"
  }

  presentation <- officer::add_slide(presentation, layout = layout, master = master) |>
    officer::ph_with(plot_rvg, location = officer::ph_location_type(type = "body"))

  presentation <- officer::ph_with(
    presentation,
    value = slide_title,
    location = officer::ph_location_type(type = "title")
  )

  presentation
}

# Backward-compatible wrapper used in SARS markdown
save_plot <- function(plot, slide_title, export_graph) {
  save_plot_to_ppt(
    presentation = export_graph,
    plot = plot,
    layout = "Title and Content",
    master = "Office Theme",
    title = slide_title
  )
}

save_table_to_ppt <- function(
  presentation,
  table,
  caption,
  layout = "Title and Content",
  master = "Office Theme"
) {
  table_flextable <- flextable::flextable(table) |>
    flextable::autofit()

  presentation <- officer::add_slide(presentation, layout = layout, master = master)
  presentation <- officer::ph_with(
    presentation,
    value = table_flextable,
    location = officer::ph_location_type(type = "body")
  )
  presentation <- officer::ph_with(
    presentation,
    value = caption,
    location = officer::ph_location_type(type = "title")
  )

  presentation
}

add_section_slide <- function(
  presentation,
  title,
  subtitle = NULL,
  layout = "Title and Content",
  master = "Office Theme"
) {
  presentation <- officer::add_slide(presentation, layout = layout, master = master)
  presentation <- officer::ph_with(
    presentation,
    value = title,
    location = officer::ph_location_type(type = "title")
  )

  if (!is.null(subtitle) && nzchar(subtitle)) {
    presentation <- officer::ph_with(
      presentation,
      value = subtitle,
      location = officer::ph_location_type(type = "body")
    )
  }

  presentation
}

report_review_mode <- function() {
  identical(tolower(Sys.getenv("REPORT_REVIEW_MODE", unset = "false")), "true")
}

decorate_slide_title <- function(title, id = NULL) {
  if (report_review_mode() && !is.null(id) && nzchar(id)) {
    paste0("[", id, "] ", title)
  } else {
    title
  }
}

## Metadata plot variants (SC2 / FLU / RSV styles)
build_metadata_counts <- function(df, x_var, fill_var) {
  if (!all(c(x_var, fill_var) %in% names(df))) return(NULL)
  d <- df %>%
    dplyr::count(.data[[x_var]], .data[[fill_var]], name = "n") %>%
    dplyr::mutate(
      xv = as.character(.data[[x_var]]),
      fv = as.character(.data[[fill_var]])
    ) %>%
    dplyr::filter(!is.na(xv), trimws(xv) != "", !is.na(fv), trimws(fv) != "")
  if (nrow(d) == 0) return(NULL)
  d
}

plot_metadata_rsv_count <- function(df, x_var, fill_var, title_txt, palette_base = kvalitativ_comb) {
  d <- build_metadata_counts(df, x_var, fill_var)
  if (is.null(d)) return(NULL)
  ggplot2::ggplot(d, ggplot2::aes(x = xv, y = n, fill = fv)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
    ggplot2::labs(title = title_txt, x = x_var, y = "Antall (n)", fill = fill_var) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

plot_metadata_rsv_pct <- function(df, x_var, fill_var, title_txt, palette_base = kvalitativ_comb) {
  d <- build_metadata_counts(df, x_var, fill_var)
  if (is.null(d)) return(NULL)
  d <- d %>% dplyr::group_by(xv) %>% dplyr::mutate(percent = 100 * n / sum(n)) %>% dplyr::ungroup()
  ggplot2::ggplot(d, ggplot2::aes(x = xv, y = percent, fill = fv)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
    ggplot2::scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    ggplot2::labs(title = title_txt, x = x_var, y = "Andel (%)", fill = fill_var) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

plot_metadata_flu_combined <- function(df, x_var, fill_var, title_txt, palette_base = kvalitativ_comb) {
  d <- build_metadata_counts(df, x_var, fill_var)
  if (is.null(d)) return(NULL)
  d <- d %>%
    dplyr::group_by(xv) %>%
    dplyr::mutate(pct = ifelse(sum(n) > 0, 100 * n / sum(n), 0)) %>%
    dplyr::ungroup()
  p1 <- ggplot2::ggplot(d, ggplot2::aes(x = xv, y = n, fill = fv)) +
    ggplot2::geom_col(position = "fill") +
    ggplot2::geom_text(
      ggplot2::aes(label = ifelse(pct >= 3, paste0("%=", sprintf("%.1f", pct)), "")),
      position = ggplot2::position_fill(vjust = 0.5),
      size = 2.8
    ) +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
    ggplot2::scale_y_continuous(labels = scales::percent_format()) +
    ggplot2::labs(title = NULL, x = NULL, y = "Andel (%)", fill = fill_var) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  p2 <- ggplot2::ggplot(d, ggplot2::aes(x = xv, y = n, fill = fv)) +
    ggplot2::geom_col() +
    ggplot2::geom_text(
      ggplot2::aes(label = ifelse(n > 0, paste0("n=", scales::comma(n)), "")),
      position = ggplot2::position_stack(vjust = 0.5),
      size = 2.8
    ) +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
    ggplot2::labs(title = NULL, x = NULL, y = "Antall (n)", fill = fill_var) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1), legend.position = "none")
  (p1 / p2) + patchwork::plot_annotation(title = title_txt)
}

plot_metadata_sc2_tessy_style <- function(df, x_var, fill_var, title_txt, palette_base = kvalitativ_comb, mode = c("pct", "count")) {
  mode <- match.arg(mode)
  d <- build_metadata_counts(df, x_var, fill_var)
  if (is.null(d)) return(NULL)
  d <- d %>% dplyr::group_by(xv) %>% dplyr::mutate(percent = 100 * n / sum(n), x_n = sum(n)) %>% dplyr::ungroup()
  order_df <- d %>% dplyr::distinct(xv, x_n) %>% dplyr::arrange(dplyr::desc(x_n), xv)
  d <- d %>% dplyr::mutate(xlab = factor(paste0(xv, " (n=", x_n, ")"), levels = paste0(order_df$xv, " (n=", order_df$x_n, ")")))
  if (mode == "pct") {
    ggplot2::ggplot(d, ggplot2::aes(x = xlab, y = percent, fill = fv)) +
      ggplot2::geom_col() +
      ggplot2::scale_y_continuous(labels = scales::percent_format(scale = 1)) +
      ggplot2::coord_cartesian(ylim = c(0, 100)) +
      ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
      ggplot2::labs(title = title_txt, x = x_var, y = "Andel (%)", fill = fill_var) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  } else {
    ggplot2::ggplot(d, ggplot2::aes(x = xlab, y = n, fill = fv)) +
      ggplot2::geom_col() +
      ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)) +
      ggplot2::labs(title = title_txt, x = x_var, y = "Antall (n)", fill = fill_var) +
      ggplot2::theme_minimal() +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  }
}

# SC2-guided helper: stacked percent + count plots by x-group and color-group.
build_group_distribution_plots <- function(
  df,
  x_col,
  color_col,
  date_col = NULL,
  start_date = NULL,
  end_date = NULL,
  x_label = "Gruppe",
  color_label = "Kategori",
  title_prefix = NULL,
  palette_base = kvalitativ_comb
) {
  if (!all(c(x_col, color_col) %in% names(df))) return(NULL)

  d <- df
  if (!is.null(date_col) && !is.null(start_date) && date_col %in% names(d)) {
    d <- d %>%
      dplyr::mutate(plot_date_window = as.Date(.data[[date_col]])) %>%
      dplyr::filter(!is.na(plot_date_window), plot_date_window >= as.Date(start_date))
    if (!is.null(end_date)) {
      d <- d %>% dplyr::filter(plot_date_window <= as.Date(end_date))
    }
  }

  d <- d %>%
    dplyr::transmute(
      group_plot = as.character(.data[[x_col]]),
      color_plot = as.character(.data[[color_col]])
    ) %>%
    dplyr::filter(
      !is.na(group_plot), trimws(group_plot) != "", group_plot != "IKKE_SATT",
      !is.na(color_plot), trimws(color_plot) != "", color_plot != "IKKE_SATT"
    )

  if (nrow(d) == 0) return(NULL)

  grouped_df <- d %>%
    dplyr::count(group_plot, color_plot, name = "n") %>%
    dplyr::group_by(group_plot) %>%
    dplyr::mutate(percent = (n / sum(n)) * 100) %>%
    dplyr::ungroup()

  x_labels_df <- grouped_df %>%
    dplyr::group_by(group_plot) %>%
    dplyr::summarise(group_n = sum(n), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(group_n), group_plot) %>%
    dplyr::mutate(group_label = paste0(group_plot, " (n=", scales::comma(group_n), ")"))

  grouped_df <- grouped_df %>%
    dplyr::left_join(x_labels_df, by = "group_plot") %>%
    dplyr::mutate(group_label = factor(group_label, levels = x_labels_df$group_label))

  title_base <- if (is.null(title_prefix)) paste0(color_label, " by ", x_label) else title_prefix

  p_pct <- ggplot2::ggplot(grouped_df, ggplot2::aes(x = group_label, y = percent, fill = color_plot)) +
    ggplot2::geom_col(position = "stack") +
    ggplot2::scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    ggplot2::coord_cartesian(ylim = c(0, 100)) +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(grouped_df$color_plot), palette_base)) +
    ggplot2::labs(
      title = NULL,
      x = paste0(x_label, " (n)"),
      y = "Andel (%)",
      fill = color_label
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  p_count <- ggplot2::ggplot(grouped_df, ggplot2::aes(x = group_label, y = n, fill = color_plot)) +
    ggplot2::geom_col(position = "stack") +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(grouped_df$color_plot), palette_base)) +
    ggplot2::labs(
      title = NULL,
      x = paste0(x_label, " (n)"),
      y = "Antall (n)",
      fill = color_label
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))

  list(percent_plot = p_pct, count_plot = p_count)
}

# Two-season pie comparison helper:
# left = previous season, right = current season.
build_two_season_pie_compare <- function(
  df,
  season_col = "season",
  category_col,
  previous_label,
  current_label,
  category_label = "Kategori",
  palette_base = kvalitativ_comb
) {
  if (is.null(df) || nrow(df) == 0) return(NULL)
  if (!all(c(season_col, category_col) %in% names(df))) return(NULL)

  build_one <- function(dat, season_lbl) {
    d <- dat %>%
      dplyr::filter(.data[[season_col]] == season_lbl) %>%
      dplyr::mutate(cat = as.character(.data[[category_col]])) %>%
      dplyr::mutate(cat = ifelse(is.na(cat) | trimws(cat) == "", "Ukjent", cat)) %>%
      dplyr::count(cat, name = "n")
    if (nrow(d) == 0) return(NULL)
    total_n <- sum(d$n, na.rm = TRUE)
    d <- d %>% dplyr::mutate(label_txt = paste0("N=", scales::comma(n)))

    ggplot2::ggplot(d, ggplot2::aes(x = "", y = n, fill = cat)) +
      ggplot2::geom_col(width = 1) +
      ggplot2::geom_text(
        ggplot2::aes(label = label_txt),
        position = ggplot2::position_stack(vjust = 0.5),
        size = 3
      ) +
      ggplot2::coord_polar(theta = "y") +
      ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$cat), palette_base)) +
      ggplot2::labs(
        title = paste0(season_lbl, " (N=", scales::comma(total_n), ")"),
        fill = category_label
      ) +
      ggplot2::theme_void()
  }

  p_prev <- build_one(df, previous_label)
  p_curr <- build_one(df, current_label)
  if (is.null(p_prev) || is.null(p_curr)) return(NULL)

  (p_prev | p_curr) + patchwork::plot_layout(ncol = 2, guides = "collect") &
    ggplot2::theme(legend.position = "right")
}

## Standardized geojson path resolver used by INF/SC2/RSV map blocks.
resolve_norway_geojson_path <- function() {
  local_shape_dir <- file.path("Source_files", "Norway_shapefile")
  if (!dir.exists(local_shape_dir)) return(NA_character_)

  shape_candidates <- list.files(
    path = local_shape_dir,
    pattern = "(?i)fylke.*geojson$",
    full.names = TRUE
  )
  if (length(shape_candidates) == 0) return(NA_character_)

  shape_info <- file.info(shape_candidates)
  newest_idx <- order(shape_info$mtime, decreasing = TRUE)[1]
  normalizePath(shape_candidates[newest_idx], winslash = "/", mustWork = FALSE)
}

load_norway_fylke_sf <- function() {
  geojson_path <- resolve_norway_geojson_path()
  if (is.na(geojson_path) || !file.exists(geojson_path)) {
    stop("Missing Norway fylke GeoJSON under Source_files/Norway_shapefile")
  }

  fylke_sf <- sf::read_sf(geojson_path)
  name_col <- intersect(
    c("fylkesnavn", "fylke_navn", "navn", "name"),
    names(fylke_sf)
  )[1]
  if (is.na(name_col)) {
    stop("Could not identify county name column in Norway fylke GeoJSON")
  }

  fylke_sf |>
    dplyr::mutate(
      fylke_name_original = as.character(.data[[name_col]]),
      fylke_name_std = normalize_fylke_value(fylke_name_original),
      fylke_name_map = unname(
        fylke_to_current_map_dictionary[
          normalize_geography_key(fylke_name_std)
        ]
      ),
      fylke_name_map = ifelse(
        is.na(fylke_name_map) | trimws(fylke_name_map) == "",
        fylke_name_std,
        fylke_name_map
      ),
      landsdel_name = derive_landsdel_from_fylke(fylke_name_std)
    )
}

build_fylke_map_plot_shared <- function(
  df,
  fylke_col = "pasient_fylke_name",
  title = "Map: Fylke fordeling",
  shape_path = NULL,
  fill_palette = kvantitativ_b2,
  ...
) {
  if (is.null(df) || nrow(df) == 0 || !fylke_col %in% names(df)) return(NULL)

  fylke_map_col <- if (paste0(fylke_col, "_map") %in% names(df)) {
    paste0(fylke_col, "_map")
  } else {
    fylke_col
  }

  count_df <- df |>
    dplyr::transmute(
      fylke_name_map = if (fylke_map_col == fylke_col) {
        normalize_fylke_value(.data[[fylke_col]])
      } else {
        as.character(.data[[fylke_map_col]])
      }
    ) |>
    dplyr::mutate(
      fylke_name_map = ifelse(
        is.na(fylke_name_map) | trimws(fylke_name_map) == "",
        "Ukjent",
        fylke_name_map
      )
    ) |>
    dplyr::filter(fylke_name_map != "Ukjent") |>
    dplyr::count(fylke_name_map, name = "n_map")

  norway_sf <- load_norway_fylke_sf() |>
    dplyr::left_join(count_df, by = "fylke_name_map") |>
    dplyr::mutate(n_map = dplyr::coalesce(n_map, 0L))

  label_pts <- sf::st_point_on_surface(sf::st_geometry(norway_sf))
  label_xy <- sf::st_coordinates(label_pts)
  label_df <- norway_sf |>
    sf::st_drop_geometry() |>
    dplyr::mutate(X = label_xy[, "X"], Y = label_xy[, "Y"]) |>
    dplyr::filter(n_map > 0) |>
    dplyr::mutate(label_txt = paste0("n=", scales::comma(n_map)))

  ggplot2::ggplot(norway_sf) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = n_map),
      color = "white",
      linewidth = 0.2
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = X, y = Y, label = label_txt),
      size = 2.8
    ) +
    ggplot2::scale_fill_gradient(
      low = fill_palette[2],
      high = fill_palette[min(length(fill_palette), 8)],
      na.value = "grey95"
    ) +
    ggplot2::labs(title = title, fill = "Antall (n)") +
    ggplot2::theme_void()
}

build_landsdel_map_plot_shared <- function(
  df,
  fylke_col = "pasient_fylke_name",
  landsdel_col = "pasient_landsdel",
  title = "Map: Landsdel fordeling",
  shape_path = NULL,
  fill_palette = NULL,
  ...
) {
  if (is.null(df) || nrow(df) == 0 || !fylke_col %in% names(df)) return(NULL)

  fylke_map_col <- if (paste0(fylke_col, "_map") %in% names(df)) {
    paste0(fylke_col, "_map")
  } else {
    fylke_col
  }

  county_df <- df |>
    dplyr::transmute(
      fylke_name_map = if (fylke_map_col == fylke_col) {
        normalize_fylke_value(.data[[fylke_col]])
      } else {
        as.character(.data[[fylke_map_col]])
      },
      landsdel_name = derive_landsdel_from_fylke(.data[[fylke_col]])
    ) |>
    dplyr::mutate(
      fylke_name_map = ifelse(
        is.na(fylke_name_map) | trimws(fylke_name_map) == "",
        "Ukjent",
        fylke_name_map
      ),
      landsdel_name = ifelse(
        is.na(landsdel_name) | trimws(landsdel_name) == "",
        "Ukjent",
        landsdel_name
      )
    ) |>
    dplyr::filter(fylke_name_map != "Ukjent")

  count_df <- county_df |>
    dplyr::count(fylke_name_map, landsdel_name, name = "n_map") |>
    dplyr::group_by(fylke_name_map) |>
    dplyr::slice_max(order_by = n_map, n = 1, with_ties = FALSE) |>
    dplyr::ungroup()

  norway_sf <- load_norway_fylke_sf() |>
    dplyr::left_join(count_df, by = "fylke_name_map")
  if (!"landsdel_name" %in% names(norway_sf)) {
    norway_sf$landsdel_name <- NA_character_
  }
  if (!"n_map" %in% names(norway_sf)) {
    norway_sf$n_map <- 0L
  }
  norway_sf <- norway_sf |>
    dplyr::mutate(
      landsdel_name = ifelse(
        is.na(.data$landsdel_name) | trimws(.data$landsdel_name) == "",
        "Ukjent",
        .data$landsdel_name
      ),
      n_map = dplyr::coalesce(n_map, 0L)
    )

  label_df <- norway_sf |>
    dplyr::filter(.data$landsdel_name != "Ukjent") |>
    dplyr::group_by(.data$landsdel_name) |>
    dplyr::summarise(
      n_map = sum(.data$n_map, na.rm = TRUE),
      geometry = sf::st_union(geometry),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n_map > 0) |>
    dplyr::mutate(
      geometry = sf::st_point_on_surface(geometry),
      label_txt = paste0("n=", scales::comma(.data$n_map))
    )

  label_xy <- sf::st_coordinates(sf::st_geometry(label_df))
  label_df <- label_df |>
    sf::st_drop_geometry() |>
    dplyr::mutate(X = label_xy[, 1], Y = label_xy[, 2])

  ggplot2::ggplot(norway_sf) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = landsdel_name),
      color = "white",
      linewidth = 0.2
    ) +
    ggplot2::geom_text(
      data = label_df,
      ggplot2::aes(x = X, y = Y, label = label_txt),
      size = 2.8
    ) +
    ggplot2::scale_fill_manual(
      values = c(
        "Sørlandet" = kvalitativ_a[1],
        "Vestlandet" = kvalitativ_b[1],
        "Østlandet" = kvalitativ_b[2],
        "Midt-Norge" = kvantitativ_gu1[5],
        "Nord-Norge" = kvantitativ_r1[5],
        "Ukjent" = "grey85"
      )
    ) +
    ggplot2::labs(title = title, fill = "Landsdel") +
    ggplot2::theme_void()
}

## Numeric outlier scan (IQR-based), including numeric columns and
## numeric-like QC fields (e.g., PCR/CT/age/WL/ID/coverage-like names).
numeric_outlier_scan_table <- function(
  df,
  include_name_regex = "(pcr|ct|age|alder|wl|id|coverage|cov)",
  min_n = 10L
) {
  if (is.null(df) || nrow(df) == 0) return(data.frame())

  name_hits <- grepl(include_name_regex, names(df), ignore.case = TRUE)
  numeric_hits <- vapply(df, is.numeric, logical(1))
  candidate_cols <- names(df)[name_hits | numeric_hits]
  candidate_cols <- unique(candidate_cols)
  if (length(candidate_cols) == 0) return(data.frame())

  outlier_scan <- lapply(candidate_cols, function(col_name) {
    raw_x <- df[[col_name]]
    x <- suppressWarnings(as.numeric(as.character(raw_x)))
    x <- x[!is.na(x) & is.finite(x)]
    if (length(x) < as.integer(min_n)) return(NULL)

    q1 <- as.numeric(stats::quantile(x, 0.25, na.rm = TRUE))
    q3 <- as.numeric(stats::quantile(x, 0.75, na.rm = TRUE))
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
      median = stats::median(x, na.rm = TRUE),
      p75 = q3,
      max = max(x, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }) %>%
    dplyr::bind_rows()

  if (nrow(outlier_scan) == 0) return(data.frame())
  outlier_scan %>%
    dplyr::arrange(dplyr::desc(outlier_pct), dplyr::desc(outlier_n), column_name)
}

## CT plot helpers (SC2-style monthly box+jitter, colored by subclade/clade)
build_ct_month_plot <- function(df, date_col, ct_col, color_col, title_txt, subtitle_txt = NULL, color_label = "Subclade") {
  if (!all(c(date_col, ct_col, color_col) %in% names(df))) return(NULL)
  d <- df %>%
    dplyr::transmute(
      month_date = as.Date(.data[[date_col]]),
      ct_value = suppressWarnings(as.numeric(.data[[ct_col]])),
      color_group = ifelse(is.na(.data[[color_col]]) | trimws(as.character(.data[[color_col]])) == "", "Ukjent", as.character(.data[[color_col]]))
    ) %>%
    dplyr::filter(!is.na(month_date), !is.na(ct_value), is.finite(ct_value))
  if (nrow(d) == 0) return(NULL)

  ggplot2::ggplot(
    d,
    ggplot2::aes(
      x = month_date,
      y = ct_value,
      color = color_group,
      group = interaction(month_date, color_group)
    )
  ) +
    ggplot2::geom_boxplot(outlier.shape = NA, alpha = 0.35, position = ggplot2::position_dodge(width = 20)) +
    ggplot2::geom_jitter(alpha = 0.25, size = 0.9, width = 4) +
    ggplot2::scale_color_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$color_group), kvalitativ_comb)) +
    ggplot2::scale_x_date(labels = format_month_label, date_breaks = "1 month") +
    ggplot2::scale_y_continuous(limits = c(0, 40), breaks = seq(0, 40, 5), expand = c(0, 0)) +
    ggplot2::labs(
      title = title_txt,
      subtitle = subtitle_txt,
      x = "MÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¥ned",
      y = "Ct-verdi",
      color = color_label
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

prepare_run_qc_df <- function(df, run_col, cov_col, qc_col = NULL, virus_col = NULL, color_col = NULL) {
  needed <- c(run_col, cov_col)
  if (!all(needed %in% names(df))) return(NULL)
  d <- df %>%
    dplyr::mutate(
      run_id = as.character(.data[[run_col]]),
      run_id = ifelse(is.na(run_id) | trimws(run_id) == "", "Ukjent", run_id),
      cov_num = suppressWarnings(as.numeric(as.character(.data[[cov_col]]))),
      cov_norm = ifelse(!is.na(cov_num) & cov_num > 1.5, cov_num / 100, cov_num),
      qc_status = if (!is.null(qc_col) && qc_col %in% names(.)) ifelse(is.na(.data[[qc_col]]) | trimws(as.character(.data[[qc_col]])) == "", "Ukjent", as.character(.data[[qc_col]])) else "Ukjent",
      virus_group = if (!is.null(virus_col) && virus_col %in% names(.)) ifelse(is.na(.data[[virus_col]]) | trimws(as.character(.data[[virus_col]])) == "", "Ukjent", as.character(.data[[virus_col]])) else "Ukjent",
      color_group = if (!is.null(color_col) && color_col %in% names(.)) ifelse(is.na(.data[[color_col]]) | trimws(as.character(.data[[color_col]])) == "", "Ukjent", as.character(.data[[color_col]])) else "Ukjent"
    ) %>%
    dplyr::filter(run_id != "Ukjent")
  if (nrow(d) == 0) return(NULL)
  d
}

run_qc_summary_table <- function(run_qc_df) {
  if (is.null(run_qc_df) || nrow(run_qc_df) == 0) return(NULL)
  run_qc_df %>%
    dplyr::group_by(run_id) %>%
    dplyr::summarise(
      n_samples = dplyr::n(),
      mean_cov = round(mean(cov_norm, na.rm = TRUE), 3),
      median_cov = round(median(cov_norm, na.rm = TRUE), 3),
      p10_cov = round(as.numeric(stats::quantile(cov_norm, probs = 0.10, na.rm = TRUE)), 3),
      p90_cov = round(as.numeric(stats::quantile(cov_norm, probs = 0.90, na.rm = TRUE)), 3),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(n_samples), dplyr::desc(median_cov), run_id)
}

plot_run_qc_by_run_colorgroup <- function(run_qc_df, title_txt, color_label = "Subclade") {
  if (is.null(run_qc_df) || nrow(run_qc_df) == 0) return(NULL)
  d <- run_qc_df %>% dplyr::count(run_id, color_group, name = "n")
  if (nrow(d) == 0) return(NULL)
  ggplot2::ggplot(d, ggplot2::aes(x = stats::reorder(run_id, n, sum), y = n, fill = color_group)) +
    ggplot2::geom_col() +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$color_group), kvalitativ_comb)) +
    ggplot2::labs(title = title_txt, x = "NGS run id", y = "Antall (n)", fill = color_label) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

plot_run_cov_by_run_colorgroup <- function(run_qc_df, title_txt, color_label = "Subclade") {
  if (is.null(run_qc_df) || nrow(run_qc_df) == 0) return(NULL)
  d <- run_qc_df %>% dplyr::filter(!is.na(cov_norm))
  if (nrow(d) == 0) return(NULL)
  ggplot2::ggplot(d, ggplot2::aes(x = run_id, y = cov_norm, color = color_group)) +
    ggplot2::geom_boxplot(outlier.shape = NA, alpha = 0.35, position = ggplot2::position_dodge(width = 0.8)) +
    ggplot2::geom_jitter(alpha = 0.25, size = 0.8, width = 0.15) +
    ggplot2::scale_color_manual(values = fhi_discrete_palette(dplyr::n_distinct(d$color_group), kvalitativ_comb)) +
    ggplot2::labs(title = title_txt, x = "NGS run id", y = "Normalisert dekning (0-1)", color = color_label) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

sanitize_excel_sheet_name <- function(x, max_length = 31) {
  clean <- gsub("[\\[\\]\\*\\?/\\\\:]", "_", x)
  clean <- gsub("^'+|'+$", "", clean)
  ifelse(nchar(clean) > max_length, substr(clean, 1, max_length), clean)
}
