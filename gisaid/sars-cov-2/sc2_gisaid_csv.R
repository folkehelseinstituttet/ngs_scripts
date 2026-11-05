# R-only SC2 GISAID export. Usage: Rscript sc2_gisaid_csv.R RUNID USER [options]
# In RStudio set gisaid_args <- c("RUNID", "USER") before source().
# Assembly method defaults to ARTIC 1.6.2; --assembly-method METHOD overrides it.
args <- if (exists("gisaid_args", inherits = FALSE)) gisaid_args else commandArgs(trailingOnly = TRUE)
locate_gisaid_shared <- function() {
  complete <- function(directory) all(file.exists(file.path(directory, "approval.R"))) &&
    file.exists(file.path(directory, "..", "sars-cov-2", "sc2_export.R"))
  override <- Sys.getenv("GISAID_SHARED_DIR", unset = "")
  if (nzchar(override)) {
    if (!complete(override)) stop("GISAID_SHARED_DIR must point to the complete gisaid/shared directory.", call. = FALSE)
    return(normalizePath(override, mustWork = TRUE))
  }
  source_files <- unlist(lapply(sys.frames(), function(frame) {
    value <- get0("ofile", envir = frame, inherits = FALSE)
    if (is.character(value)) value else character()
  }), use.names = FALSE)
  cli_files <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
  files <- c(rev(source_files), cli_files)
  files <- files[!is.na(files) & nzchar(files)]
  candidates <- c(file.path(dirname(files), "..", "shared"), file.path(getwd(), "gisaid", "shared"),
    file.path(getwd(), "shared"), file.path(getwd(), "..", "shared"),
    "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/shared")
  for (directory in unique(candidates)) if (complete(directory)) return(normalizePath(directory, mustWork = TRUE))
  stop("Cannot locate gisaid/shared. Source the full script path or set GISAID_SHARED_DIR to the complete shared directory.", call. = FALSE)
}
if (!is.character(args) || anyNA(args)) stop("gisaid_args must be a character vector without missing values.", call. = FALSE)
if (identical(args, "--help")) {
  cat("Usage: Rscript sc2_gisaid_csv.R RUNID USER [options]\n",
      "Options: --assembly-method --master --fasta --lab-lookup --output-dir --prefix --sequencing-technology --authors\n", sep = "")
} else {
  if (length(args) < 2L) stop('Provide RUNID USER, using Rscript or gisaid_args before source().', call. = FALSE)
  shared_dir <- locate_gisaid_shared()
  source(file.path(shared_dir, "approval.R"), encoding = "UTF-8")
  source(file.path(shared_dir, "..", "sars-cov-2", "sc2_export.R"), encoding = "UTF-8")
  options <- sc2_gisaid_defaults()
  options$run <- args[1L]; options$submitter <- args[2L]
  extra <- args[-c(1L, 2L)]
  allowed <- c("master", "fasta", "lab_lookup", "output_dir", "prefix", "assembly_method", "sequencing_technology", "authors")
  if (length(extra) %% 2L) stop("Every option needs a value.", call. = FALSE)
  used <- character()
  for (i in seq.int(1L, length(extra) + 1L, by = 2L)) {
    if (i > length(extra)) break
    name <- gsub("-", "_", substring(extra[i], 3L), fixed = TRUE)
    if (!startsWith(extra[i], "--") || !name %in% allowed || name %in% used) stop("Unknown or repeated option: ", extra[i], call. = FALSE)
    options[[name]] <- extra[i + 1L]
    used <- c(used, name)
  }
  manifest <- export_sc2_gisaid(options)
  cat(gisaid_json(manifest[c("samples", "approval_counts", "filter_counts")]), "\n", sep = "")
  message("Submission CSV, FASTA and manifest written to ", options$output_dir)
}
