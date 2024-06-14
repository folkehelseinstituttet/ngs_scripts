library(tidyverse)

# Read lineage descriptions from GitHub
pango <- read_delim(file = "https://raw.githubusercontent.com/cov-lineages/pango-designation/master/lineage_notes.txt")

# 2023.11.08: Include BA.2.86 abbreviations
pango_str <- pango %>% 
  # Get the BA.2.86's
  filter(str_detect(Description, "B.1.1.529.2.86") | str_detect(Lineage, "^BA.2.86")) %>% 
  # Remove any withdrawn lineages
  filter(str_detect(Lineage, "\\*", negate = TRUE)) %>% 
  # Pull all the aliases into a character vector
  pull(Lineage)

# 2023.08.16: Including XBB abbreviations
# Create list of XBB lineages for the Nextstrain build file. This is copied and manually hardcoded into the build file.
pango_str <- pango %>%
  # Get the XBB's
  filter(str_detect(Description, "XBB") | str_detect(Lineage, "^XBB")) %>%
  # Remove some withdrawn lineages
  filter(str_detect(Lineage, "\\*", negate = TRUE)) %>%
  # Pull all the aliases into a character vector
  pull(Lineage)

# Create a list of queries to add to the builds.yaml file
# NB: The list needs to be enclosed by double quotes ("").
# These are actually not there now, but when the vector is printed they are shown,
# and copied when I copy and paste
tmp <- str_flatten(pango_str, collapse = "', '")
# Insert "[' in the beginning
tmp <- str_c('[\'', tmp)
# Insert ']" at the end
tmp <- str_c(tmp, '\']')
print(tmp)

# Create list of BA.5 lineages for the Nextstrain build file
pango_str <- pango %>% 
  # Get the BA.5's
  filter(str_detect(Description, "B.1.1.529.5")) %>% 
  # Remove some withdrawn lineages
  filter(str_detect(Lineage, "\\*", negate = TRUE)) %>% 
  # Pull all the aliases into a character vector
  pull(Lineage)

# Create a list of queries to add to the builds.yaml file
# NB: The list needs to be enclosed by double quotes ("").
# These are actually not there now, but when the vector is printed they are shown,
# and copied when I copy and paste
tmp <- str_flatten(pango_str, collapse = "', '")
# Insert "[' in the beginning
tmp <- str_c('[\'', tmp)
# Insert ']" at the end
tmp <- str_c(tmp, '\']')
print(tmp)

# Create list of BA.2.75 lineages for the Nextstrain build file
pango_str <- pango %>% 
  # Get the BA.5's
  filter(str_detect(Description, "B.1.1.529.2.75")) %>% 
  # Remove some withdrawn lineages
  filter(str_detect(Lineage, "\\*", negate = TRUE)) %>% 
  # Pull all the aliases into a character vector
  pull(Lineage)

# Create a list of queries to add to the builds.yaml file
# NB: The list needs to be enclosed by double quotes ("").
# These are actually not there now, but when the vector is printed they are shown,
# and copied when I copy and paste
tmp <- str_flatten(pango_str, collapse = "', '")
# Insert "[' in the beginning
tmp <- str_c('[\'', tmp)
# Insert ']" at the end
tmp <- str_c(tmp, '\']')
print(tmp)
