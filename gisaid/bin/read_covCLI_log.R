library(tidyverse)

# Read the covCLI submission log
sub_log <- read_csv2("/home/jonr/Prosjekter/FHI_Gisaid/Gisaid_files/2024-04-09_submission.log", 
                     col_names = FALSE)

# Count successfull submissions
sub_log %>% 
  filter(X1 == "SUCCESS") %>% print(n=50)
