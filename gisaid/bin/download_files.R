#!/usr/bin/env Rscript

library(seqinr)
library(tidyverse)

reference <- read.fasta("https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/nCoV-2019.reference.fasta")
write.fasta(reference, names = names(reference), "MN908947.3.fasta")

genelist <- read_csv("https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/corona%20genemap.csv")
write_csv(genelist, file = "genemap.csv")

# Remember to update
database <- read_csv("https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/FSDB/FSDB20220718.csv")
write_csv(database, file = "FSDB.csv")

# Write out sessionInfo() to track versions
session <- capture.output(sessionInfo())
write_lines(session, file = paste0(Sys.Date(), "_R_versions_download.txt"))