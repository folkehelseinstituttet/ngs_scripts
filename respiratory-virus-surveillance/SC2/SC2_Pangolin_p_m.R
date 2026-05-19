export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Pangolin Classification per Month", location = ph_location_type(type = "title"))

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
  labs(y = "Andel av Sekvenser (%)", x = "", fill = "SARS-CoV-2 Nomenklatur") +
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
  labs(y = "Antall av Sekvenser (n)", x = "") +
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
print(combined_plotwp)

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
  labs(y = "Andel av Sekvenser (%)", x = "", fill = "Collapsed Pangolin Name") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_blank())

# Second plot for last 12 months sequence counts
grpangomtp_numbers_12mo <- ggplot(monthcounstat12mo, aes(x = Sampledate, y = TotalSeq)) +
  geom_bar(stat = "identity") +
  labs(y = "Antall av Sekvenser (n)", x = "") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(
    angle = 90,
    hjust = 1,
    vjust = 0.5
  ))

# Combine last 12 months plots
combined_plot_12mo <- grpangomtp_12mo / grpangomtp_numbers_12mo +
  plot_layout(guides = "collect", heights = c(3, 1))
print(combined_plot_12mo)

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
        "undervarianter de siste seks månedene"
      ),
      x = "",
      y = "Antall sekvenser (n)",
      fill = "Pangolin Nomenklature"
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
        "undervarianter de siste seks månedene"
      ),
      x = "",
      y = "Andel av alle SARS-CoV-2 sekvenser (%)",
      fill = "Pangolin Nomenklature"
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
print(SC2_6mopangopivot)

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

