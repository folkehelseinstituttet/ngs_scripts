# Shared read-only approval gate for the master-based R exporter.
approval_command <- function(helper, master, pathogen, ...) {
  node <- Sys.getenv("GISAID_NODE", unset = "node")
  args <- c(helper, "--master", normalizePath(master, mustWork = TRUE), "--pathogen", pathogen, ...)
  status <- system2(node, vapply(args, shQuote, character(1)))
  if (status != 0L) stop("Sequence Review approval check failed; no submission was written.")
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
