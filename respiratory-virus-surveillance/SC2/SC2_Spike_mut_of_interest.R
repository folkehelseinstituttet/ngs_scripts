export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Spike Mutation of Interest", location = ph_location_type(type = "title"))

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

# Dot plot with month-year on x-axis and number of mutations on y-axis, colored by Tessy
mutfr_monthly <- mutfr %>%
  group_by(date, Tessy_group, n_mut) %>%
  summarise(n = sum(n), .groups = "drop")

grnmutfr <- ggplot(mutfr_monthly, aes(x = date, y = n_mut, color = Tessy_group, size = n)) +
  geom_point(alpha = 0.85, position = position_jitter(width = 2, height = 0.08, seed = 2526)) +
  labs(
    title = "Punktplott av mutasjoner per type og måned-år",
    x = "Måned-år",
    y = "Number of Mutations",
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

print(grnmutfr)

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
    title = "Varmekart av mutasjonskombinasjoner per måned (siste 6 måneder)",
    x = "Måned-år",
    y = "Mutations or Combinations",
    fill = "Andel (%)"
  ) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

print(hmapmut)

export_graph <- save_plot(hmapmut, "Varmekart av mutasjonskombinasjoner per måned (siste 6 måneder)", export_graph)

# Pangolin nomenclature per mutation combination
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
      title = paste("Pangolin Nomenclature per Combination of Spike Mutations for", combination),
      x = "Måned-år", 
      y = "Antall sekvenser (n)", 
      fill = "Pangolin Nomenklature"
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
      title = paste("Andel av Pangolin Nomenclature per Combination of Spike Mutations for", combination),
      x = "Måned-år", 
      y = "Andel av alle SARS-CoV-2 sekvenser (%)", 
      fill = "Pangolin Nomenklature"
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

