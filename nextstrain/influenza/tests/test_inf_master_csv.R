# Base-R integration checks; use package writers when installed, otherwise a TSV test substitute.
source("nextstrain/influenza/INF_master_csv.R", encoding = "UTF-8")
test_dir <- tempfile("nextstrain-master-test-")
dir.create(test_dir)
master <- data.frame(
  Key = c("252600001", "252600002", "252600003", "", "252600004"),
  NGS_LW_ID = c("SEQ1", "SEQ2", "SEQ3", "SEQ4", "SEQ5"),
  NGS_Sekvens_Resultat = c("A/H1N1", "A/H3N2", "B/Victoria", "A/H1N1", "N1"),
  Pasient_Fylke_Nr = c("50", "15", "31", "03", "03"),
  Pasient_Fylke_Name = c("Tr ndelag", "M re g Romsdal", " stfold", "Oslo", "Oslo"),
  Prove_Tatt = c("2026-10-25", "26.10.2026", "2026-10-27", "2026-10-28", "2026-10-29"),
  Prove_Innsender_ID = c("AALESUND-MIKR", " AHUS-MIKR ", "UNKNOWN", "AALESUND-MIKR", "AALESUND-MIKR"),
  Prove_Kategori = c("", "", "Ref", "", ""), stringsAsFactors = FALSE)
master_path <- file.path(test_dir, "master.csv")
write.table(master, master_path, sep = ";", row.names = FALSE, na = "", fileEncoding = "UTF-8")
# Reviews are required even when the metadata and sequences pass the old filters.
config <- list(schema_version = 1L, pathogen = "INF", key_column = "NGS_LW_ID",
  csv_delimiter = ";", review_options = list("Approved"), edit_columns = list(), default_columns = list())
writeLines(gisaid_json(config), file.path(test_dir, "config.json"), useBytes = TRUE)
dir.create(file.path(test_dir, "reviews"))
for (i in seq_len(nrow(master))) {
  row <- as.list(master[i, , drop = FALSE])
  event <- list(format_version = 1L, id = paste0("review", i), pathogen = "INF", key = master$NGS_LW_ID[i],
    result_hash = gisaid_fingerprint(row, gisaid_sort(names(master)), "NGS_LW_ID"),
    created_at = "2026-11-05T12:00:00Z", supersedes = list(),
    review = list(reviewer = "TEST", assessment = "Approved", comment = "",
                  overrides = setNames(list(), character())))
  writeLines(gisaid_json(event), file.path(test_dir, "reviews", paste0("review", i, ".json")), useBytes = TRUE)
}
fasta_path <- file.path(test_dir, "master.fasta")
writeLines(c(
  ">SEQ1|01-HA-H1N1 description", "AC", "GT", ">SEQ1|02-NA-H1N1", "AAAC",
  ">SEQ2|01-HA-H3N2", "CCCC", ">SEQ3|01-HA-Bvic", "GGGG", ">SEQ3|02-NA-Bvic", "TTTT",
  ">OTHER|01-HA-H1N1", "ACGT"), fasta_path, useBytes = TRUE)
lab <- data.frame(Innsender_nr = c("AALESUND-MIKR", "AHUS-MIKR", "TOM-MIKR"),
                  Innsender_navn = c("Helse M\u00f8re og Romsdal", "Akershus", "T\u00f8nsberg"),
                  GISAID_Id = c("1447", "1433", ""),
                  `Institution Name` = c("Aalesund Hospital", "Akershus University Hospital", "Unknown"),
                  check.names = FALSE)
lab_path <- file.path(test_dir, "Innsender_GISAID.csv")
write.table(lab, lab_path, sep = ";", quote = FALSE, row.names = FALSE, na = "", fileEncoding = "UTF-8")
lab <- read_lab_lookup(lab_path)
stopifnot(lab$Innsender_nr[1] == "AALESUND-MIKR", lab$Innsender_navn[1] == "Helse M\u00f8re og Romsdal")
cp1252_path <- file.path(test_dir, "lookup-cp1252.csv")
write.table(lab, cp1252_path, sep = ";", row.names = FALSE, na = "", fileEncoding = "CP1252")
stopifnot(identical(read_lab_lookup(cp1252_path), lab))
real_xlsx <- requireNamespace("writexl", quietly = TRUE) && requireNamespace("readxl", quietly = TRUE)
check_dependencies <- function() invisible(NULL)
if (!real_xlsx) write_metadata <- function(data, path) {
  write.table(data, path, sep = "\t", row.names = FALSE, na = "", fileEncoding = "UTF-8")
}
output <- file.path(test_dir, "output")
staging <- file.path(test_dir, "staging")
main(c("--master", master_path, "--fasta", fasta_path, "--lab", lab_path, "--output", output, "--staging", staging))
build <- file.path(output, paste0(format(Sys.Date(), "%Y-%m-%d"), "_Nextstrain_Build"))
expected_files <- as.vector(outer(c("H1", "H3", "VIC"), c("metadata.xlsx", "raw_sequences_ha.fasta", "raw_sequences_na.fasta"), paste, sep = "/"))
stopifnot(setequal(list.files(build, recursive = TRUE), expected_files),
          setequal(list.files(staging, recursive = TRUE), expected_files))
for (f in expected_files) stopifnot(identical(unname(tools::md5sum(file.path(build, f))), unname(tools::md5sum(file.path(staging, f)))))
metadata <- function(group) {
  path <- file.path(build, group, "metadata.xlsx")
  if (real_xlsx) as.data.frame(readxl::read_excel(path), stringsAsFactors = FALSE) else
    read.delim(path, colClasses = "character", na.strings = character(), check.names = FALSE, fileEncoding = "UTF-8")
}
h1 <- metadata("H1"); h3 <- metadata("H3"); vic <- metadata("VIC")
stopifnot(identical(names(h1), c("Isolate_Name", "Isolate_Id", "Passage_History", "Location", "Authors", "Originating_Lab", "Collection_Date", "Submission_Date")),
          h1$Isolate_Name == "A/Norway/00001/2026", h1$Location == "Europe / Norway / Tr\u00f8ndelag",
          h1$Originating_Lab == "1447", h1$Collection_Date == "2026-10-25",
          h3$Isolate_Name == "A/Norway/00002/2026", h3$Originating_Lab == "1433", h3$Collection_Date == "2026-10-26",
          vic$Isolate_Name == "252600003", vic$Originating_Lab == "3869")
stopifnot(identical(readLines(file.path(build, "H1/raw_sequences_ha.fasta")), c(">A/Norway/00001/2026", "ACGT")),
          identical(readLines(file.path(build, "H1/raw_sequences_na.fasta")), c(">A/Norway/00001/2026", "AAAC")),
          identical(readLines(file.path(build, "VIC/raw_sequences_ha.fasta")), c(">252600003", "GGGG")),
          length(readLines(file.path(build, "H3/raw_sequences_na.fasta"))) == 0L)
# Empty output groups should still produce a valid metadata table with the right columns.
samples <- prepare_metadata(read_master(master_path), lab)
empty_lab <- read_master(master_path)
empty_lab$prove_innsender_id[1] <- "TOM-MIKR"
stopifnot(prepare_metadata(empty_lab, lab)$originating_lab[1] == "3869")
err <- tryCatch(prepare_metadata(read_master(master_path), rbind(lab, lab[1, ])),
                error = function(e) conditionMessage(e))
stopifnot(grepl("duplicate submitter IDs", err, fixed = TRUE))
stopifnot(nrow(metadata_for_group(samples[samples$group == "H1", , drop = FALSE], "H3")) == 0L)
stopifnot(identical(county_from_nr(c("", "", ""), c("Tr ndelag", "M\u00c3\u00b8re og Romsdal", " stfold")),
                    c("Tr\u00f8ndelag", "M\u00f8re og Romsdal", "\u00d8stfold")))
ambiguous <- samples
ambiguous$ngs_lw_id[2] <- ambiguous$ngs_lw_id[1]
err <- tryCatch(read_sequences(fasta_path, ambiguous), error = function(e) conditionMessage(e))
stopifnot(grepl("matches multiple master rows", err, fixed = TRUE))
writeLines(c(">SEQ1|HA", "ACGT", ">SEQ1|01-HA-H1N1", "ACGT"), fasta_path)
err <- tryCatch(read_sequences(fasta_path, samples), error = function(e) conditionMessage(e))
stopifnot(grepl("Multiple FASTA records", err, fixed = TRUE))

# Older R-only readers omit original_rows. Recovery must preserve original aliases
# despite review edits, and retain unapproved rows for ambiguity detection.
compat_dir <- file.path(test_dir, "older-reader")
dir.create(compat_dir)
dir.create(file.path(compat_dir, "reviews"))
compat_master <- master[1:2, , drop = FALSE]
compat_master$Sequence_ID <- c("ARCHIVE1", "ARCHIVE2")
compat_path <- file.path(compat_dir, "master.csv")
write.table(compat_master, compat_path, sep = ";", row.names = FALSE, na = "", fileEncoding = "UTF-8")
config$edit_columns <- list("Sequence_ID")
writeLines(gisaid_json(config), file.path(compat_dir, "config.json"), useBytes = TRUE)
event <- jsonlite::fromJSON(file.path(test_dir, "reviews/review1.json"), simplifyVector = FALSE)
event$result_hash <- gisaid_fingerprint(as.list(compat_master[1, , drop = FALSE]),
                                       gisaid_sort(names(compat_master)), "NGS_LW_ID")
event$review$overrides <- list(Sequence_ID = "edited-alias")
writeLines(gisaid_json(event), file.path(compat_dir, "reviews/review1.json"), useBytes = TRUE)
compat_fasta <- file.path(compat_dir, "master.fasta")
writeLines(c(">ARCHIVE1|01-HA-H1N1", "ACGT", ">ARCHIVE2|01-HA-H3N2", "CCCC"), compat_fasta)
current_reader <- read_approved_master
modern_master <- read_master(compat_path)
read_approved_master <- function(master, pathogen) {
  snapshot <- current_reader(master, pathogen)
  snapshot$original_rows <- NULL
  snapshot
}
legacy_master <- read_master(compat_path)
stopifnot(identical(legacy_master, modern_master),
          legacy_master$sequence_id == "edited-alias",
          identical(attr(legacy_master, "original_rows")$sequence_id, c("ARCHIVE1", "ARCHIVE2")))
legacy_samples <- prepare_metadata(legacy_master, lab)
legacy_sequences <- read_sequences(compat_fasta, legacy_samples, attr(legacy_master, "original_rows"))
stopifnot(nrow(legacy_sequences) == 1L, legacy_sequences$owner == 1L,
          legacy_sequences$sequence == "ACGT")
compat_master$Sequence_ID[2] <- "ARCHIVE1"
write.table(compat_master, compat_path, sep = ";", row.names = FALSE, na = "", fileEncoding = "UTF-8")
ambiguous_master <- read_master(compat_path)
err <- tryCatch(read_sequences(compat_fasta, prepare_metadata(ambiguous_master, lab),
                               attr(ambiguous_master, "original_rows")), error = function(e) conditionMessage(e))
stopifnot(grepl("matches multiple master rows", err, fixed = TRUE))
# A change between approval and recovery must stop before creating outputs.
read_approved_master <- function(master, pathogen) {
  snapshot <- current_reader(master, pathogen)
  snapshot$original_rows <- NULL
  cat("\n", file = master, append = TRUE)
  snapshot
}
compat_output <- file.path(compat_dir, "output")
compat_staging <- file.path(compat_dir, "staging")
err <- tryCatch(main(c("--master", compat_path, "--fasta", compat_fasta, "--lab", lab_path,
                       "--output", compat_output, "--staging", compat_staging)), error = function(e) conditionMessage(e))
stopifnot(grepl("changed during export", err, fixed = TRUE),
          !dir.exists(compat_output), !dir.exists(compat_staging))
read_approved_master <- current_reader
unlink(test_dir, recursive = TRUE)
cat("Nextstrain master CSV integration checks passed", if (!real_xlsx) "(Excel writer substituted; packages not installed)" else "with real XLSX files", "\n")
