# Locate the R-only Sequence Review reader in the complete ngs_scripts checkout.
nextstrain_approval_helper <- local({
  source_files <- unlist(lapply(sys.frames(), function(frame) {
    value <- get0("ofile", envir = frame, inherits = FALSE)
    if (is.character(value)) value else character()
  }), use.names = FALSE)
  cli_files <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  scripts <- c(rev(source_files), cli_files)
  scripts <- scripts[!is.na(scripts) & nzchar(scripts)]
  override <- Sys.getenv("GISAID_SHARED_DIR", unset = "")
  if (nzchar(override)) {
    candidates <- file.path(override, "approval.R")
  } else {
    candidates <- c(file.path(dirname(scripts), "..", "..", "gisaid", "shared", "approval.R"),
      file.path(getwd(), "gisaid", "shared", "approval.R"),
      file.path(getwd(), "..", "gisaid", "shared", "approval.R"),
      file.path(getwd(), "..", "..", "gisaid", "shared", "approval.R"),
      "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/shared/approval.R")
  }
  available <- candidates[file.exists(candidates)]
  if (!length(available)) stop("Cannot locate the R-only Sequence Review reader. Keep the complete ngs_scripts checkout, or set GISAID_SHARED_DIR to gisaid/shared.", call. = FALSE)
  normalizePath(available[1L], winslash = "/", mustWork = TRUE)
})
source(nextstrain_approval_helper, encoding = "UTF-8")
if (!identical(names(formals(read_approved_master)), c("master", "pathogen"))) {
  stop("Outdated Sequence Review reader: ", nextstrain_approval_helper,
       ". Update the complete checkout to the R-only version.", call. = FALSE)
}

# Approved master-based SC2 Nextstrain inputs. No SQL connection or Node.js.
# Rscript SC2_META.R [--min-date YYYY-MM-DD] [--master master.csv] [--fasta master.fasta]
#                       [--lab Innsender_GISAID.csv] [--output directory]
source(file.path(dirname(nextstrain_approval_helper), "..", "sars-cov-2", "sc2_export.R"), encoding = "UTF-8")

parse_options <- function(args) {
  defaults <- sc2_gisaid_defaults()
  opts <- list(master = defaults$master, fasta = NULL, lab = defaults$lab_lookup,
    output = "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-Nextstrain",
    min_date = "2025-01-01")
  if (any(args %in% c("-h", "--help"))) {
    cat("Usage: Rscript SC2_META.R [--min-date YYYY-MM-DD] [--master master.csv]\n",
      "       [--fasta master.fasta] [--lab Innsender_GISAID.csv] [--output directory]\n",
      "The first positional argument may also specify the minimum date.\n", sep = "")
    return(NULL)
  }
  if (length(args) && !startsWith(args[1L], "--")) {
    opts$min_date <- args[1L]
    args <- args[-1L]
  }
  if (length(args) %% 2L) stop("Each option requires a value; use --help.", call. = FALSE)
  used <- character()
  if (length(args)) for (i in seq.int(1L, length(args), by = 2L)) {
    name <- gsub("-", "_", sub("^--", "", args[i]), fixed = TRUE)
    if (!startsWith(args[i], "--") || !name %in% names(opts) || name %in% used || !nzchar(args[i + 1L])) {
      stop("Unknown or repeated option, or missing value: ", args[i], call. = FALSE)
    }
    opts[name] <- list(args[i + 1L]); used <- c(used, name)
  }
  date <- if (grepl("^\\d{4}-\\d{2}-\\d{2}$", opts$min_date)) suppressWarnings(as.Date(opts$min_date, "%Y-%m-%d")) else as.Date(NA)
  if (is.na(date) || format(date, "%Y-%m-%d") != opts$min_date) stop("--min-date must be YYYY-MM-DD.", call. = FALSE)
  if (is.null(opts$fasta)) opts$fasta <- file.path(dirname(opts$master), "master.fasta")
  opts
}
nextstrain_col <- function(x, name, default = "") {
  if (name %in% names(x)) x[[name]] else rep(default, nrow(x))
}
prepare_sc2_nextstrain <- function(snapshot, records, labs, min_date) {
  x <- snapshot$rows
  if (anyDuplicated(tolower(names(x)))) stop("Master CSV has duplicate column names.", call. = FALSE)
  names(x) <- tolower(names(x))
  required <- c("key", "prove_tatt", "nc_coverage", "pasient_fylke_name", "prove_innsender_id")
  sc2_require_columns(names(x), required, "SC2 master")
  dates <- suppressWarnings(as.Date(x$prove_tatt, "%Y-%m-%d"))
  coverage <- suppressWarnings(as.numeric(gsub(",", ".", x$nc_coverage, fixed = TRUE)))
  selected <- which(!is.na(dates) & dates > as.Date(min_date) & is.finite(coverage) & coverage >= 0.75)
  x <- x[selected, , drop = FALSE]
  approvals <- snapshot$approvals[selected]
  missing_key <- is.na(x$key) | !nzchar(trimws(x$key))
  if (any(missing_key)) message("Skipping ", sum(missing_key), " eligible rows with no Key.")
  x <- x[!missing_key, , drop = FALSE]; approvals <- approvals[!missing_key]
  if (!nrow(x)) stop("No currently approved samples remain after Nextstrain date, coverage and Key filters.", call. = FALSE)
  if (anyDuplicated(x$key)) stop("Eligible samples have duplicate Key values.", call. = FALSE)
  sequences <- sc2_match_sequences(approvals, snapshot$identities, records)
  names <- paste("hCoV-19", "Norway", substring(x$key, pmax(1L, nchar(x$key) - 3L)),
                 format(as.Date(x$prove_tatt, "%Y-%m-%d"), "%Y"), sep = "/")
  if (any(grepl("[[:space:]>]", names)) || anyDuplicated(names)) stop("Eligible samples have invalid or duplicate isolate names.", call. = FALSE)
  gender <- toupper(nextstrain_col(x, if ("pasient_kjnn" %in% names(x)) "pasient_kjnn" else "pasient_kjonn"))
  category <- nextstrain_col(x, "prove_kategori")
  status <- nextstrain_col(x, "pasient_status")
  purpose <- ifelse(category == "P1_", "Sentinel surveillance (ARI)",
    ifelse(category == "P2_" & status == "Poliklinisk", "Non-sentinel surveillance (outpatient)",
    ifelse(status == "Inneliggende", "Non-sentinel surveillance (hospital)", "")))
  accession <- rep("", nrow(x))
  for (column in intersect(c("gisaid_isolate_id", "epi_isl", "gisaid_epi_isl", "gisaid_accession", "gisaid_acc", "epi_isl_id"), names(x))) {
    values <- x[[column]]
    hit <- !nzchar(accession) & grepl("^EPI[_-]?ISL[_-]?\\d+$", values, ignore.case = TRUE)
    accession[hit] <- values[hit]
  }
  division <- vapply(x$pasient_fylke_name, sc2_repair_county, character(1))
  lab_names <- vapply(trimws(x$prove_innsender_id), function(code) {
    lab <- if (nzchar(code)) labs[[code]] else NULL
    if (is.null(lab)) "" else lab$name
  }, character(1), USE.NAMES = FALSE)
  ordered <- lapply(approvals, function(review) sequences[[review$key]])
  metadata <- data.frame(strain = names, virus = "SARS-CoV-2", gisaid_epi_isl = accession,
    date = format(as.Date(x$prove_tatt, "%Y-%m-%d"), "%Y-%m-%d"), region = "Europe", country = "Norway",
    division = division, location = nextstrain_col(x, "pasient_kommune_name"), region_exposure = "Europe",
    country_exposure = "Norway", division_exposure = division, segment = "genome",
    length = vapply(ordered, function(record) nchar(record$sequence), integer(1)), host = "Human",
    age = nextstrain_col(x, "pasient_alder"), sex = ifelse(gender == "M", "male", ifelse(gender == "F", "female", "")),
    pangolin_lineage = nextstrain_col(x, "nc_pangolin_long"), GISAID_clade = nextstrain_col(x, "gisaid_clade"),
    originating_lab = lab_names, submitting_lab = "Norwegian Institute of Public Health, Department of Virology",
    authors = "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF",
    url = "", title = "", paper_url = "", date_submitted = "", purpose_of_sequencing = purpose,
    stringsAsFactors = FALSE, check.names = FALSE)
  fasta <- unlist(lapply(seq_along(ordered), function(i) c(paste0(">", names[i]), ordered[[i]]$sequence)), use.names = FALSE)
  list(metadata = metadata, fasta = fasta)
}
main <- function(args = commandArgs(trailingOnly = TRUE)) {
  opts <- parse_options(args)
  if (is.null(opts)) return(invisible(NULL))
  snapshot <- read_approved_master(opts$master, "SC2")
  fasta_bytes <- gisaid_read_bytes(opts$fasta)
  lab_bytes <- gisaid_read_bytes(opts$lab)
  prepared <- prepare_sc2_nextstrain(snapshot, sc2_read_fasta(fasta_bytes), sc2_lab_lookup(lab_bytes), opts$min_date)
  assert_approved_master(opts$master, "SC2", snapshot$token)
  if (!identical(gisaid_read_bytes(opts$fasta), fasta_bytes) || !identical(gisaid_read_bytes(opts$lab), lab_bytes)) {
    stop("FASTA or lab lookup changed during export; retry.", call. = FALSE)
  }
  if (!dir.exists(opts$output) && !dir.create(opts$output, recursive = TRUE)) stop("Cannot create output directory.", call. = FALSE)
  metadata_path <- file.path(opts$output, paste0("nextstrain_metadata_", format(Sys.Date(), "%Y-%m-%d"), ".tsv"))
  fasta_path <- file.path(opts$output, paste0("nextstrain_fasta", format(Sys.Date(), "%U-%Y"), ".fasta"))
  write.table(prepared$metadata, metadata_path, sep = "\t", quote = TRUE, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  writeLines(prepared$fasta, fasta_path, useBytes = TRUE)
  message("Nextstrain metadata and FASTA written to: ", opts$output)
  invisible(prepared)
}
if (sys.nframe() == 0L) main() else if (exists("nextstrain_args", inherits = FALSE)) main(nextstrain_args)
