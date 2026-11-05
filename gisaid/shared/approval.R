# Read-only Sequence Review approval checks in R. No external runtime is used.
gisaid_require_packages <- function() {
  required <- c("jsonlite", "digest")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Install required R packages: ", paste(missing, collapse = ", "),
                            ". Use install.packages(c(\"jsonlite\", \"digest\")).", call. = FALSE)
}
gisaid_fail <- function(...) stop(..., call. = FALSE)
gisaid_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
gisaid_object <- function(x) is.list(x) && !is.null(names(x))
gisaid_default <- function(x, fallback) if (is.null(x)) fallback else x
gisaid_trim <- function(x) trimws(x, whitespace = "[\\x09-\\x0D \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]")
gisaid_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
gisaid_sha256 <- function(x) digest::digest(if (is.character(x)) charToRaw(enc2utf8(x)) else x,
                                         algo = "sha256", serialize = FALSE)
gisaid_utf16 <- function(x) {
  unlist(lapply(utf8ToInt(enc2utf8(x)), function(cp) {
    if (cp <= 65535L) cp else c(55296L + (cp - 65536L) %/% 1024L, 56320L + (cp - 65536L) %% 1024L)
  }), use.names = FALSE)
}
# JavaScript sorts strings by UTF-16 code units, independently of the OS locale.
gisaid_sort <- function(x) x[order(vapply(x, function(s) paste(sprintf("%04x", gisaid_utf16(s)), collapse = ""),
                                        character(1)), method = "radix")]
gisaid_strings <- function(x, label) {
  if (!is.list(x) || !is.null(names(x)) ||
      any(!vapply(x, function(s) gisaid_string(s) && nzchar(gisaid_trim(s)), logical(1)))) {
    gisaid_fail("Invalid ", label, ".")
  }
  out <- as.character(unlist(x, use.names = FALSE))
  if (anyDuplicated(out)) gisaid_fail("Invalid ", label, ".")
  out
}
gisaid_config <- function(value, pathogen) {
  if (!gisaid_object(value) || !is.numeric(value$schema_version) ||
      !identical(as.numeric(value$schema_version), 1) || !gisaid_string(value$pathogen) ||
      !grepl("^[A-Za-z0-9_-]{1,48}$", value$pathogen) || value$pathogen != pathogen) {
    gisaid_fail("Invalid pathogen configuration.")
  }
  keys <- gisaid_strings(gisaid_default(value$key_columns, list(value$key_column)), "sample key columns")
  legacy <- gisaid_strings(gisaid_default(value$legacy_key_columns, list()), "legacy sample key columns")
  if (!length(keys) || length(keys) > 8L || !gisaid_string(value$csv_delimiter) ||
      !value$csv_delimiter %in% c(";", ",", "\t")) gisaid_fail("Invalid key or delimiter configuration.")
  if (length(legacy) > 8L || (length(legacy) && identical(keys, legacy))) {
    gisaid_fail("Legacy sample key columns must differ from the current sample key columns.")
  }
  options <- gisaid_strings(value$review_options, "review options")
  if (!"Approved" %in% options) gisaid_fail("Review options must include Approved.")
  edits <- gisaid_strings(value$edit_columns, "editable fields")
  if (any(edits %in% keys)) gisaid_fail("Sample identifiers cannot be manually changed.")
  gisaid_strings(value$default_columns, "default columns")
  gisaid_strings(gisaid_default(value$column_order, list()), "column order")
  legacy_edits <- gisaid_strings(gisaid_default(value$legacy_edit_columns, as.list(edits)), "legacy editable fields")
  colors <- gisaid_default(value$tree_colorings, list())
  if (!is.list(colors) || !is.null(names(colors)) || length(colors) > 30L) {
    gisaid_fail("tree_colorings must be a list of at most 30 columns.")
  }
  seen <- character()
  hex <- function(x) gisaid_string(x) && grepl("^#[0-9a-fA-F]{6}$", x)
  for (entry in colors) {
    if (!gisaid_object(entry) || !gisaid_string(entry$column) || !nzchar(gisaid_trim(entry$column)) ||
        length(gisaid_utf16(entry$column)) > 256L || entry$column %in% seen) {
      gisaid_fail("Each tree coloring needs a unique column name.")
    }
    seen <- c(seen, entry$column)
    title <- gisaid_default(entry$title, entry$column)
    type <- gisaid_default(entry$type, "categorical")
    if (!gisaid_string(title) || !nzchar(gisaid_trim(title)) || length(gisaid_utf16(title)) > 256L ||
        !gisaid_string(type) || !type %in% c("categorical", "continuous")) gisaid_fail("Invalid tree coloring title or type.")
    if ("colors" %in% names(entry) && (type != "categorical" || !gisaid_object(entry$colors) ||
        any(!vapply(entry$colors, hex, logical(1))))) gisaid_fail("Invalid categorical colors.")
    if ("range" %in% names(entry) && (type != "continuous" || !is.list(entry$range) ||
        !is.null(names(entry$range)) || length(entry$range) != 2L ||
        any(!vapply(entry$range, hex, logical(1))))) gisaid_fail("Invalid continuous color range.")
  }
  value$key_columns <- keys
  value$legacy_key_columns <- legacy
  value$review_options <- options
  value$edit_columns <- edits
  value$legacy_edit_columns <- legacy_edits
  value
}
gisaid_read_bytes <- function(path, limit = Inf) {
  if (!file.exists(path) || dir.exists(path) || file.access(path, 4L) != 0L) {
    gisaid_fail("Cannot read file: ", path)
  }
  size <- file.info(path)$size
  if (!is.finite(size) || size > limit) gisaid_fail("Input exceeds the supported size limit: ", path)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", n = if (is.finite(limit)) limit + 1 else size + 1)
  if (length(bytes) > limit) gisaid_fail("Input exceeds the supported size limit: ", path)
  bytes
}
gisaid_decode_utf8 <- function(bytes) {
  text <- iconv(rawToChar(bytes), from = "UTF-8", to = "UTF-8", sub = NA_character_)
  if (is.na(text)) gisaid_fail("Input is not valid UTF-8.")
  sub("^\ufeff", "", text)
}
gisaid_read_snapshot <- function(master) {
  base <- dirname(master)
  directory <- file.path(base, "reviews")
  if (!dir.exists(directory) || file.access(directory, 4L) != 0L) {
    gisaid_fail("Cannot read Sequence Review directory: ", directory)
  }
  files <- list.files(directory, pattern = "\\.json$", all.files = TRUE, no.. = TRUE)
  paths <- file.path(directory, files)
  links <- Sys.readlink(paths)
  files <- gisaid_sort(files[!file.info(paths)$isdir & (is.na(links) | links == "")])
  if (length(files) > 20000L) gisaid_fail("Review history exceeds the supported 20,000 events.")
  config <- gisaid_read_bytes(file.path(base, "config.json"), 256000)
  csv <- gisaid_read_bytes(master, 32 * 1024 * 1024)
  events <- lapply(file.path(directory, files), gisaid_read_bytes, limit = 256000)
  hashes <- lapply(seq_along(files), function(i) list(files[i], gisaid_sha256(events[[i]])))
  token <- gisaid_sha256(gisaid_json(list(gisaid_sha256(config), gisaid_sha256(csv), hashes)))
  decode_json <- function(bytes) jsonlite::fromJSON(gisaid_decode_utf8(bytes), simplifyVector = FALSE)
  list(config = decode_json(config), csv = gisaid_decode_utf8(csv), events = lapply(events, decode_json),
       token = token, master_sha256 = gisaid_sha256(csv))
}
# Strict CSV scanner: preserve text, quoted newlines, CRLF and leading zeroes.
# Scan only structural bytes rather than building strings one character at a time.
gisaid_parse_csv <- function(text, delimiter) {
  bytes <- charToRaw(enc2utf8(sub("^\ufeff", "", text)))
  n <- length(bytes)
  separator <- charToRaw(delimiter)
  positions <- which(bytes %in% c(separator, as.raw(c(34L, 13L, 10L))))
  records <- list(); fields <- character(); start <- 1L; skip <- 0L; quoted <- FALSE
  append_cell <- function(end) {
    value <- if (end >= start) rawToChar(bytes[start:end]) else ""
    Encoding(value) <- "UTF-8"
    if (startsWith(value, '"')) value <- gsub('""', '"', substr(value, 2L, nchar(value) - 1L), fixed = TRUE)
    fields <<- c(fields, value)
    if (length(fields) > 1000L) gisaid_fail("CSV exceeds 1,000 columns.")
  }
  append_record <- function() {
    if (any(nzchar(fields))) records[[length(records) + 1L]] <<- fields
    fields <<- character()
    if (length(records) > 50001L) gisaid_fail("CSV exceeds 50,000 rows.")
  }
  malformed <- function(message, position) {
    prefix <- if (position > 1L) rawToChar(bytes[seq_len(position - 1L)]) else ""
    lines <- gregexpr("\r\n|\r|\n", prefix, perl = TRUE)[[1]]
    line <- 1L + if (lines[1] < 0L) 0L else length(lines)
    gisaid_fail(message, " Line ", line, ", CSV column ", length(fields) + 1L, ".")
  }
  for (i in positions) {
    if (i <= skip) next
    b <- bytes[i]
    if (quoted) {
      if (b == as.raw(34L)) {
        if (i < n && bytes[i + 1L] == as.raw(34L)) skip <- i + 1L else {
          quoted <- FALSE
          if (i < n && !bytes[i + 1L] %in% c(separator, as.raw(c(13L, 10L)))) {
            malformed("Malformed CSV: characters after a closing quote.", i + 1L)
          }
        }
      }
    } else if (b == separator || b %in% as.raw(c(13L, 10L))) {
      append_cell(i - 1L)
      if (b != separator) {
        append_record()
        if (b == as.raw(13L) && i < n && bytes[i + 1L] == as.raw(10L)) skip <- i + 1L
      }
      start <- max(i, skip) + 1L
    } else {
      if (i != start) malformed("Malformed CSV quote.", i)
      quoted <- TRUE
      quote_start <- i
    }
  }
  if (quoted) malformed("Malformed CSV: unclosed quote.", quote_start)
  if (start <= n || length(fields)) {append_cell(n); append_record()}
  if (!length(records) || any(!nzchar(gisaid_trim(records[[1]]))) || anyDuplicated(records[[1]])) {
    gisaid_fail("CSV needs unique, nonempty headers (at most 1,000).")
  }
  headers <- records[[1]]
  records <- records[-1L]
  for (i in seq_along(records)) {
    if (length(records[[i]]) != length(headers)) gisaid_fail("Incorrect column count on row ", i + 1L, ".")
  }
  matrix <- if (length(records)) do.call(rbind, records) else matrix(character(), 0L, length(headers))
  rows <- as.data.frame(matrix, stringsAsFactors = FALSE, optional = TRUE)
  names(rows) <- headers
  list(headers = headers, rows = rows)
}
gisaid_key <- function(row, keys) {
  parts <- unname(unlist(row[keys], use.names = FALSE))
  if (length(parts) != length(keys) || anyNA(parts) || any(!nzchar(gisaid_trim(parts)))) {
    gisaid_fail("Empty sample identifier in ", paste(keys, collapse = " + "), ".")
  }
  if (length(parts) == 1L) parts else gisaid_json(as.list(parts))
}
gisaid_fingerprint <- function(row, headers, keys) {
  # Callers supply headers already in JavaScript order, shared across all rows.
  columns <- headers[!headers %in% keys & vapply(row[headers], nzchar, logical(1))]
  pairs <- lapply(columns, function(column) list(column, row[[column]]))
  paste0("sha256:", gisaid_sha256(gisaid_json(pairs)))
}
gisaid_event <- function(event, cfg) {
  timestamp_ok <- function(s) {
    if (!gisaid_string(s) || !grepl("^\\d{4}-\\d{2}-\\d{2}([Tt]\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?([Zz]|[+-]\\d{2}:?\\d{2})?)?$", s)) return(FALSE)
    # Persisted review events use ISO 8601. Validate the entire offset and time,
    # rather than silently accepting a valid date prefix of a corrupt timestamp.
    if (grepl("[+-]\\d{2}:?\\d{2}$", s)) {
      offset <- gsub(":", "", sub("^.*([+-]\\d{2}:?\\d{2})$", "\\1", s))
      if (as.integer(substr(offset, 2L, 3L)) > 23L || as.integer(substr(offset, 4L, 5L)) > 59L) return(FALSE)
    }
    date <- suppressWarnings(as.Date(substr(s, 1L, 10L), "%Y-%m-%d"))
    if (is.na(date)) return(FALSE)
    if (nchar(s) == 10L) return(TRUE)
    hour <- as.integer(substr(s, 12L, 13L)); minute <- as.integer(substr(s, 15L, 16L))
    second <- if (substr(s, 17L, 17L) == ":") as.numeric(sub("[Zz+-].*$", "", substring(s, 18L))) else 0
    hour <= 24L && minute <= 59L && second < 60 && (hour < 24L || (minute == 0L && second == 0))
  }
  if (!gisaid_object(event) || !is.numeric(event$format_version) ||
      !identical(as.numeric(event$format_version), 1) || !identical(event$pathogen, cfg$pathogen) ||
      !gisaid_string(event$id) || !grepl("^[A-Za-z0-9_-]{1,160}$", event$id) ||
      !gisaid_string(event$key) || !nzchar(gisaid_trim(event$key)) || !gisaid_string(event$result_hash) ||
      !grepl("^sha256:[a-f0-9]{64}$", event$result_hash) || !timestamp_ok(event$created_at) ||
      !gisaid_object(event$review)) gisaid_fail("Invalid review identity, fingerprint or timestamp.")
  event$supersedes <- gisaid_strings(event$supersedes, "review parents")
  if ("key_columns" %in% names(event) &&
      !identical(gisaid_strings(event$key_columns, "review key columns"), cfg$key_columns)) {
    gisaid_fail("Review identifier columns do not match the dataset configuration.")
  }
  review <- event$review
  comment <- gisaid_default(review$comment, "")
  if (!gisaid_string(review$reviewer) || !nzchar(gisaid_trim(review$reviewer)) ||
      length(gisaid_utf16(review$reviewer)) > 80L || !gisaid_string(review$assessment) ||
      !review$assessment %in% cfg$review_options || !gisaid_string(comment) ||
      length(gisaid_utf16(comment)) > 32000L || !gisaid_object(review$overrides)) gisaid_fail("Invalid review decision or reviewer.")
  policy <- !is.null(event$policy_version) && !identical(event$policy_version, "") && !identical(event$policy_version, FALSE)
  if (policy && !identical(event$policy_version, gisaid_default(cfg$review_policy_version, "legacy-v1"))) {
    gisaid_fail("Unknown review policy version.")
  }
  allowed <- if (policy) cfg$edit_columns else cfg$legacy_edit_columns
  for (column in names(review$overrides)) {
    value <- review$overrides[[column]]
    if (column %in% cfg$key_columns || !column %in% allowed || !gisaid_string(value) ||
        length(gisaid_utf16(value)) > 32000L) gisaid_fail("Review contains an unsupported manual field. Check the historical field policy.")
  }
  event
}
gisaid_load_approved_master <- function(master, pathogen) {
  gisaid_require_packages()
  if (!pathogen %in% c("INF", "SC2")) gisaid_fail("Expected pathogen INF or SC2.")
  master <- normalizePath(master, winslash = "/", mustWork = TRUE)
  raw <- gisaid_read_snapshot(master)
  cfg <- gisaid_config(raw$config, pathogen)
  parsed <- gisaid_parse_csv(raw$csv, cfg$csv_delimiter)
  missing <- setdiff(cfg$key_columns, parsed$headers)
  if (length(missing)) gisaid_fail("CSV is missing a configured sample key column: ", paste(missing, collapse = ", "), ".")
  rows <- lapply(seq_len(nrow(parsed$rows)), function(i) as.list(parsed$rows[i, , drop = FALSE]))
  keys <- vapply(rows, gisaid_key, character(1), keys = cfg$key_columns)
  if (anyDuplicated(keys)) gisaid_fail("Duplicate sample identifier in CSV (", paste(cfg$key_columns, collapse = " + "), ").")
  legacy_keys <- NULL
  hash_headers <- gisaid_sort(parsed$headers)
  events <- lapply(raw$events, function(event) {
    if (!gisaid_object(event)) gisaid_fail("Invalid review identity, fingerprint or timestamp.")
    # Internal identity state must never be accepted from a review JSON file.
    event$gisaid_legacy_identity <- FALSE
    source <- gisaid_default(event$key_columns, as.list(if (length(cfg$legacy_key_columns)) cfg$legacy_key_columns else cfg$key_columns))
    source <- gisaid_strings(source, "review key columns")
    if (identical(source, cfg$key_columns)) return(gisaid_event(event, cfg))
    if (!length(cfg$legacy_key_columns) || !identical(source, cfg$legacy_key_columns)) {
      gisaid_fail("Review identifier columns do not match the current or configured legacy identifiers.")
    }
    legacy_cfg <- cfg
    legacy_cfg$key_columns <- cfg$legacy_key_columns
    event <- gisaid_event(event, legacy_cfg)
    if (is.null(legacy_keys)) {
      if (any(!cfg$legacy_key_columns %in% parsed$headers)) gisaid_fail("The CSV is missing legacy identifier columns needed to link existing reviews.")
      legacy_keys <<- vapply(rows, gisaid_key, character(1), keys = cfg$legacy_key_columns)
      if (anyDuplicated(legacy_keys)) gisaid_fail("Duplicate legacy identifier: existing reviews cannot be linked safely.")
    }
    index <- match(event$key, legacy_keys)
    if (is.na(index)) gisaid_fail("An existing review has no matching legacy identifier in the current master CSV. Restore its mapping before changing identifiers.")
    event$key <- keys[index]
    event$key_columns <- as.list(cfg$key_columns)
    event$gisaid_legacy_identity <- TRUE
    # The core validates translated overrides against current identifiers too.
    event$supersedes <- as.list(event$supersedes)
    gisaid_event(event, cfg)
  })
  ids <- vapply(events, `[[`, character(1), "id")
  if (anyDuplicated(ids)) gisaid_fail("Duplicate review IDs.")
  id_index <- new.env(hash = TRUE, parent = emptyenv())
  for (i in seq_along(ids)) id_index[[ids[i]]] <- i
  indegree <- vapply(events, function(e) length(e$supersedes), integer(1))
  superseded <- rep(FALSE, length(events))
  children <- vector("list", length(events))
  for (i in seq_along(events)) {
    for (parent in events[[i]]$supersedes) {
      p <- id_index[[parent]]
      if (is.null(p) || events[[p]]$key != events[[i]]$key || p == i) gisaid_fail("Review history has a missing or unrelated parent.")
      superseded[p] <- TRUE
      children[[p]] <- c(children[[p]], i)
    }
  }
  queue <- which(indegree == 0L)
  cursor <- 1L
  while (cursor <= length(queue)) {
    for (child in children[[queue[cursor]]]) {
      indegree[child] <- indegree[child] - 1L
      if (indegree[child] == 0L) queue <- c(queue, child)
    }
    cursor <- cursor + 1L
  }
  if (length(queue) != length(events)) gisaid_fail("Review history contains a cycle.")
  heads <- new.env(hash = TRUE, parent = emptyenv())
  for (i in which(!superseded)) heads[[events[[i]]$key]] <- c(heads[[events[[i]]$key]], i)
  counts <- list(total = length(rows), approved = 0L, pending = 0L, stale = 0L, conflict = 0L, not_approved = 0L)
  approvals <- list(); selected <- integer()
  effective <- parsed$rows
  for (i in seq_along(rows)) {
    head <- heads[[keys[i]]]
    state <- if (length(head) > 1L) "conflict" else if (!length(head)) "pending" else {
      event <- events[[head]]
      hash_keys <- if (isTRUE(event$gisaid_legacy_identity)) cfg$legacy_key_columns else cfg$key_columns
      if (identical(event$result_hash, gisaid_fingerprint(rows[[i]], hash_headers, hash_keys))) "valid" else "stale"
    }
    if (state != "valid") {counts[[state]] <- counts[[state]] + 1L; next}
    if (event$review$assessment != "Approved") {counts$not_approved <- counts$not_approved + 1L; next}
    counts$approved <- counts$approved + 1L
    selected <- c(selected, i)
    for (column in intersect(names(event$review$overrides), parsed$headers)) effective[[column]][i] <- event$review$overrides[[column]]
    approvals[[length(approvals) + 1L]] <- list(key = keys[i], event_id = event$id, result_hash = event$result_hash)
  }
  if (!identical(gisaid_read_snapshot(master)$token, raw$token)) gisaid_fail("Master or review history changed while reading; retry.")
  identity_headers <- c("review_key", "Key", "Prove_LW_ID", "NGS_LW_ID", "OriginalName", "SampleID")
  identities <- as.data.frame(setNames(lapply(identity_headers, function(column) {
    if (column == "review_key") keys else if (column %in% parsed$headers) parsed$rows[[column]] else rep("", length(rows))
  }), identity_headers), stringsAsFactors = FALSE, check.names = FALSE)
  list(headers = parsed$headers, rows = effective[selected, , drop = FALSE], identities = identities,
       counts = counts, approvals = approvals, token = raw$token, master_sha256 = raw$master_sha256,
       identity_headers = identity_headers)
}
read_approved_master <- function(master, pathogen) {
  tryCatch({
    result <- gisaid_load_approved_master(master, pathogen)
    message("Sequence Review approval filter: ", gisaid_json(result$counts))
    result
  }, error = function(e) gisaid_fail("Sequence Review approval check failed; no submission was written.\n", conditionMessage(e)))
}
assert_approved_master <- function(master, pathogen, token) {
  fresh <- read_approved_master(master, pathogen)
  if (!identical(fresh$token, token)) gisaid_fail("Master or reviews changed during export; regenerate the submission. No submission was written.")
  invisible(TRUE)
}
