#!/usr/bin/env Rscript
# One-time historical CSV import. Base R only; source() also exposes backfill_master().
# Existing master supplies the exact output column names and order.

nonblank <- function(x) !is.na(x) & nzchar(trimws(x))
id_value <- function(x) {
  x[is.na(x)] <- ""
  x <- trimws(x)
  x[toupper(x) %in% c("NA", "N/A", "NAN", "NONE", "NULL", "-")] <- ""
  x
}
sequence_columns <- c("NGS_LW_ID", "Sequence_ID", "SequenceID", "SampleID")
provenance_columns <- c("Master_Key_Source", "Master_Index_Source")

read_csv_text <- function(path, encoding = "auto", diagnose = FALSE) {
  if (!file.exists(path)) stop("Input does not exist: ", path)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  if (!length(bytes)) stop("Empty input: ", path)
  starts <- function(prefix) length(bytes) >= length(prefix) &&
    identical(bytes[seq_along(prefix)], as.raw(prefix))
  if (encoding == "auto") {
    encoding <- if (starts(c(255, 254))) "UTF-16LE" else if (starts(c(254, 255))) "UTF-16BE" else ""
    if (!nzchar(encoding)) {
      text <- rawToChar(bytes)
      encoding <- if (!is.na(iconv(text, from = "UTF-8", to = "UTF-8"))) "UTF-8" else "CP1252"
    }
  }
  con <- file(path, open = "rt", encoding = encoding)
  on.exit(close(con))
  lines <- withCallingHandlers(readLines(con, warn = FALSE), warning = function(w) stop(conditionMessage(w)))
  text <- sub("^\ufeff", "", paste(lines, collapse = "\n"))
  options <- list(header = TRUE, colClasses = "character", check.names = FALSE,
                  na.strings = NULL, quote = '"', comment.char = "", fill = FALSE,
                  row.names = NULL, strip.white = FALSE, blank.lines.skip = TRUE)
  separators <- c(";", ",", "\t")
  # Detect the separator from the header alone. Malformed data rows must not
  # influence read.table's header/row-name heuristics during detection.
  header_text <- sub("^\ufeff", "", lines[which(nzchar(trimws(lines)))[1]])
  widths <- vapply(separators, function(sep) tryCatch(
    ncol(do.call(read.table, c(list(text = header_text, sep = sep, nrows = 0L), options))),
    error = function(e) 0L), integer(1))
  sep <- separators[which.max(widths)]
  counts_con <- textConnection(text)
  counts <- tryCatch(count.fields(counts_con, sep = sep, quote = '"', comment.char = "", blank.lines.skip = FALSE),
                     finally = close(counts_con))
  # count.fields reports NA on continuation lines and can synthesize a final
  # record at EOF for an unterminated quote. Do not accept that truncated field.
  if (length(counts) > length(lines)) stop("Unterminated quoted CSV field near the end of ", basename(path))
  records <- which(!is.na(counts) & counts > 0)
  if (!length(records)) stop("No CSV header found: ", basename(path))
  expected <- counts[records[1]]
  bad <- records[counts[records] != expected]
  delimiter <- if (sep == "\t") "tab" else paste0("'", sep, "'")
  if (diagnose) {
    message(basename(path), ": separator ", delimiter, "; header has ", expected,
            " fields; inconsistent records: ", length(bad),
            ". Line numbers refer to record-ending physical lines; no cell values are printed.")
    return(data.frame(line = bad, fields = counts[bad], expected = rep(expected, length(bad))))
  }
  if (length(bad)) stop("Inconsistent CSV field counts: ", basename(path),
                        "; separator ", delimiter, "; expected ", expected, " fields. ",
                        paste(sprintf("Line %d: %d fields", head(bad, 10), counts[head(bad, 10)]), collapse = "; "),
                        ". Check missing/extra separators or incorrectly quoted text. ",
                        "Use diagnose_csv() for all affected lines. No rows were padded or discarded.")
  tab <- do.call(read.table, c(list(text = text, sep = sep), options))
  names(tab) <- trimws(names(tab))
  if (!ncol(tab) || any(!nzchar(names(tab))) || anyDuplicated(tolower(names(tab))))
    stop("Missing or duplicate column names: ", basename(path))
  tab
}

diagnose_csv <- function(path, encoding = "auto") read_csv_text(path, encoding, diagnose = TRUE)

# The LABWAREDIRECT.xml mappings are identity mappings except these renames.
# Canonical spelling comes from the actual master header, not R's make.names().
canonicalize <- function(tab, header, label, metadata = FALSE) {
  aliases <- c(Pasient_Kjonn = "Pasient_Kjnn", Pasient_Kjønn = "Pasient_Kjnn",
               Prove_Manad = "Prove_M nad", Prove_Maanad = "Prove_M nad", Prove_Månad = "Prove_M nad")
  if (metadata) aliases <- c(aliases, RekvNr = "Key", Key = "Metadata_Key", Sesong = "Prove_Sesong")
  targets <- names(tab)
  match_alias <- match(tolower(targets), tolower(names(aliases)))
  hit <- !is.na(match_alias)
  targets[hit] <- unname(aliases[match_alias[hit]])
  match_header <- match(tolower(targets), tolower(header))
  hit <- !is.na(match_header)
  targets[hit] <- header[match_header[hit]]
  if (any(tolower(targets) %in% tolower(provenance_columns)))
    stop(label, ": provenance columns are reserved; remove them from this input")
  unknown <- setdiff(targets, header)
  if (length(unknown)) stop(label, ": columns absent from the master header: ", paste(unknown, collapse = ", "),
                            ". Add them to a copy of the master header before importing.")
  out <- tab[, FALSE, drop = FALSE]
  for (i in seq_along(targets)) {
    dest <- targets[i]
    value <- tab[[i]]
    if (dest %in% names(out)) {
      conflict <- nonblank(out[[dest]]) & nonblank(value) & out[[dest]] != value
      if (any(conflict)) stop(label, ": conflicting source columns for ", dest, " at CSV record ", which(conflict)[1] + 1L)
      use <- nonblank(value)
      out[[dest]][use] <- value[use]
    } else out[[dest]] <- value
  }
  out
}

align_columns <- function(tab, header) {
  for (name in setdiff(header, names(tab))) tab[[name]] <- rep("", nrow(tab))
  tab[, header, drop = FALSE]
}

sequences <- function(tab) {
  out <- rep("", nrow(tab))
  for (name in intersect(sequence_columns, names(tab))) {
    value <- id_value(tab[[name]])
    use <- !nzchar(out) & nzchar(value)
    out[use] <- value[use]
  }
  out
}

check_indexes <- function(tab, label) {
  ids <- id_value(tab$Prove_LW_ID)
  if (any(!nzchar(ids))) stop(label, ": unresolved Prove_LW_ID at CSV record ", which(!nzchar(ids))[1] + 1L)
  if (anyDuplicated(ids)) {
    duplicate <- anyDuplicated(ids)
    records <- which(ids == ids[duplicate]) + 1L
    stop(label, ": duplicate Prove_LW_ID at CSV records ", paste(head(records, 10), collapse = ", "),
         if (length(records) > 10L) " (and more)" else "",
         if (label == "historical results")
           ". Set duplicate_results = 'first' or 'last' to keep one complete historical record per resolved ID." else "")
  }
  seqs <- sequences(tab)
  groups <- split(ids[nzchar(seqs)], seqs[nzchar(seqs)])
  if (any(vapply(groups, function(x) length(unique(x)) > 1L, logical(1))))
    stop(label, ": sequencing ID maps to multiple specimen IDs")
}

fill_indexes <- function(tab, label) {
  tab$Prove_LW_ID <- id_value(tab$Prove_LW_ID)
  seqs <- sequences(tab)
  missing <- !nzchar(tab$Prove_LW_ID)
  tab$Prove_LW_ID[missing] <- seqs[missing]
  tab$Master_Index_Source[missing] <- "Sequence_ID"
  provisional <- tab$Master_Index_Source == "Sequence_ID"
  if (any(provisional & tab$Prove_LW_ID != seqs)) stop(label, ": provisional index differs from sequencing ID")
  check_indexes(tab, label)
  tab
}

resolve_row <- function(row, known, label, allow_name_fallback = FALSE) {
  supplied <- id_value(row$Prove_LW_ID)
  seqid <- sequences(row)
  is_provisional <- row$Master_Index_Source == "Sequence_ID"
  seq_matches <- unique(known$Prove_LW_ID[nzchar(seqid) & sequences(known) == seqid])
  # Legacy Key is used only for records lacking a known specimen index.
  legacy_matches <- character()
  if (!nzchar(supplied) || is_provisional) {
    legacy <- id_value(row$Key)
    if (nzchar(legacy)) legacy_matches <- unique(known$Prove_LW_ID[
      id_value(known$Key) == legacy | known$Prove_LW_ID == legacy])
  }
  matches <- unique(c(seq_matches, legacy_matches))
  if (length(matches) > 1L) stop(label, ": ambiguous or disagreeing sequencing/legacy identifiers")
  if (nzchar(supplied) && !is_provisional) {
    if (length(matches) && matches != supplied) stop(label, ": specimen and sequencing identifiers disagree")
    return(row)
  }
  if (length(matches)) {
    matched <- known[match(matches, known$Prove_LW_ID), , drop = FALSE]
    row$Prove_LW_ID <- matches
    row$Master_Index_Source <- if (matched$Master_Index_Source == "Sequence_ID") "Sequence_ID" else "Prove_LW_ID"
    if (!nzchar(seqid) && row$Master_Index_Source == "Sequence_ID") {
      for (name in intersect(sequence_columns, names(row))) row[[name]] <- matched[[name]]
    }
  } else {
    if (!nzchar(seqid)) {
      name <- id_value(row$Key)
      if (!allow_name_fallback || !nzchar(name))
        stop(label, ": no specimen ID, sequencing ID, or unambiguous legacy match")
      if (!"SequenceID" %in% names(row))
        stop(label, ": name fallback requires SequenceID in the master header")
      if (name %in% sequences(known))
        stop(label, ": name fallback collides with an existing sequencing ID; resolve the identifiers first")
      # Keep Key unchanged. Use the exact name as an external record ID in the
      # existing sequencing-fallback contract, without inventing an NGS_LW_ID.
      row$SequenceID <- name
      seqid <- name
    }
    if (seqid %in% known$Prove_LW_ID) stop(label, ": provisional sequencing ID collides with an unrelated specimen ID")
    row$Prove_LW_ID <- seqid
    row$Master_Index_Source <- "Sequence_ID"
  }
  row
}

repair_text <- function(tab) {
  replacements <- c("tr ndelag" = "Trøndelag", "m re g romsdal" = "Møre og Romsdal", "stfold" = "Østfold",
                    "p vist" = "Påvist", "ikke p vist" = "Ikke påvist")
  for (name in names(tab)[tolower(names(tab)) == "pasient_fylke_name" | grepl("^PCR_.+_Res$", names(tab), ignore.case = TRUE)]) {
    values <- tab[[name]]
    # Undo only reversible UTF-8-as-CP1252 damage in these known text fields.
    for (i in which(grepl("[ÃÂâ]", values))) {
      bytes <- iconv(values[i], from = "UTF-8", to = "CP1252", sub = NA, toRaw = TRUE)[[1]]
      if (!is.null(bytes)) {
        fixed <- iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = NA)
        if (!is.na(fixed)) values[i] <- fixed
      }
    }
    lookup <- tolower(gsub("[[:space:]]+", " ", trimws(values)))
    allowed <- if (tolower(name) == "pasient_fylke_name") 1:3 else 4:5
    hits <- match(lookup, names(replacements)[allowed])
    values[!is.na(hits)] <- unname(replacements[allowed][hits[!is.na(hits)]])
    tab[[name]] <- values
  }
  tab
}

backfill_master <- function(master, metadata, results, output, overwrite_existing = FALSE, encoding = "auto",
                            allow_name_fallback = FALSE, duplicate_results = "error") {
  duplicate_results <- match.arg(duplicate_results, c("error", "first", "last"))
  paths <- vapply(c(master, metadata, results), normalizePath, character(1), winslash = "/", mustWork = TRUE)
  if (file.exists(output)) stop("Output already exists; choose a new filename: ", output)
  output_path <- file.path(normalizePath(dirname(output), winslash = "/", mustWork = TRUE), basename(output))
  if (tolower(output_path) %in% tolower(paths)) stop("Output must be separate from all inputs")
  old <- read_csv_text(master, encoding)
  header <- names(old)
  required <- c("Key", "Prove_LW_ID", "Master_Index_Source")
  if (!all(required %in% header)) stop("Master header must contain: ", paste(required, collapse = ", "))
  meta <- canonicalize(read_csv_text(metadata, encoding), header, "metadata", metadata = TRUE)
  history <- canonicalize(read_csv_text(results, encoding), header, "historical results")
  if (!nrow(history)) stop("Historical results contain no data rows")
  meta <- fill_indexes(align_columns(meta, header), "metadata")
  history <- align_columns(history, header)
  old$Prove_LW_ID <- id_value(old$Prove_LW_ID)
  # Repair legacy/fallback indexes before doing a fill-only historical import.
  for (i in seq_len(nrow(old))) old[i, ] <- resolve_row(
    old[i, , drop = FALSE], meta, paste("master record", i + 1L), allow_name_fallback)
  old <- fill_indexes(old, "master")
  # Metadata lacking a specimen ID must not downgrade a known master specimen.
  for (i in which(meta$Master_Index_Source == "Sequence_ID"))
    meta[i, ] <- resolve_row(meta[i, , drop = FALSE], old, paste("metadata record", i + 1L))
  meta <- fill_indexes(meta, "metadata")
  known <- rbind(old, meta)
  seqs <- sequences(known)
  groups <- split(known$Prove_LW_ID[nzchar(seqs)], seqs[nzchar(seqs)])
  if (any(vapply(groups, function(x) length(unique(x)) > 1L, logical(1))))
    stop("Master and metadata disagree about sequencing/specimen identifiers")
  for (i in seq_len(nrow(history)))
    history[i, ] <- resolve_row(history[i, , drop = FALSE], known, paste("historical record", i + 1L), allow_name_fallback)
  # Choose whole records only after metadata/name fallback has resolved their
  # indexes. Input order is not assumed to be chronological. Source files stay
  # untouched, and master/metadata duplicate checks remain strict.
  discarded <- integer()
  if (duplicate_results != "error") {
    discard <- duplicated(id_value(history$Prove_LW_ID), fromLast = duplicate_results == "last")
    discarded <- which(discard) + 1L
    history <- history[!discard, , drop = FALSE]
  }
  history <- fill_indexes(history, "historical results")
  combined <- old
  added <- matched <- conflicts <- 0L
  for (i in seq_len(nrow(history))) {
    row <- history[i, , drop = FALSE]
    key <- row$Prove_LW_ID
    mi <- match(key, meta$Prove_LW_ID)
    candidate <- if (is.na(mi)) row else meta[mi, , drop = FALSE]
    if (!is.na(mi)) matched <- matched + 1L
    use <- vapply(row, nonblank, logical(1))
    candidate[1, use] <- row[1, use]
    oi <- match(key, combined$Prove_LW_ID)
    if (is.na(oi)) {
      combined <- rbind(combined, candidate)
      added <- added + 1L
    } else {
      before <- combined[oi, , drop = FALSE]
      incoming <- vapply(candidate, nonblank, logical(1))
      populated <- vapply(before, nonblank, logical(1))
      conflicts <- conflicts + sum(incoming & populated & as.character(before[1, ]) != as.character(candidate[1, ]))
      use <- incoming & (overwrite_existing | !populated)
      combined[oi, use] <- candidate[1, use]
    }
  }
  combined <- repair_text(fill_indexes(combined, "output"))
  # Exclusive output creation avoids overwriting an input or an earlier preview.
  con <- file(output_path, open = "wx", encoding = "UTF-8")
  on.exit(close(con))
  cat("\ufeff", file = con)
  write.table(combined[, header, drop = FALSE], file = con, sep = ";", quote = TRUE,
              row.names = FALSE, col.names = TRUE, na = "", qmethod = "double", eol = "\n")
  message("Wrote ", nrow(combined), " rows and ", length(header), " columns to ", output_path,
          "\nAdded: ", added, "; historical rows matched to metadata: ", matched,
          "; without metadata: ", nrow(history) - matched,
          "; historical duplicate records skipped: ", length(discarded), " (policy: ", duplicate_results, ")",
          "; differing populated cells ", if (overwrite_existing) "overwritten" else "preserved", ": ", conflicts,
          "\nMetadata-only rows were not added. Input files were not changed.")
  invisible(combined)
}

main <- function(args) {
  usage <- paste("Usage: Rscript backfill_master_once.R --master master.csv",
                 "--metadata NGS_PREP_INF_report.csv --results historical.csv --output master.backfill.csv",
                 "[--overwrite-existing] [--allow-name-fallback] [--duplicate-results error|first|last]",
                 "[--encoding auto|UTF-8|CP1252|UTF-16LE|UTF-16BE]")
  if (!length(args) || "--help" %in% args) { cat(usage, "\n"); return(invisible(NULL)) }
  values <- list(overwrite_existing = FALSE, encoding = "auto", allow_name_fallback = FALSE)
  while (length(args)) {
    key <- args[1]
    if (key == "--overwrite-existing") {
      values$overwrite_existing <- TRUE
      args <- args[-1]
    } else if (key == "--allow-name-fallback") {
      values$allow_name_fallback <- TRUE
      args <- args[-1]
    } else {
      if (!key %in% c("--master", "--metadata", "--results", "--output", "--encoding", "--duplicate-results") || length(args) < 2L)
        stop(usage)
      values[[gsub("-", "_", substring(key, 3L), fixed = TRUE)]] <- args[2]
      args <- args[-c(1, 2)]
    }
  }
  if (!all(c("master", "metadata", "results", "output") %in% names(values))) stop(usage)
  do.call(backfill_master, values)
}

if (sys.nframe() == 0L) tryCatch(main(commandArgs(trailingOnly = TRUE)), error = function(e) {
  message("Backfill failed: ", conditionMessage(e))
  quit(status = 1L)
})
