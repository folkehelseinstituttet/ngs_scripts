#!/usr/bin/env Rscript

# Check if seqinr is installed, if not install it.
list.of.packages <- c("seqinr")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages)

library(seqinr)

args <- commandArgs(trailingOnly=TRUE)

fasta <- args[1]
prefix <- args[2]

fasta <- read.fasta(fasta)

# Create a function to extract group names from sequence headers
get_group_name <- function(header) {
  # Extract the group based on the pattern "EPI_ISL_"
  group <- gsub('.*\\|EPI_ISL_([^|]+)\\|.*', '\\1', header)
  return(group)
}

# Split sequences into groups based on the pattern "EPI_ISL_"
grouped_sequences <- split(fasta, sapply(names(fasta), get_group_name))


# Write sequences into individual fasta files per group
for (group_name in names(grouped_sequences)) {
  tmp <- grouped_sequences[[group_name]][1:8]
  write.fasta(tmp, names = names(tmp), file = paste0(prefix, "EPI_ISL_", group_name, "_sequences.fasta"))
}
