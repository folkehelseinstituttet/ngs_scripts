# Import one or more GISAID "Isolate as XLS" exports into master.csv.
# Usage: Rscript import_gisaid_epi_csv.R [--master path/to/master.csv] export1.xls [export2.xls ...]
# Requires: readxl, readr. Only nonempty GISAID values are imported.

args <- commandArgs(trailingOnly = TRUE)
master_path <- "N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv"
if (length(args) >= 1L && args[1] == "--master") {
  if (length(args) < 3L) stop("Usage: Rscript import_gisaid_epi_csv.R [--master master.csv] export1.xls [export2.xls ...]")
  master_path <- args[2]
  args <- args[-c(1, 2)]
}
if (!length(args)) stop("Provide at least one GISAID XLS or XLSX export.")
if (!requireNamespace("readxl", quietly = TRUE) || !requireNamespace("readr", quietly = TRUE)) {
  stop("Install the readxl and readr packages before running this script.")
}
if (!file.exists(master_path)) stop("Master CSV not found: ", master_path)
if (any(!file.exists(args))) stop("Export file not found: ", paste(args[!file.exists(args)], collapse = ", "))

mapping <- c(
  "Isolate_Id" = "GISAID_Isolate_ID", "Isolate_Name" = "GISAID_Isolate_Name",
  "HA Segment_Id" = "GISAID_HA_ID", "NA Segment_Id" = "GISAID_NA_ID",
  "MP Segment_Id" = "GISAID_M_ID", "NP Segment_Id" = "GISAID_NP_ID",
  "NS Segment_Id" = "GISAID_NS_ID", "PA Segment_Id" = "GISAID_PA_ID",
  "PB1 Segment_Id" = "GISAID_PB1_ID", "PB2 Segment_Id" = "GISAID_PB2_ID"
)

# Use the same lock directory as the FluSeq master CSV updater.
lock_path <- paste0(master_path, ".lock")
if (!dir.create(lock_path, showWarnings = FALSE)) {
  stop("Could not acquire master lock: ", lock_path, ". Check for an active writer or a stale lock.")
}
import_exports <- function() {
  on.exit(unlink(lock_path, recursive = FALSE), add = TRUE)
  original_hash <- unname(tools::md5sum(master_path))
  master <- readr::read_delim(master_path, delim = ";", col_types = readr::cols(.default = readr::col_character()),
                              na = character(), trim_ws = FALSE, name_repair = "minimal", show_col_types = FALSE)
  if (nrow(readr::problems(master))) stop("Could not parse master CSV; no changes made.")
  if (anyDuplicated(names(master))) stop("Master CSV has duplicate column names.")
  missing <- setdiff(c("Key", unname(mapping)), names(master))
  if (length(missing)) stop("Missing master columns: ", paste(missing, collapse = ", "))
  keys <- trimws(master$Key)
  if (anyDuplicated(keys[nzchar(keys)])) stop("Master CSV contains duplicate nonempty Key values.")

  exports <- lapply(args, function(path) {
    x <- readxl::read_excel(path, sheet = 1, col_types = "text", .name_repair = "minimal")
    if (anyDuplicated(names(x))) stop("Duplicate columns in export: ", path)
    missing <- setdiff(c("Submitting_Sample_Id", names(mapping)), names(x))
    if (length(missing)) stop("Missing columns in ", path, ": ", paste(missing, collapse = ", "))
    x <- as.data.frame(x[, c("Submitting_Sample_Id", names(mapping))], stringsAsFactors = FALSE)
    x[is.na(x)] <- ""
    x[] <- lapply(x, trimws)
    x
  })
  exports <- do.call(rbind, exports)
  if (any(!nzchar(exports$Submitting_Sample_Id))) stop("An export row has no Submitting_Sample_Id.")
  unmatched <- unique(exports$Submitting_Sample_Id[!exports$Submitting_Sample_Id %in% keys])
  if (length(unmatched)) stop("Export sample IDs not found in master Key: ", paste(unmatched, collapse = ", "))

  # Segment fields have the form EPI123|SEGMENT|Submitting_Sample_Id.
  segment_cols <- names(mapping)[grepl(" Segment_Id$", names(mapping))]
  for (col in segment_cols) {
    segment <- sub(" Segment_Id$", "", col)
    for (i in which(nzchar(exports[[col]]))) {
      parts <- strsplit(exports[[col]][i], "|", fixed = TRUE)[[1]]
      if (length(parts) != 3L || !grepl("^EPI[0-9]+$", parts[1]) ||
          parts[2] != segment || parts[3] != exports$Submitting_Sample_Id[i]) {
        stop("Unexpected ", col, " value for sample ", exports$Submitting_Sample_Id[i], ": ", exports[[col]][i])
      }
      exports[[col]][i] <- parts[1]
    }
  }
  bad_isolate <- nzchar(exports$Isolate_Id) & !grepl("^EPI_ISL_[0-9]+$", exports$Isolate_Id)
  if (any(bad_isolate)) stop("Invalid isolate ID in export for sample: ", exports$Submitting_Sample_Id[which(bad_isolate)[1]])

  changes <- 0L
  for (sample_id in unique(exports$Submitting_Sample_Id)) {
    rows <- exports[exports$Submitting_Sample_Id == sample_id, , drop = FALSE]
    target <- match(sample_id, keys)
    for (source_col in names(mapping)) {
      values <- unique(rows[[source_col]][nzchar(rows[[source_col]])])
      if (length(values) > 1L) stop("Conflicting export values for ", sample_id, " / ", source_col)
      if (!length(values)) next
      target_col <- mapping[[source_col]]
      old <- trimws(master[[target_col]][target])
      if (nzchar(old) && old != values[1]) {
        stop("Conflicting existing value for ", sample_id, " / ", target_col, "; resolve it before importing.")
      }
      if (!nzchar(old)) {
        master[[target_col]][target] <- values[1]
        changes <- changes + 1L
      }
    }
  }
  if (!changes) {
    message("No new GISAID values to import; master was not changed.")
    return(invisible(NULL))
  }

  candidate <- tempfile(pattern = "master.csv.tmp.", tmpdir = dirname(master_path))
  on.exit(unlink(candidate), add = TRUE)
  readr::write_delim(master, candidate, delim = ";", na = "", quote = "needed")
  if (!identical(unname(tools::md5sum(master_path)), original_hash)) stop("Master changed during import; no replacement made.")
  backup <- tempfile(pattern = paste0(basename(master_path), ".bak."), tmpdir = dirname(master_path))
  if (.Platform$OS.type == "windows") {
    # File.Replace replaces the destination and creates its backup in one operation.
    ps <- tempfile(fileext = ".ps1")
    on.exit(unlink(ps), add = TRUE)
    writeLines(c("$ErrorActionPreference = 'Stop'", "[System.IO.File]::Replace($env:GISAID_CANDIDATE, $env:GISAID_MASTER, $env:GISAID_BACKUP)"), ps, useBytes = TRUE)
    old_env <- Sys.getenv(c("GISAID_CANDIDATE", "GISAID_MASTER", "GISAID_BACKUP"), unset = NA_character_)
    on.exit({
      for (n in names(old_env)) {
        if (is.na(old_env[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old_env[[n]]), n))
      }
    }, add = TRUE)
    Sys.setenv(GISAID_CANDIDATE = normalizePath(candidate, winslash = "\\"),
               GISAID_MASTER = normalizePath(master_path, winslash = "\\"),
               GISAID_BACKUP = file.path(normalizePath(dirname(master_path), winslash = "\\"), basename(backup)))
    status <- system2("powershell.exe", c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", shQuote(ps)))
    if (status != 0L) stop("Could not replace master. Check the master and backup before retrying: ", backup)
  } else {
    if (!file.copy(master_path, backup, overwrite = FALSE)) stop("Could not create master backup.")
    if (!identical(unname(tools::md5sum(backup)), original_hash) ||
        !identical(unname(tools::md5sum(master_path)), original_hash)) stop("Master changed during backup; no replacement made.")
    if (!file.rename(candidate, master_path)) stop("Could not replace master; backup: ", backup)
  }
  message("Imported ", changes, " values for ", length(unique(exports$Submitting_Sample_Id)), " samples. Backup: ", backup)
}
import_exports()
