# Shared read-only approval gate for the master-based R exporter.
approval_command <- function(helper, master, pathogen, ...) {
  node <- Sys.getenv("GISAID_NODE", unset = "node")
  executable <- unname(Sys.which(node))
  if (!nzchar(executable)) {
    stop("Node.js executable not found: ", node,
         ". Install Node.js 18+ or set GISAID_NODE to its executable path; no submission was written.",
         call. = FALSE)
  }
  args <- c(helper, "--master", normalizePath(master, mustWork = TRUE), "--pathogen", pathogen, ...)
  # Capture both streams so RStudio also includes the helper's reason in errors.
  stdout <- tempfile("gisaid-approval-stdout-")
  stderr <- tempfile("gisaid-approval-stderr-")
  on.exit(unlink(c(stdout, stderr)), add = TRUE)
  status <- tryCatch(
    system2(executable, vapply(args, shQuote, character(1)), stdout = stdout, stderr = stderr),
    error = function(e) stop("Could not run the Sequence Review approval check; no submission was written.\n",
                             conditionMessage(e), call. = FALSE)
  )
  read_log <- function(path) if (file.exists(path)) readLines(path, warn = FALSE) else character()
  output <- read_log(stdout)
  errors <- read_log(stderr)
  if (status != 0L) {
    details <- c(errors, output)
    details <- details[nzchar(trimws(details))]
    if (!length(details)) details <- "Node.js returned no diagnostic output."
    stop("Sequence Review approval check failed (exit status ", status,
         "); no submission was written.\n", paste(details, collapse = "\n"), call. = FALSE)
  }
  if (length(output)) cat(paste(output, collapse = "\n"), "\n", sep = "")
  if (length(errors)) message(paste(errors, collapse = "\n"))
  invisible(status)
}

read_approved_master <- function(helper, master, pathogen) {
  directory <- tempfile("gisaid-approved-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  approved <- file.path(directory, "approved.csv")
  identities <- file.path(directory, "identities.csv")
  token <- file.path(directory, "token.txt")
  approval_command(helper, master, pathogen, "--output", approved,
                   "--identities-output", identities, "--token-output", token)
  read <- function(file) read.csv(file, sep = ";", colClasses = "character", na.strings = character(),
                                   check.names = FALSE, fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
  list(rows = read(approved), identities = read(identities), token = readLines(token, warn = FALSE))
}
