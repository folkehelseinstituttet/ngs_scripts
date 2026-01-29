library(odbc)

# Version 1.1

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

outfile <- file.path(outdir, paste0(run_env, "/ToOrdinary", "/LW_Datauttrekk", "/test-connection.txt"))

## ==================================================
## Database connection test
## ==================================================

con <- tryCatch(
  {
    odbc::dbConnect(odbc::odbc(),
                    Driver = sqldriver,
                    Server = sqlserver,
                    Database = database
    )
  },
  error = function(e) {
    cat(
      "ERROR: Unable to connect to database.\n",
      "Environment: ", run_env, "\n",
      "Message: ", e$message, "\n", 
      file = outfile
    )
    stop("Connection failed")
  }
)
  
cat(
  "Connection successful!\n", 
  "Environment: ", run_env, "\n",
  file = outfile
)

## ==================================================
## Simple query test
## ==================================================

res <- tryCatch(
  dbGetQuery(con, "SELECT 1 AS test"),
  error = function(e) {
    cat("Query test failed:\n", e$message, "\n", file = outfile, append = TRUE)
    NULL
  }
)

if(!is.null(res)) cat("Test query result: ", paste(res$test, collapse = ","), "\n", file = outfile, append = TRUE)

## ==================================================
## Cleanup
## ==================================================

dbDisconnect(con)
cat("Connection closed.\n",
    file = outfile,
    append = TRUE
    )
