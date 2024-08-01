library(odbc)
library(tidyverse)

con <- dbConnect(odbc(),
                 Driver = "SQL Server",
                 Server = "sql-bn-covid19",
                 Database = "BN_Covid19")

BN <- tbl(con, "ENTRYTABLE") %>% 
  # Keep all columns
  rename("Dekning_Artic" = PROSENTDEKNING_GENOM,
         "Dekning_Swift" = COVERAGE_BREADTH_SWIFT,
         "Dekning_Nano" = DEKNING_NANOPORE,
         "Dekning_Eksterne" = COVERAGE_BREATH_EKSTERNE) %>% 
  collect()

# Get the NSP5 mutations
tmp <- tbl(con, "ENTRYFLD") %>%
  # Get the NSP5 mutations
  filter(FIELDID == 388) %>% 
  collect() %>% 
  rename("NSP5_mut" = CONTENT)
  
# Add the NSP5 mutations to BN
BN <- left_join(BN, tmp, by = "KEY") 
  

# Convert comma to dot in the coverage
BN <- BN %>% 
  # Replace a few double commas
  mutate(Dekning_Nano = str_replace(Dekning_Nano, ",,", ",")) %>% 
  # Change comma to decimal for the coverage
  mutate(Dekning_Artic = str_replace(Dekning_Artic, ",", "."),
         Dekning_Swift = str_replace(Dekning_Swift, ",", "."),
         Dekning_Nano = str_replace(Dekning_Nano, ",", "."),
         Dekning_Eksterne = str_replace(Dekning_Eksterne, ",", "."))

save(BN, file = "N:/Virologi/JonBrate/Prosjekter/BN.RData")


