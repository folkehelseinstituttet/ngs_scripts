# SC2 master-based exporter. Source shared/approval.R before calling export_sc2_gisaid().
sc2_gisaid_defaults <- function() list(
  master = paste0("N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/",
    "Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2/master.csv"),
  fasta = NULL,
  lab_lookup = "N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender_GISAID.csv",
  output_dir = "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon",
  prefix = NULL, assembly_method = "ARTIC 1.6.2",
  sequencing_technology = "Oxford Nanopore - GridION",
  authors = "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF")
sc2_gisaid_columns <- c("submitter", "fn", "covv_virus_name", "covv_type", "covv_passage",
  "covv_collection_date", "covv_location", "covv_host", "covv_gender", "covv_patient_age",
  "covv_patient_status", "covv_specimen", "covv_seq_technology", "covv_assembly_method",
  "covv_orig_lab", "covv_orig_lab_addr", "covv_subm_lab", "covv_subm_lab_addr", "covv_authors",
  "covv_outbreak", "covv_add_host_info", "covv_add_location", "covv_provider_sample_id",
  "covv_last_vaccinated", "covv_treatment", "covv_coverage", "covv_sampling_strategy")
sc2_require_columns <- function(headers, required, label) {
  missing <- setdiff(required, headers)
  if (length(missing)) gisaid_fail(label, ": missing columns: ", paste(missing, collapse = ", "))
}
sc2_decode_table <- function(bytes) {
  starts <- function(prefix) length(bytes) >= length(prefix) && identical(bytes[seq_along(prefix)], as.raw(prefix))
  if (starts(c(255L, 254L)) || starts(c(254L, 255L))) {
    text <- iconv(list(bytes), from = if (bytes[1L] == as.raw(255L)) "UTF-16LE" else "UTF-16BE", to = "UTF-8")[[1L]]
  } else {
    text <- iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = NA_character_)
    if (is.na(text)) text <- iconv(rawToChar(bytes), from = "CP1252", to = "UTF-8", sub = NA_character_)
  }
  if (is.na(text)) gisaid_fail("Lab lookup has invalid text encoding.")
  text <- sub("^\ufeff", "", text)
  # Only inspect the header for separator detection; quoted punctuation is data.
  header <- strsplit(text, "\r\n|\r|\n", perl = TRUE)[[1L]][1L]
  delimiters <- c(";", ",", "\t")
  widths <- vapply(delimiters, function(delimiter) {
    tryCatch(length(gisaid_parse_csv(header, delimiter)$headers), error = function(e) 0L)
  }, integer(1))
  parsed <- gisaid_parse_csv(text, delimiters[which.max(widths)])
  names(parsed$rows) <- trimws(parsed$headers)
  if (anyDuplicated(tolower(names(parsed$rows)))) gisaid_fail("Lab lookup has duplicate column names.")
  parsed$rows
}
sc2_lab_lookup <- function(bytes) {
  rows <- sc2_decode_table(bytes)
  sc2_require_columns(names(rows), c("Innsender_nr", "Innsender_navn"), "Lab lookup")
  labs <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_len(nrow(rows))) {
    code <- trimws(rows$Innsender_nr[i])
    if (!nzchar(code)) next
    if (!is.null(labs[[code]])) gisaid_fail("Lab lookup contains duplicate Innsender_nr values")
    fields <- intersect(c("Innsender_adresse", "Lab_address"), names(rows))
    addresses <- unique(trimws(unlist(rows[i, fields, drop = FALSE], use.names = FALSE)))
    addresses <- addresses[nzchar(addresses)]
    if (length(addresses) > 1L) gisaid_fail("Lab lookup has conflicting address columns")
    labs[[code]] <- list(name = trimws(rows$Innsender_navn[i]), address = if (length(addresses)) addresses[1L] else "")
  }
  labs
}
sc2_read_fasta <- function(bytes) {
  lines <- strsplit(gisaid_decode_utf8(bytes), "\r\n|\r|\n", perl = TRUE)[[1L]]
  records <- list(); header <- NULL; sequence <- character()
  finish <- function() {
    if (is.null(header)) return(invisible(NULL))
    if (!length(sequence)) gisaid_fail("Empty FASTA sequence")
    id <- strsplit(header, "[[:space:]]+", perl = TRUE)[[1L]][1L]
    records[[length(records) + 1L]] <<- list(id = id, header = header, sequence = paste(sequence, collapse = ""))
  }
  for (line in trimws(lines)) {
    if (!nzchar(line)) next
    if (startsWith(line, ">")) {
      finish()
      header <- trimws(substring(line, 2L))
      if (!nzchar(header) || grepl("[\\x01-\\x08\\x0b-\\x1f]", header, perl = TRUE)) gisaid_fail("Invalid FASTA header")
      sequence <- character()
    } else {
      if (is.null(header)) gisaid_fail("Sequence before the first FASTA header")
      value <- gsub("[[:space:]]+", "", line)
      if (!grepl("^[A-Za-z.*?\\-]+$", value)) gisaid_fail("Invalid FASTA sequence text")
      sequence <- c(sequence, value)
    }
  }
  finish()
  ids <- vapply(records, `[[`, character(1), "id")
  if (anyDuplicated(ids)) gisaid_fail("Duplicate FASTA records must be resolved before export")
  names(records) <- ids
  records
}
sc2_match_sequences <- function(approvals, identities, records) {
  aliases <- new.env(hash = TRUE, parent = emptyenv())
  fields <- c("NGS_LW_ID", "OriginalName", "SampleID", "Key", "Prove_LW_ID")
  for (i in seq_len(nrow(identities))) {
    values <- unique(trimws(unlist(identities[i, fields, drop = FALSE], use.names = FALSE)))
    values <- values[nzchar(values) & !toupper(values) %in% c("NA", "N/A", "NULL", "NONE", "-")]
    for (value in values) aliases[[value]] <- unique(c(aliases[[value]], identities$review_key[i]))
  }
  wanted <- vapply(approvals, `[[`, character(1), "key")
  matches <- setNames(vector("list", length(wanted)), wanted)
  for (record in records) {
    candidates <- aliases[[record$id]]
    if (any(candidates %in% wanted)) {
      if (length(candidates) != 1L) gisaid_fail("A selected FASTA ID matches multiple master samples")
      matches[[candidates]] <- c(matches[[candidates]], list(record))
    }
  }
  if (any(lengths(matches) != 1L)) gisaid_fail("Each eligible sample must match exactly one FASTA record; missing or ambiguous matches found")
  lapply(matches, `[[`, 1L)
}
sc2_repair_county <- function(value) {
  if (grepl("\u00c3|\u00c2|\u00e2", value)) {
    bytes <- iconv(value, from = "UTF-8", to = "CP1252", sub = NA_character_, toRaw = TRUE)[[1L]]
    if (!is.null(bytes)) {
      repaired <- iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = NA_character_)
      if (!is.na(repaired)) value <- repaired
    }
  }
  # County spellings use NFC; handle decomposed Nordic vowels without another package.
  value <- gsub("o\u0308", "\u00f6", value, fixed = TRUE)
  value <- gsub("a\u030a", "\u00e5", value, fixed = TRUE)
  value <- gsub("A\u030a", "\u00c5", value, fixed = TRUE)
  replacements <- c("tr ndelag" = "Tr\u00f8ndelag", "m re g romsdal" = "M\u00f8re og Romsdal", "stfold" = "\u00d8stfold")
  normalized <- tolower(gsub("[[:space:]]+", " ", trimws(value)))
  if (normalized %in% names(replacements)) unname(replacements[[normalized]]) else value
}
sc2_metadata_row <- function(row, lab, args, fasta_name) {
  collected <- trimws(row$Prove_Tatt)
  date <- if (grepl("^\\d{4}-\\d{2}-\\d{2}$", collected)) suppressWarnings(as.Date(collected, "%Y-%m-%d")) else as.Date(NA)
  if (is.na(date) || format(date, "%Y-%m-%d") != collected) gisaid_fail("Eligible samples need a valid ISO Prove_Tatt date (YYYY-MM-DD)")
  key <- row$Key
  unique <- if (grepl("^[0-9]{5,}$", key)) substring(key, 5L) else key
  if (!nzchar(unique) || grepl("[[:space:]/>]", unique)) gisaid_fail("Eligible Key cannot form an unambiguous FASTA submission name")
  county <- trimws(sc2_repair_county(row$Pasient_Fylke_Name))
  if (!nzchar(county) || toupper(county) %in% c("NA", "N/A", "NULL", "NONE")) gisaid_fail("Eligible samples need Pasient_Fylke_Name")
  gender <- toupper(if ("Pasient_Kjnn" %in% names(row)) row$Pasient_Kjnn else row$Pasient_Kjonn)
  sampling <- if (row$Prove_Kategori == "P1_") "Sentinel surveillance (ARI)" else
    if (row$Pasient_Status == "Inneliggende") "Non-sentinel surveillance (hospital)" else
    if (row$Prove_Kategori == "P2_" && row$Pasient_Status == "Poliklinisk") "Non-sentinel surveillance (outpatient)" else ""
  technology <- args$sequencing_technology
  if (startsWith(row$NGS_Primer_vers, "VM.3")) technology <- paste0(technology, " - Midnight version 3")
  result <- setNames(as.list(rep("Unknown", length(sc2_gisaid_columns))), sc2_gisaid_columns)
  values <- list(submitter = args$submitter, fn = fasta_name,
    covv_virus_name = paste0("hCoV-19/Norway/", unique, "/", format(date, "%Y")),
    covv_type = "betacoronavirus", covv_passage = "Clinical Specimen", covv_collection_date = collected,
    covv_location = paste0("Europe/Norway/", county), covv_host = "Human",
    covv_gender = if (gender %in% c("M", "F")) gender else "", covv_seq_technology = technology,
    covv_assembly_method = args$assembly_method, covv_orig_lab = lab$name, covv_orig_lab_addr = lab$address,
    covv_subm_lab = "Norwegian Institute of Public Health, Department of Virology",
    covv_subm_lab_addr = "P.O.Box 222 Skoyen, 0213 Oslo, Norway", covv_authors = args$authors,
    covv_coverage = row$NGS_Depth, covv_sampling_strategy = sampling)
  result[names(values)] <- values
  result
}
sc2_csv_bytes <- function(rows) {
  field <- function(value) if (grepl('[,"\r\n]', value)) paste0('"', gsub('"', '""', value, fixed = TRUE), '"') else value
  line <- function(values) paste(vapply(values, field, character(1)), collapse = ",")
  lines <- c(line(as.list(sc2_gisaid_columns)), vapply(rows, line, character(1)))
  charToRaw(enc2utf8(paste0(paste(lines, collapse = "\n"), "\n")))
}
export_sc2_gisaid <- function(args) {
  for (name in c("run", "submitter", "assembly_method", "sequencing_technology", "authors")) {
    if (!gisaid_string(args[[name]]) || !nzchar(trimws(args[[name]]))) {
      gisaid_fail("Run, submitter, assembly method, technology and authors must be nonempty")
    }
  }
  master <- normalizePath(args$master, winslash = "/", mustWork = TRUE)
  fasta <- gisaid_default(args$fasta, file.path(dirname(master), "master.fasta"))
  snapshot <- read_approved_master(master, "SC2")
  required <- c("Key", "NGS_Run_ID", "GISAID_Kommentar", "NC_Coverage", "Prove_Tatt", "Pasient_Fylke_Name",
    "Prove_Innsender_ID", "Prove_Kategori", "Pasient_Status", "NGS_Depth", "NGS_Primer_vers")
  sc2_require_columns(snapshot$headers, required, "SC2 master")
  if (!any(c("Pasient_Kjnn", "Pasient_Kjonn") %in% snapshot$headers)) gisaid_fail("SC2 master: missing Pasient_Kjnn/Pasient_Kjonn")
  counts <- setNames(list(), character()); selected <- integer()
  for (i in seq_len(nrow(snapshot$rows))) {
    row <- snapshot$rows[i, , drop = FALSE]
    coverage <- gsub(",", ".", trimws(row$NC_Coverage), fixed = TRUE)
    number <- if (grepl("^[+-]?(\\d+(\\.\\d*)?|\\.\\d+)([eE][+-]?\\d+)?$", coverage)) as.numeric(coverage) else NA_real_
    reason <- if (row$NGS_Run_ID != args$run) "other_run" else if (nzchar(row$GISAID_Kommentar)) "gisaid_comment" else
      if (!is.finite(number) || number < 0.75 || number > 1) "coverage" else if (!nzchar(trimws(row$Key))) "missing_key" else ""
    if (nzchar(reason)) counts[[reason]] <- gisaid_default(counts[[reason]], 0L) + 1L else selected <- c(selected, i)
  }
  if (!length(selected)) gisaid_fail("No currently approved samples remain after run, comment, coverage and Key filters")
  rows <- snapshot$rows[selected, , drop = FALSE]
  approvals <- snapshot$approvals[selected]
  if (anyDuplicated(rows$Key)) gisaid_fail("Eligible samples must have unique Key values")
  labs_bytes <- gisaid_read_bytes(args$lab_lookup)
  fasta_bytes <- gisaid_read_bytes(fasta)
  labs <- sc2_lab_lookup(labs_bytes)
  matches <- sc2_match_sequences(approvals, snapshot$identities, sc2_read_fasta(fasta_bytes))
  prefix <- gisaid_default(args$prefix, paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y")))
  if (!gisaid_string(prefix) || !nzchar(prefix) || prefix %in% c(".", "..") || grepl("[\\\\/:\r\n]", prefix)) {
    gisaid_fail("--prefix must be a filename without a directory")
  }
  fasta_name <- paste0(prefix, ".fasta")
  submission <- list(); fasta_lines <- character(); audit <- list()
  for (i in seq_len(nrow(rows))) {
    row <- as.list(rows[i, , drop = FALSE])
    lab <- labs[[trimws(row$Prove_Innsender_ID)]]
    if (is.null(lab) || !nzchar(lab$name)) gisaid_fail("An eligible sample lacks a matching originating lab name in the CSV lookup")
    if (!nzchar(lab$address)) counts$missing_lab_address <- gisaid_default(counts$missing_lab_address, 0L) + 1L
    metadata <- sc2_metadata_row(row, lab, args, fasta_name)
    record <- matches[[approvals[[i]]$key]]
    submission[[i]] <- metadata
    fasta_lines <- c(fasta_lines, paste0(">", metadata$covv_virus_name), record$sequence)
    audit[[i]] <- c(approvals[[i]], list(fasta_id = record$id, virus_name = metadata$covv_virus_name))
  }
  if (anyDuplicated(vapply(submission, `[[`, character(1), "covv_virus_name"))) gisaid_fail("Different eligible samples produce the same virus name")
  payloads <- setNames(list(sc2_csv_bytes(submission), charToRaw(enc2utf8(paste0(paste(fasta_lines, collapse = "\n"), "\n")))),
                       c(paste0(prefix, ".csv"), fasta_name))
  manifest <- list(format_version = 1L, pathogen = "SC2", run = args$run, samples = nrow(rows),
    approval_counts = snapshot$counts, filter_counts = counts, review_snapshot_token = snapshot$token,
    master_sha256 = snapshot$master_sha256, fasta_sha256 = gisaid_sha256(fasta_bytes),
    lab_lookup_sha256 = gisaid_sha256(labs_bytes), approvals = audit, outputs = lapply(payloads, gisaid_sha256))
  payloads[[paste0(prefix, ".manifest.json")]] <- charToRaw(enc2utf8(paste0(jsonlite::toJSON(manifest,
    auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE), "\n")))
  assert_approved_master(master, "SC2", snapshot$token)
  if (!identical(gisaid_read_bytes(fasta), fasta_bytes) || !identical(gisaid_read_bytes(args$lab_lookup), labs_bytes)) {
    gisaid_fail("FASTA or lab lookup changed during export; retry")
  }
  if (!dir.exists(args$output_dir) && !dir.create(args$output_dir, recursive = TRUE)) gisaid_fail("Cannot create output directory")
  paths <- file.path(args$output_dir, names(payloads))
  if (any(file.exists(paths))) gisaid_fail("Submission output already exists; use a new --prefix or output directory")
  created <- character(); completed <- FALSE
  on.exit(if (!completed) unlink(created), add = TRUE)
  for (i in seq_along(paths)) {
    # Record ownership only after exclusive creation, so cleanup cannot remove a colleague's file.
    con <- file(paths[i], "wxb")
    created <- c(created, paths[i])
    tryCatch(writeBin(payloads[[i]], con), finally = close(con))
  }
  completed <- TRUE
  manifest
}
