# Shared report helpers for Influenza and SARS-CoV-2 analyses.

# -------------------------
# FHI color palettes
# -------------------------
kvalitativ_a <- c("#ec7c73", "#40436d", "#61d2b2", "#a93c38", "#f9dc8c", "#7176c9", "#e0f0f7", "#09181f")
kvalitativ_b <- c("#65a9c5", "#2a6a82", "#f0af5e", "#fee9e6", "#179463", "#c8e1ec")
kvalitativ_comb <- c("#ec7c73", "#40436d", "#61d2b2", "#a93c38", "#f9dc8c", "#7176c9", "#e0f0f7", "#09181f", "#65a9c5", "#2a6a82", "#f0af5e", "#fee9e6", "#179463", "#c8e1ec")
kvantitativ_b2 <- c("#f2fafe", "#e0f0f7", "#c8e1ec", "#8fc5dc", "#65a9c5", "#4089a7", "#2a6a82", "#234e5f", "#16323d", "#09181f")
kvantitativ_b1 <- c("#fafbff", "#ebedff", "#d8ddff", "#b0b8fa", "#8e96f3", "#7176c9", "#595d9d", "#40436d", "#292b47", "#131428")
kvantitativ_r1 <- c("#fff6f5", "#fee9e6", "#ffd2cc", "#fda49b", "#ec7c73", "#d74b46", "#a93c38", "#7b2623", "#4f1a17", "#2c0807")
kvantitativ_gu1 <- c("#fff7ee", "#faead5", "#f9dc8c", "#f0af5e", "#d39244", "#ac763a", "#83592d", "#5f4122", "#3c2917", "#221305")
kvantitativ_gr1 <- c("#f2fbfa", "#d9f4ed", "#b5e8d9", "#61d2b2", "#00b782", "#179463", "#396e4d", "#2d4f35", "#203323", "#0d1b0a")
divergerende_3_1_3 <- c("#7b2623", "#d74b46", "#fda49b", "#ffffff", "#8fc5dc", "#4089a7", "#234e5f")
divergerende_6_1_6 <- c("#7b2623", "#a93c38", "#d74b46", "#ec7c73", "#fda49b", "#ffd2cc", "#ffffff", "#c8e1ec", "#8fc5dc", "#65a9c5", "#4089a7", "#2a6a82", "#234e5f")
sc2_palette <- kvalitativ_comb

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

# -------------------------
# Label/date helpers
# -------------------------
format_month_label <- function(x) {
  tolower(format(as.Date(x), "%b-%Y"))
}

parse_month_label <- function(x) {
  as.Date(paste0("01-", x), format = "%d-%b-%Y")
}

fhi_discrete_palette <- function(n, palette = kvalitativ_comb) {
  if (n <= length(palette)) {
    palette[seq_len(n)]
  } else {
    grDevices::colorRampPalette(palette)(n)
  }
}

# -------------------------
# PowerPoint helpers
# -------------------------
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

sanitize_excel_sheet_name <- function(x, max_length = 31) {
  clean <- gsub("[\\[\\]\\*\\?/\\\\:]", "_", x)
  clean <- gsub("^'+|'+$", "", clean)
  ifelse(nchar(clean) > max_length, substr(clean, 1, max_length), clean)
}
