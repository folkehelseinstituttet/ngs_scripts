# Script version 1.2

## ==================================================
## Validate required environment variables
## ==================================================

required_vars <- c(
  "OUTDIR",
  "SQL_DRIVER",
  "SQL_SERVER",
  "SQL_DATABASE",
  "RUN_ENV"
)

missing <- required_vars[Sys.getenv(required_vars) == ""]
if (length(missing) > 0) {
  stop(
    "Missing required environment variables: ",
    paste(missing, collapse = ", ")
  )
}

## ==================================================
## Resolve variables
## ==================================================

run_env   <- Sys.getenv("RUN_ENV")   # Test or Prod
outdir    <- Sys.getenv("OUTDIR")
sqldriver <- Sys.getenv("SQL_DRIVER")
sqlserver <- Sys.getenv("SQL_SERVER")
database  <- Sys.getenv("SQL_DATABASE")

## ==================================================
## Validate output directory
## ==================================================

if (!dir.exists(outdir)) {
  stop(
    "OUTDIR does not exist: ", outdir,
    "\nEnvironment: ", run_env
  )
}

# Name output file
outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/test_R_base.txt"))

# Create time stamp
ts <- format(Sys.time(), "%Y%m%d-%H%M%S")

cat(
"Rscript execution OK\n",
"Timestamp: ", ts, "\n",
"R version: ", R.version.string, "\n",
file = outfile
)

quit(status = 0)