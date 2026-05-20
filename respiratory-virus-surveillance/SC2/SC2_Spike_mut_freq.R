export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Spike Mutation Frequency", location = ph_location_type(type = "title"))

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

# --- Count Mutations per Week by Pangolin Variant ---

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
    ylab("Andel av sekvenser") +
    xlab("Måned") +
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
  
  print(tm)  # Print tree map for testing
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
      TRUE                             ~ "Other"
    ))

  domainmutcp <- Linmut %>%
    mutate(
      Tessy_group = as.character(Tessy),
      Tessy_group = ifelse(is.na(Tessy_group) | trimws(Tessy_group) == "", "Unknown", Tessy_group)
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
        size = "Count (n)"
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
  


