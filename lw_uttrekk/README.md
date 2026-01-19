R-scripts for LabWare extractions are found in the separate folders with human readable names. 

Minimal requirements for R-scripts:

1. Load the odbc package
2. Connect to the LabWare database.
3. Close the connection when done.
4. Keep a script version that can be used to compare versions between GitHub and sikker sone.
5. Write a unique and descriptive output file. For FHI Statistikk this needs to be a csv-file with an accompanying ".ready" file. See examples below:  


Example template for FHI Statistikk:
```r
library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.0

outdir <- "OUTDIR_FHISTATISTIKK"
outfile <- file.path(outdir, paste0("HCV.csv"))

# Define the semafor file
readyfile <- sub("\\.csv$", ".ready", outfile)

# Remove the semafor file if it exists
if (file.exists(readyfile)) {
	unlink(readyfile)
}

# Establish connection to Lab Ware ----------------------------------------

con <- odbc::dbConnect(odbc::odbc(),
                       Driver = Sys.getenv("SQL_DRIVER"),
                       Server = Sys.getenv("SQL_SERVER"),
                       Database = Sys.getenv("SQL_DATABASE"))

# Do the data extractions here

# Close database connection
odbc::dbDisconnect(con)

# Prepare the data and the output file here

# Write the data file
write_delim(df,
            outfile,
            delim = ";",
            quote = "all"
            )

# Write the semafor file
file.create(readyfile)
```
  
Example template for scripts that produce files for internal use:
```r
library(odbc)
library(tidyverse)
library(lubridate)

# Script version 1.0

outdir <- "OUTDIR_ORD"
outfile <- file.path(outdir, paste0("My_outfile.csv"))


# Establish connection to Lab Ware ----------------------------------------

con <- odbc::dbConnect(odbc::odbc(),
                       Driver = Sys.getenv("SQL_DRIVER"),
                       Server = Sys.getenv("SQL_SERVER"),
                       Database = Sys.getenv("SQL_DATABASE"))

# Do the data extractions here

# Close database connection
odbc::dbDisconnect(con)

# Prepare the data and the output file here

# Write the data file
write_csv(df, outfile)
```