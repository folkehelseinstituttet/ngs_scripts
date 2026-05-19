###### Sequences per week for percentage calculations: ######

# Make this script self-sufficient when sourced on its own.
suppressPackageStartupMessages({
  library(magrittr)
  library(dplyr)
  library(ggplot2)
  library(lubridate)
  library(tsibble)
})

if (!exists("SC2db_v")) {
  stop("Object 'SC2db_v' is missing. Run the SQL/classification scripts before sourcing SC2_Seqs_per_month.R.")
}

# Calculate Sequences per week for Spike protein sequence results
spw_spike <- SC2db_v %>%
  filter(nc_pangolin_short != "") %>%
  filter(Spike_mut != "") %>%
  count(wy, name = "TotalSeq") %>%
  mutate(ym = tsibble::yearweek(wy)) # count total sequences per week and convert week to yearweek format

# Calculate Total Valid Sequences per week
v_seqs_per_week <- SC2db_v %>%
  count(wy, name = "TotalSeq") %>%
  mutate(wy = tsibble::yearweek(wy))

###### Sequences per month for percentage calculations: ######

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

###### Sequences per Originating laboratory #######

v_seqs_per_month_origin <- SC2db_v %>%
  group_by(my, Origin) %>%
  count(name = "TotalSeq") %>%
  ungroup() %>%
  mutate(my  = as.Date(paste0(my, " 01"), format="%Y %b %d")) 


# Create a bar chart per month based on Origin
spmlabto <- ggplot(v_seqs_per_month_origin, aes(x = my, y = TotalSeq, fill = Origin)) +
  geom_bar(stat = "identity") +
  labs(title = "Sekvensering av SC2 i Norge",
       x = "Måned",
       y = "Antall Sekvenser") +
  scale_x_date(
    breaks = "1 month",  # Show breaks every month
    labels = scales::date_format("%b %Y")  # Format as month name and year
  ) +
  scale_fill_manual(values = kvalitativ_a) +  # Set custom colors
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  theme(plot.title = element_text(hjust = 0.5, size = 14)) +  # Center the title and increase its size
  theme(legend.position="right")  # Optional: Remove legend if not needed


spmlabto

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
       x = "Måned",
       y = "Antall Sekvenser") +
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

