#!/usr/bin/env Rscript

# Load packages
library(tidyverse)

# Load the BN object 
# load("/home/jonr/Prosjekter/FHI_Gisaid/BN.RData")
load(args[2])

# Convert empty strings to NA
BN <- BN %>% mutate_all(list(~na_if(.,"")))

# Plan
1. OK: Lese inn alle prøver som ikke har GisaidId
2. Kjøre FrameShift-analyse på alt. Det vil jo bli veldig mange prøver første gangen.
3. Lage BN-import-template over sekvenser med Frameshift. 4. Hvordan skal jeg klare å lage riktig sample sheet?
  
  
# Initial filtering and cleaning
tmp <- BN %>%
  # Remove previously submitted samples
  filter(is.na(GISAID_EPI_ISL)) %>% 
  # Fjerne evt positiv controll
  filter(str_detect(KEY, "pos", negate = TRUE)) %>%
  # Endre Trøndelag til Trondelag
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "Tr\xf8ndelag", "Trondelag")) %>%
  # Endre Møre og Romsdal
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "M\xf8re", "More")) %>%
  # Endre Sør
  mutate("FYLKENAVN" = str_replace(FYLKENAVN, "S\xf8r", "Sor")) %>%
  # Change "Ukjent" in FYLKENAVN to NA
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "Ukjent")) %>% 
  mutate("FYLKENAVN" = na_if(FYLKENAVN, "ukjent")) %>% 
  # Fix date format
  mutate("PROVE_TATT" = ymd(PROVE_TATT)) %>%
  # Drop samples witout collection date
  filter(!is.na(PROVE_TATT))
