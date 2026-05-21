build_meta_count_data <- function(df, x_var, fill_var, count_var = NULL) {
  if (!all(c(x_var, fill_var) %in% names(df))) {
    return(NULL)
  }

  d <- if (is.null(count_var)) {
    df %>%
      dplyr::count(.data[[x_var]], .data[[fill_var]], name = "n")
  } else {
    if (!(count_var %in% names(df))) return(NULL)
    df %>%
      dplyr::group_by(.data[[x_var]], .data[[fill_var]]) %>%
      dplyr::summarise(n = sum(.data[[count_var]], na.rm = TRUE), .groups = "drop")
  }

  d <- d %>%
    dplyr::mutate(
      xv = as.character(.data[[x_var]]),
      fv = as.character(.data[[fill_var]])
    ) %>%
    dplyr::filter(!is.na(xv), trimws(xv) != "", !is.na(fv), trimws(fv) != "")

  if (nrow(d) == 0) {
    return(NULL)
  }
  d1
}

meta_fill_scale <- function(d, palette_base = NULL) {
  if (is.null(palette_base)) {
    return(ggplot2::scale_fill_discrete())
  }
  ggplot2::scale_fill_manual(
    values = fhi_discrete_palette(dplyr::n_distinct(d$fv), palette_base)
  )
}

plot_meta_stacked_count_shared <- function(df, x_var, fill_var, title_txt, x_label, fill_label, palette_base = NULL, count_var = NULL, label_x_with_n = FALSE) {
  d <- build_meta_count_data(df, x_var, fill_var, count_var = count_var)
  if (is.null(d)) return(NULL)
  if (label_x_with_n) {
    x_labels <- d %>%
      dplyr::group_by(xv) %>%
      dplyr::summarise(x_total_n = sum(n), .groups = "drop") %>%
      dplyr::arrange(dplyr::desc(x_total_n), xv) %>%
      dplyr::mutate(x_label = paste0(xv, " (n=", x_total_n, ")"))
    d <- d %>%
      dplyr::left_join(x_labels, by = "xv") %>%
      dplyr::mutate(x_plot = factor(x_label, levels = x_labels$x_label))
  } else {
    d <- d %>% dplyr::mutate(x_plot = xv)
  }

  ggplot2::ggplot(d, ggplot2::aes(x = x_plot, y = n, fill = fv)) +
    ggplot2::geom_col() +
    meta_fill_scale(d, palette_base = palette_base) +
    ggplot2::labs(title = title_txt, x = x_label, y = "Antall (n)", fill = fill_label) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

plot_meta_stacked_pct_shared <- function(df, x_var, fill_var, title_txt, x_label, fill_label, palette_base = NULL, count_var = NULL, label_x_with_n = FALSE) {
  d <- build_meta_count_data(df, x_var, fill_var, count_var = count_var)
  if (is.null(d)) return(NULL)

  d <- d %>%
    dplyr::group_by(xv) %>%
    dplyr::mutate(percent = 100 * n / sum(n)) %>%
    dplyr::ungroup()

  if (label_x_with_n) {
    x_labels <- d %>%
      dplyr::group_by(xv) %>%
      dplyr::summarise(x_total_n = sum(n), .groups = "drop") %>%
      dplyr::arrange(dplyr::desc(x_total_n), xv) %>%
      dplyr::mutate(x_label = paste0(xv, " (n=", x_total_n, ")"))
    d <- d %>%
      dplyr::left_join(x_labels, by = "xv") %>%
      dplyr::mutate(x_plot = factor(x_label, levels = x_labels$x_label))
  } else {
    d <- d %>% dplyr::mutate(x_plot = xv)
  }

  ggplot2::ggplot(d, ggplot2::aes(x = x_plot, y = percent, fill = fv)) +
    ggplot2::geom_col() +
    meta_fill_scale(d, palette_base = palette_base) +
    ggplot2::scale_y_continuous(labels = scales::percent_format(scale = 1)) +
    ggplot2::labs(title = title_txt, x = x_label, y = "Andel (%)", fill = fill_label) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

plot_meta_count_pct_combined_shared <- function(df, x_var, fill_var, title_txt, x_label, fill_label, palette_base = NULL, count_var = NULL, label_x_with_n = FALSE) {
  p_pct <- plot_meta_stacked_pct_shared(df, x_var, fill_var, paste0(title_txt, " (andel)"), x_label, fill_label, palette_base = palette_base, count_var = count_var, label_x_with_n = label_x_with_n)
  p_n <- plot_meta_stacked_count_shared(df, x_var, fill_var, paste0(title_txt, " (antall)"), x_label, fill_label, palette_base = palette_base, count_var = count_var, label_x_with_n = label_x_with_n)
  if (is.null(p_pct) || is.null(p_n)) return(NULL)
  p_pct + p_n + patchwork::plot_layout(ncol = 1, heights = c(1, 1), guides = "collect") &
    ggplot2::theme(legend.position = "right")
}

normalize_map_key_shared <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x <- tolower(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT")
  x <- gsub("\\bfylke\\b", "", x)
  x <- gsub("\\bcounty\\b", "", x)
  x <- gsub("[^a-z0-9]+", "", x)
  x
}

canonical_fylke_key_shared <- function(x) {
  k <- normalize_map_key_shared(x)
  dplyr::case_when(
    grepl("^troms", k) ~ "troms",
    grepl("^finnmark", k) ~ "finnmark",
    grepl("^nordland", k) ~ "nordland",
    grepl("^trondelag", k) ~ "trondelag",
    grepl("^moreogromsdal", k) ~ "moreogromsdal",
    grepl("^ostfold", k) ~ "ostfold",
    k %in% c("troms", "tromsfinnmark", "tromsogfinnmark") ~ "troms",
    k %in% c("finnmark") ~ "finnmark",
    k %in% c("trondelag", "sortrondelag", "nordtrondelag") ~ "trondelag",
    k %in% c("innlandet", "hedmark", "oppland") ~ "innlandet",
    k %in% c("ostfold", "akershus", "buskerud") ~ k,
    k %in% c("vestfold", "telemark") ~ k,
    k %in% c("oslo", "innlandet", "rogaland", "vestland", "moreogromsdal", "nordland", "agder") ~ k,
    TRUE ~ k
  )
}

align_fylke_keys_to_shape_shared <- function(fylke_keys, shape_keys) {
  out <- as.character(fylke_keys)
  shape_keys <- unique(as.character(shape_keys))

  # If the shape uses merged Troms/Finnmark, remap split data keys so joins work.
  if ("tromsogfinnmark" %in% shape_keys) {
    out[out %in% c("troms", "finnmark")] <- "tromsogfinnmark"
  }

  # If the shape uses merged Vestfold/Telemark, remap split data keys so joins work.
  if ("vestfoldogtelemark" %in% shape_keys) {
    out[out %in% c("vestfold", "telemark")] <- "vestfoldogtelemark"
  }

  out
}

landsdel_from_fylke_key_shared <- function(fylke_key) {
  dplyr::case_when(
    fylke_key %in% c("agder") ~ "sorlandet",
    fylke_key %in% c("rogaland", "vestland", "moreogromsdal") ~ "vestlandet",
    fylke_key %in% c("trondelag") ~ "midtnorge",
    fylke_key %in% c("nordland", "troms", "finnmark") ~ "nordnorge",
    fylke_key %in% c("oslo", "akershus", "ostfold", "buskerud", "innlandet", "vestfold", "telemark") ~ "ostlandet",
    TRUE ~ NA_character_
  )
}

landsdel_label_from_key_shared <- function(landsdel_key) {
  dplyr::case_when(
    landsdel_key == "sorlandet" ~ "Sørlandet",
    landsdel_key == "vestlandet" ~ "Vestlandet",
    landsdel_key == "midtnorge" ~ "Midt-Norge",
    landsdel_key == "nordnorge" ~ "Nord-Norge",
    landsdel_key == "ostlandet" ~ "Østlandet",
    TRUE ~ NA_character_
  )
}

build_fylke_map_plot_shared <- function(df, fylke_col = "pasient_fylke_name", shape_path, fill_palette) {
  if (!requireNamespace("sf", quietly = TRUE) || !file.exists(shape_path) || !(fylke_col %in% names(df))) {
    return(NULL)
  }
  shape_sf <- tryCatch({
    lyr <- sf::st_layers(shape_path)$name
    sf::st_read(shape_path, layer = lyr[1], quiet = TRUE)
  }, error = function(e) NULL)
  if (is.null(shape_sf) || !all(c("fylkesnavn", "geometry") %in% names(shape_sf))) return(NULL)

  shape_keys <- shape_sf %>%
    dplyr::mutate(
      fylke_map = canonical_fylke_key_shared(trimws(as.character(fylkesnavn)))
    ) %>%
    dplyr::pull(fylke_map)

  df_map <- df %>%
    dplyr::mutate(
      fylke_map = canonical_fylke_key_shared(.data[[fylke_col]]),
      fylke_map = align_fylke_keys_to_shape_shared(fylke_map, shape_keys)
    )

  fylke_counts <- df_map %>%
    dplyr::transmute(fylke_map = as.character(fylke_map)) %>%
    dplyr::filter(!is.na(fylke_map), fylke_map != "", fylke_map != "ukjent") %>%
    dplyr::count(fylke_map, name = "n")

  map_df <- shape_sf %>%
    dplyr::mutate(
      fylke = trimws(as.character(fylkesnavn)),
      fylke_map = canonical_fylke_key_shared(fylke)
    ) %>%
    dplyr::left_join(fylke_counts, by = "fylke_map") %>%
    dplyr::mutate(n = ifelse(is.na(n), 0, n))

  ggplot2::ggplot(map_df) +
    ggplot2::geom_sf(ggplot2::aes(fill = n), color = "white", linewidth = 0.2) +
    ggplot2::scale_fill_gradientn(colours = fill_palette, name = "Antall\nprøver", labels = scales::comma) +
    ggplot2::labs(title = "Prøver per fylke", subtitle = paste0("Basert på ", fylke_col)) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), axis.text = ggplot2::element_blank(), axis.title = ggplot2::element_blank())
}

build_landsdel_map_plot_shared <- function(df, fylke_col = "pasient_fylke_name", landsdel_col = "pasient_landsdel", shape_path, palette_base) {
  if (!requireNamespace("sf", quietly = TRUE) || !file.exists(shape_path) || !all(c(fylke_col, landsdel_col) %in% names(df))) {
    return(NULL)
  }
  shape_sf <- tryCatch({
    lyr <- sf::st_layers(shape_path)$name
    sf::st_read(shape_path, layer = lyr[1], quiet = TRUE)
  }, error = function(e) NULL)
  if (is.null(shape_sf) || !all(c("fylkesnavn", "geometry") %in% names(shape_sf))) return(NULL)
  shape_sf <- sf::st_make_valid(shape_sf)

  shape_keys <- shape_sf %>%
    dplyr::mutate(
      fylke_map = canonical_fylke_key_shared(trimws(as.character(fylkesnavn)))
    ) %>%
    dplyr::pull(fylke_map)

  df_map <- df %>%
    dplyr::mutate(
      fylke_map = canonical_fylke_key_shared(.data[[fylke_col]]),
      fylke_map = align_fylke_keys_to_shape_shared(fylke_map, shape_keys),
      landsdel_map = landsdel_from_fylke_key_shared(fylke_map),
      landsdel_map_raw = normalize_map_key_shared(.data[[landsdel_col]]),
      landsdel_label_raw = trimws(as.character(.data[[landsdel_col]]))
    ) %>%
    dplyr::mutate(
      landsdel_map = dplyr::if_else(
        is.na(landsdel_map) | landsdel_map == "",
        landsdel_map_raw,
        landsdel_map
      ),
      landsdel_label = landsdel_label_from_key_shared(landsdel_map),
      landsdel_label = dplyr::if_else(
        is.na(landsdel_label) | landsdel_label == "",
        landsdel_label_raw,
        landsdel_label
      )
    )

  fylke_landsdel_lookup <- df_map %>%
    dplyr::filter(!is.na(fylke_map), fylke_map != "", fylke_map != "ukjent", !is.na(landsdel_map), landsdel_map != "", landsdel_map != "ukjent") %>%
    dplyr::count(fylke_map, landsdel_map, landsdel_label, name = "n") %>%
    dplyr::group_by(fylke_map) %>%
    dplyr::slice_max(order_by = n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup() %>%
    dplyr::select(fylke_map, landsdel_map, landsdel_label)

  landsdel_counts <- df_map %>%
    dplyr::transmute(
      landsdel_map = as.character(landsdel_map),
      landsdel_label = as.character(landsdel_label)
    ) %>%
    dplyr::filter(!is.na(landsdel_map), landsdel_map != "", landsdel_map != "ukjent", !is.na(landsdel_label), landsdel_label != "", tolower(landsdel_label) != "ukjent") %>%
    dplyr::count(landsdel_map, landsdel_label, name = "n_landsdel")

  shape_for_union <- shape_sf
  if (isTRUE(sf::st_is_longlat(shape_for_union))) {
    shape_for_union <- sf::st_transform(shape_for_union, 3857)
  }

  landsdel_sf <- shape_for_union %>%
    dplyr::mutate(
      fylke = trimws(as.character(fylkesnavn)),
      fylke_map = canonical_fylke_key_shared(fylke)
    ) %>%
    dplyr::left_join(fylke_landsdel_lookup, by = "fylke_map") %>%
    dplyr::filter(!is.na(landsdel_map), landsdel_map != "") %>%
    dplyr::mutate(geometry = sf::st_make_valid(geometry)) %>%
    dplyr::group_by(landsdel_map, landsdel_label) %>%
    dplyr::summarise(geometry = sf::st_union(geometry), .groups = "drop") %>%
    dplyr::mutate(geometry = sf::st_make_valid(geometry)) %>%
    dplyr::left_join(landsdel_counts, by = c("landsdel_map", "landsdel_label")) %>%
    dplyr::mutate(n_landsdel = ifelse(is.na(n_landsdel), 0, n_landsdel))
  if (nrow(landsdel_sf) == 0) return(NULL)

  label_points <- sf::st_point_on_surface(landsdel_sf)
  label_coords <- sf::st_coordinates(label_points)
  label_df <- landsdel_sf %>%
    sf::st_drop_geometry() %>%
    dplyr::mutate(
      x = label_coords[, 1],
      y = label_coords[, 2],
      label_txt = paste0(landsdel_label, "\n(n=", scales::comma(n_landsdel), ")")
    )

  ggplot2::ggplot() +
    ggplot2::geom_sf(data = shape_for_union, fill = "grey92", color = "white", linewidth = 0.2) +
    ggplot2::geom_sf(data = landsdel_sf, ggplot2::aes(fill = landsdel_label), color = "white", linewidth = 0.3) +
    ggplot2::geom_text(data = label_df, ggplot2::aes(x = x, y = y, label = label_txt), size = 3) +
    ggplot2::scale_fill_manual(values = fhi_discrete_palette(dplyr::n_distinct(landsdel_sf$landsdel_label), palette_base)) +
    ggplot2::labs(title = "Prøver per landsdel", subtitle = paste0("Aggregert fra ", fylke_col, " + ", landsdel_col)) +
    ggplot2::theme_minimal() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), axis.text = ggplot2::element_blank(), axis.title = ggplot2::element_blank())
}
