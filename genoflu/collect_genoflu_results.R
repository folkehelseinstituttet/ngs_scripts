#!/usr/bin/env Rscript

files <- list.files("fasta/", "tsv$", full.names=T)

data_list <- lapply(files, function(file) {
  read.delim(file, header = TRUE, stringsAsFactors = FALSE)
})

combined_data <- do.call(rbind, data_list)

# Step 4: Write the combined data frame to a new TSV file
write.table(combined_data, file = paste0(Sys.Date(), "_genoflu_combined_data.tsv"), sep = "\t", row.names = FALSE)
