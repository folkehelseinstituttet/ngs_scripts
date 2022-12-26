#!/usr/bin/env Rscript

# Load packages
library(tidyverse)

# Load the BN object 
# load("/home/jonr/Prosjekter/FHI_Gisaid/BN.RData")
load(args[2])

# Plan
1. Lese inn alle prøver som ikke har GisaidId
2. Kjøre FrameShift-analyse på alt. Det vil jo bli veldig mange prøver første gangen.
3. Lage log-fil over alle som ikke passerer FrameShift - laste opp dette til BN i Gisaid-kolonna
4. Hvordan skal jeg klare å lage riktig sample sheet?
