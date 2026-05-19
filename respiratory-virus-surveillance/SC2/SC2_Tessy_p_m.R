export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme") %>%
  ph_with(value = "Tessy Classification per Month", location = ph_location_type(type = "title"))

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
    labs(y = "Andel av Sekvenser (%)", x = "", fill = "Tessy Reporting category") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

# Create the second bar plot with numbers from the "TotalSeq" column
grtessyp_numbers <- ggplot(monthcount, aes(x = Sampledate, y = TotalSeq)) +
  geom_bar(stat = "identity") +
  labs(y = "Antall av Sekvenser (n)", x = "") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))

# Combine the two plots using patchwork
combined_plot <- grtessymtp / grtessyp_numbers + plot_layout(guides = "collect", heights = c(3, 1))

# Print the combined plot
print(combined_plot)

# Save the combined plot to PowerPoint without title
export_graph <- save_plot(combined_plot, "Tessy Reporting Overview", export_graph)

############################################### Tessy category single plots

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
        title = paste("Pangolin Nomenklatur per Tessy Reporting Category", tessy),
        x = "", 
        y = "Antall av Sekvenser (n)", 
        fill = "Pangolin Nomenklatur"
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
        title = paste("Pangolin Nomenclature per Tessy Reporting Category", tessy),
        x = "", 
        y = "Andel av Sekvenser (%)", 
        fill = "Pangolin Nomenklatur"
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
head(subset_data12mo_modp)

# ------------- PLOT 1: Percentage Stacked Bar Plot -------------
grtessymtp_12mo <- ggplot(subset_data12mo, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_comb) +
  labs(y = "Andel av Sekvenser (%)", x = "", fill = "Pangolin Nomenklatur") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") + # Do not set limits here to avoid conflict
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, size = 10))

# ------------- PLOT 2: Grey Bars for TotalSeq with Line Plot for Percentages -------------
combined_plot_12mo_mod <- ggplot(subset_data12mo_modp, aes(x = Sampledate)) +
  geom_bar(aes(y = TotalSeq / max(TotalSeq) * 100, fill = "TotalSeq"), 
           stat = "identity", alpha = 0.5, color = "black", position = "identity") +
  geom_line(aes(y = Percent, color = Tessy, group = Tessy), linewidth = 2) +
  scale_y_continuous(
    name = "Andel av Sekvenser (%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data12mo$TotalSeq) / 100,
      name = "Antall av Sekvenser (n)"
    )
  ) +
  scale_color_manual(values = variant_color, name = "Pangolin Nomenklatur") +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall Sekvenser") +
  scale_x_date(date_labels = "%b-%Y", date_breaks = "1 month") + # Same scale on x-axis but no limits 
  labs(x = "") +
  theme_classic() +
  theme(axis.text.x = element_text(angle = 90, size = 10))

# ------------- COMBINE PLOTS USING PATCHWORK -------------
# Adjusting the height of the lower graph to be bigger (increasing lower plot's relative height in the layout)
combined_plot <- grtessymtp_12mo / combined_plot_12mo_mod + 
  plot_layout(guides = "collect", heights = c(3, 2))  # Adjusting height proportions (3 for lower plot)

# Print the combined plot
print(combined_plot)

export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())


 ### Season only Tessy with trends 



# Assuming subset_data_season is correctly defined and has the necessary columns
subset_data_season_gr <- ggplot(subset_data_season, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_a) +
  labs(y = "Andel av Sekvenser (%)", x = "", fill = "Pangolin Nomenklatur") +
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
    name = "Andel av Sekvenser(%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data_season_p$TotalSeq) / 100,
      name = "Antall av Sekvenser(n)"
    )
  ) +
  scale_color_manual(values = kvalitativ_a) +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall Sekvenser") +
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
print(combined_plot)

# Export the plot to a PowerPoint slide
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())

# Assuming subset_data_season is correctly defined and has the necessary columns
subset_data_year_gr <- ggplot(subset_data_year, aes(x = Sampledate, y = Percent, fill = Tessy)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(values = kvalitativ_a) +
  labs(y = "Andel av Sekvenser (%)", x = "", fill = "Pangolin Nomenklatur") +
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
    name = "Andel av Sekvenser(%)",
    sec.axis = sec_axis(
      transform = ~ . * max(subset_data_season_p$TotalSeq) / 100,
      name = "Antall av Sekvenser(n)"
    )
  ) +
  scale_color_manual(values = kvalitativ_a) +
  scale_fill_manual(values = c("TotalSeq" = "grey"), name = "", labels = "Antall Sekvenser") +
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
print(combined_plot)

# Export the plot to a PowerPoint slide
export_graph <- add_slide(export_graph, layout = "Title and Content", master = "Office Theme")
export_graph <- ph_with(export_graph, value = combined_plot, location = ph_location_fullsize())

