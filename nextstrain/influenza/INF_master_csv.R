#!/usr/bin/env Rscript
# Prepare the same H1/H3/VIC inputs as INF.R from the FluSeq master archives.
# Run Rscript INF_master_csv.R --help for input and output options.

default_master <- paste0("N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/",
  "Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv")
default_lab <- "N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender_GISAID.csv"
default_output <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/11-Nextstrain"
default_staging <- "N:/Virologi/NGS/tmp/flu_nextstrain"

parse_options <- function(args) {
  opts <- list(master = default_master, fasta = NULL, lab = default_lab,
               output = default_output, staging = default_staging)
  if (any(args %in% c("-h", "--help"))) {
    cat("Usage: Rscript INF_master_csv.R [--master master.csv] [--fasta master.fasta]\n",
        "       [--lab lookup.csv] [--output output_directory] [--staging staging_directory]\n",
        "Defaults use the N: drive; master.fasta defaults beside master.csv.\n", sep = "")
    return(NULL)
  }
  if (length(args) %% 2L) stop("Each option requires a path; use --help for usage.")
  if (length(args)) for (i in seq.int(1L, length(args), by = 2L)) {
    name <- sub("^--", "", args[i])
    if (!startsWith(args[i], "--") || !name %in% names(opts) || !nzchar(args[i + 1L])) {
      stop("Unknown option or missing path: ", args[i], "; use --help for usage.")
    }
    opts[name] <- list(args[i + 1L])
  }
  if (is.null(opts$fasta)) opts$fasta <- file.path(dirname(opts$master), "master.fasta")
  opts
}

read_master <- function(path) {
  if (!file.exists(path)) stop("Master CSV not found: ", path)
  # Read all IDs as text, including literal NA and leading zeroes.
  x <- read.csv(path, sep = ";", header = TRUE, colClasses = "character", na.strings = character(),
                check.names = FALSE, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  if (anyDuplicated(tolower(names(x)))) stop("Master CSV has duplicate column names.")
  names(x) <- tolower(names(x))
  required <- c("key", "ngs_sekvens_resultat", "pasient_fylke_nr", "prove_tatt",
                "pasient_fylke_name", "prove_innsender_id", "prove_kategori")
  missing <- setdiff(required, names(x))
  if (length(missing)) stop("Missing master CSV columns: ", paste(missing, collapse = ", "))
  x
}

read_lab_lookup <- function(path) {
  if (!file.exists(path)) stop("Laboratory lookup not found: ", path)
  raw <- readBin(path, "raw", n = file.info(path)$size)
  if (length(raw) >= 2L && (identical(raw[1:2], as.raw(c(255, 254))) ||
                             identical(raw[1:2], as.raw(c(254, 255))))) {
    encoding <- "UTF-16"
  } else {
    valid_utf8 <- tryCatch(!is.na(iconv(rawToChar(raw), from = "UTF-8", to = "UTF-8", sub = NA)),
                           error = function(e) FALSE)
    encoding <- if (valid_utf8) "UTF-8-BOM" else "CP1252"
  }
  lab <- read.csv(path, sep = ";", header = TRUE, colClasses = "character", na.strings = character(),
                  check.names = FALSE, fileEncoding = encoding, stringsAsFactors = FALSE)
  if (anyDuplicated(names(lab))) stop("Laboratory lookup has duplicate column names.")
  if (!all(c("Innsender_nr", "GISAID_Id") %in% names(lab))) {
    stop("Laboratory lookup must contain 'Innsender_nr' and 'GISAID_Id'.")
  }
  lab
}

write_metadata <- function(data, path) {
  if (!requireNamespace("writexl", quietly = TRUE)) stop("Install the R package writexl.")
  writexl::write_xlsx(data, path)
}

parse_date_col <- function(x) {
  # Equivalent date formats accepted by INF.R, with timestamps allowed.
  x <- trimws(as.character(x))
  result <- rep(as.Date(NA), length(x))
  formats <- c("%Y-%m-%d", "%Y%m%d", "%d.%m.%Y", "%d/%m/%Y", "%d%m%Y", "%m/%d/%Y")
  for (format in formats) {
    todo <- is.na(result) & nzchar(x)
    if (!any(todo)) break
    result[todo] <- suppressWarnings(as.Date(x[todo], format = format))
  }
  result
}

county_from_nr <- function(nr, fallback) {
  county_map <- c("03" = "Oslo", "11" = "Rogaland", "15" = "M\u00f8re og Romsdal", "18" = "Nordland",
    "31" = "\u00d8stfold", "32" = "Akershus", "33" = "Buskerud", "34" = "Innlandet", "39" = "Vestfold",
    "40" = "Telemark", "42" = "Agder", "46" = "Vestland", "50" = "Tr\u00f8ndelag", "55" = "Troms", "56" = "Finnmark")
  nr <- trimws(as.character(nr))
  nr[nchar(nr) == 1L] <- paste0("0", nr[nchar(nr) == 1L])
  out <- unname(county_map[nr])
  fallback <- as.character(fallback)
  # Repair known damaged names when the county number is unavailable.
  key <- tolower(gsub("[[:space:]]+", " ", trimws(fallback)))
  repairs <- c("tr ndelag" = "Tr\u00f8ndelag", "m re g romsdal" = "M\u00f8re og Romsdal", "stfold" = "\u00d8stfold",
               "tr\u00e3\u00b8ndelag" = "Tr\u00f8ndelag", "m\u00e3\u00b8re og romsdal" = "M\u00f8re og Romsdal",
               "\u00e3\u0098stfold" = "\u00d8stfold")
  hit <- !is.na(key) & key %in% names(repairs)
  fallback[hit] <- unname(repairs[key[hit]])
  out[is.na(out)] <- fallback[is.na(out)]
  out[is.na(out)] <- "Unknown"
  out
}

prepare_metadata <- function(master, lab) {
  keep <- !is.na(master$ngs_sekvens_resultat) & nzchar(master$ngs_sekvens_resultat) &
          !master$ngs_sekvens_resultat %in% c("NA", "N2", "N1") &
          (startsWith(master$ngs_sekvens_resultat, "A/H1N1") |
           startsWith(master$ngs_sekvens_resultat, "A/H3N2") |
           startsWith(master$ngs_sekvens_resultat, "B/Victoria"))
  master <- master[keep, , drop = FALSE]
  missing_key <- is.na(master$key) | !nzchar(trimws(master$key))
  if (any(missing_key)) message("Skipping ", sum(missing_key), " eligible rows with no Key.")
  master <- master[!missing_key, , drop = FALSE]
  if (!nrow(master)) stop("No eligible samples with a Key found in master CSV.")
  master$key <- trimws(master$key)
  if (anyDuplicated(master$key)) stop("Eligible samples have duplicate Key values.")

  # LabWare submitter IDs are text such as AALESUND-MIKR, not numeric IDs.
  lab_ids <- trimws(lab$Innsender_nr)
  valid <- !is.na(lab_ids) & nzchar(lab_ids)
  if (anyDuplicated(lab_ids[valid])) stop("Laboratory lookup has duplicate submitter IDs.")
  lab <- lab[valid, , drop = FALSE]
  lab_ids <- lab_ids[valid]
  lab_nr <- trimws(lab$GISAID_Id[match(trimws(master$prove_innsender_id), lab_ids)])
  fallback <- is.na(lab_nr) | !nzchar(lab_nr)
  if (any(fallback)) message("Using default originating lab 3869 for ", sum(fallback),
                             " sample(s) without a matching GISAID_Id.")
  lab_nr[fallback] <- "3869"
  date <- parse_date_col(master$prove_tatt)
  year <- format(date, "%Y")
  is_ref <- grepl("Ref", master$prove_kategori)
  result <- master$ngs_sekvens_resultat
  flu_type <- ifelse(startsWith(result, "A/"), "A", ifelse(startsWith(result, "B/"), "B", ""))
  name <- ifelse(is_ref, master$key, paste(flu_type, "Norway", sub("^[0-9]{4}", "", master$key), year, sep = "/"))
  if (any(is.na(name) | !nzchar(name)) || anyDuplicated(name)) {
    stop("Eligible samples have missing or duplicate isolate names; resolve them before generating files.")
  }
  county <- county_from_nr(master$pasient_fylke_nr, master$pasient_fylke_name)
  master$isolate_name <- name
  master$group <- ifelse(startsWith(result, "A/H1N1"), "H1",
                  ifelse(startsWith(result, "A/H3N2"), "H3",
                  ifelse(startsWith(result, "B/Victoria"), "VIC", "")))
  master$location <- ifelse(is_ref, NA_character_, paste0("Europe / Norway / ", county))
  master$authors <- ifelse(is_ref, NA_character_, "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF")
  master$originating_lab <- lab_nr
  master$collection_date <- format(date, "%Y-%m-%d")
  master[master$group != "", , drop = FALSE]
}

read_sequences <- function(path, samples) {
  if (!file.exists(path)) stop("Master FASTA not found: ", path)
  # FASTA IDs use the original sequencing ID, not the specimen index.
  columns <- intersect(c("ngs_lw_id", "sequence_id", "sequenceid", "sampleid", "originalname", "key", "prove_lw_id"), names(samples))
  aliases <- unlist(lapply(columns, function(col) trimws(samples[[col]])), use.names = FALSE)
  owners <- rep(seq_len(nrow(samples)), times = length(columns))
  valid <- !is.na(aliases) & nzchar(aliases) & !toupper(aliases) %in% c("NA", "N/A", "NONE", "NULL", "NAN", "-")
  aliases <- aliases[valid]; owners <- owners[valid]
  pairs <- unique(data.frame(alias = aliases, owner = owners, stringsAsFactors = FALSE))
  duplicate_alias <- unique(pairs$alias[duplicated(pairs$alias)])
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(lines)) lines[1] <- sub("^\ufeff", "", lines[1])
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]
  headers <- which(startsWith(lines, ">"))
  if (!length(headers)) stop("Master FASTA has no records: ", path)
  if (headers[1] != 1L) stop("Master FASTA contains sequence data before its first header.")
  ends <- c(headers[-1L] - 1L, length(lines))
  header_text <- trimws(substring(lines[headers], 2L))
  tokens <- vapply(strsplit(header_text, "[[:space:]]+"), function(x) if (length(x)) x[1L] else "", character(1))
  fields <- strsplit(tokens, "|", fixed = TRUE)
  ids <- vapply(fields, function(x) if (length(x)) x[1L] else "", character(1))
  match_rows <- match(ids, pairs$alias)
  ambiguous <- ids %in% duplicate_alias
  records <- vector("list", length(headers))
  ignored <- 0L
  count <- 0L
  for (i in seq_along(headers)) {
    header <- header_text[i]
    if (ambiguous[i]) stop("FASTA identifier matches multiple master rows: ", ids[i])
    match_row <- match_rows[i]
    if (is.na(match_row)) { ignored <- ignored + 1L; next }
    if (length(fields[[i]]) < 2L) stop("Matched FASTA header has no segment: ", header)
    segment <- toupper(sub("-.*$", "", sub("^[0-9]+-", "", fields[[i]][2L])))
    if (!segment %in% c("HA", "NA", "PB1", "PB2", "PA", "MP", "M", "NS", "NP")) {
      stop("Matched FASTA header has an unrecognised segment: ", header)
    }
    if (segment == "M") segment <- "MP"
    sequence <- if (ends[i] > headers[i]) paste(lines[(headers[i] + 1L):ends[i]], collapse = "") else ""
    sequence <- gsub("[[:space:]]+", "", sequence)
    if (!nzchar(sequence) || grepl("[^A-Za-z.*?-]", sequence)) stop("Invalid or empty sequence in FASTA record: ", header)
    count <- count + 1L
    records[[count]] <- data.frame(owner = pairs$owner[match_row], segment = segment, sequence = sequence,
                                   stringsAsFactors = FALSE)
  }
  if (!count) stop("No master FASTA records matched eligible master CSV identifiers.")
  if (ignored) message("Skipped ", ignored, " FASTA record(s) without a matching eligible sample.")
  records <- do.call(rbind, records[seq_len(count)])
  if (anyDuplicated(paste(records$owner, records$segment, sep = "\r"))) {
    stop("Multiple FASTA records match the same sample and segment; resolve them before generating files.")
  }
  missing <- setdiff(seq_len(nrow(samples)), records$owner)
  if (length(missing)) message(length(missing), " eligible sample(s) have no matching FASTA records.")
  records
}

metadata_for_group <- function(samples, group) {
  x <- samples[samples$group == group, , drop = FALSE]
  data.frame(Isolate_Name = x$isolate_name, Isolate_Id = rep("", nrow(x)), Passage_History = rep("Clinical Specimen", nrow(x)),
    Location = x$location, Authors = x$authors, Originating_Lab = x$originating_lab,
    Collection_Date = x$collection_date, Submission_Date = rep("", nrow(x)), stringsAsFactors = FALSE)
}

write_group_fasta <- function(path, sequences, samples, group, segment) {
  records <- sequences[sequences$segment == segment & samples$group[sequences$owner] == group, , drop = FALSE]
  con <- file(path, open = "wt", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  if (nrow(records)) for (i in seq_len(nrow(records))) {
    cat(">", samples$isolate_name[records$owner[i]], "\n", records$sequence[i], "\n", file = con, sep = "")
  }
}

check_dependencies <- function() {
  if (!requireNamespace("writexl", quietly = TRUE)) stop("Install the R package writexl.")
}

main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- parse_options(args)
  if (is.null(opts)) return(invisible(NULL))
  check_dependencies()
  samples <- prepare_metadata(read_master(opts$master), read_lab_lookup(opts$lab))
  if (!nrow(samples)) stop("No H1N1, H3N2 or B/Victoria samples found in master CSV.")
  sequences <- read_sequences(opts$fasta, samples)
  target <- file.path(opts$output, paste0(format(Sys.Date(), "%Y-%m-%d"), "_Nextstrain_Build"))
  for (group in c("H1", "H3", "VIC")) {
    dir <- file.path(target, group)
    if (!dir.create(dir, recursive = TRUE, showWarnings = FALSE) && !dir.exists(dir)) stop("Cannot create output directory: ", dir)
    write_metadata(metadata_for_group(samples, group), file.path(dir, "metadata.xlsx"))
    for (segment in c("HA", "NA")) {
      write_group_fasta(file.path(dir, paste0("raw_sequences_", tolower(segment), ".fasta")), sequences, samples, group, segment)
    }
    staging <- file.path(opts$staging, group)
    if (!dir.create(staging, recursive = TRUE, showWarnings = FALSE) && !dir.exists(staging)) stop("Cannot create staging directory: ", staging)
    files <- file.path(dir, c("metadata.xlsx", "raw_sequences_ha.fasta", "raw_sequences_na.fasta"))
    if (!all(file.copy(files, staging, overwrite = TRUE))) stop("Could not copy all files to staging directory: ", staging)
    message(group, ": ", sum(samples$group == group), " metadata samples")
  }
  message("Nextstrain inputs written to ", target, " and copied to ", opts$staging)
}

if (sys.nframe() == 0L) main()
