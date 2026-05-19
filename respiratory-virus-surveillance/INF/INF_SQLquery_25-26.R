# Load required libraries with reduced startup warning noise.
load_required_libraries <- function(packages) {
  lapply(packages, function(pkg) {
    withCallingHandlers(
      suppressPackageStartupMessages(library(pkg, character.only = TRUE)),
      warning = function(w) {
        if (grepl("was built under R version", conditionMessage(w), fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
  })
}

required_packages <- c("RSQLite", "lubridate", "tidyverse", "janitor", "base64enc", "odbc")
invisible(load_required_libraries(required_packages))

# Set locale for Norwegian Nynorsk (if supported)
Sys.setlocale(category = "LC_ALL", locale = "nno_NO.UTF-8")

# Source database connection script
sql_address_local <- Sys.getenv(
  "INF_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Scripts/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop("Local SQL address file not found. Set INF_SQL_ADDRESS_FILE to your local SQL_address.R path.")
}
source(sql_address_local)

# ---------------------------------------------------------------
# Load ENTRYINFOFIELDS and ENTRYFLD tables
# ---------------------------------------------------------------

# Load ENTRYINFOFIELDS and select relevant columns
entryinf <- tbl(conFLU2526, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect()

# Load ENTRYFLD table
entryfld <- tbl(conFLU2526, "ENTRYFLD") %>%
  collect()

# Keep DB text as delivered to avoid double-reencoding mojibake.

# Join ENTRYFLD with ENTRYINFOFIELDS and pivot wider
entryfld <- entryfld %>%
  left_join(entryinf, by = "FIELDID") %>%
  mutate(FIELDID = DISPNAME) %>%
  tidyr::pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(
    everything(),
    ~ if (all(is.na(.))) NA_character_ else paste(na.omit(.), collapse = ";")
  ))

# ---------------------------------------------------------------
# Load ENTRYTABLE and replace column names with DISPNAME
# ---------------------------------------------------------------

entrytable <- tbl(conFLU2526, "ENTRYTABLE") %>%
  collect()

# Keep DB text as delivered to avoid double-reencoding mojibake.

# Map SQL column names (NAME) to display names (DISPNAME)
name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

# Clean names
clean_names(name_mapping)
clean_names(entrytable)

# Rename columns in entrytable using mapping
entrytable <- entrytable %>%
  rename_with(
    ~ ifelse(. %in% name_mapping$NAME,
      as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]),
      .
    ),
    .cols = everything()
  )

# Handle duplicate column names by collapsing them into a single column
dup_cols <- names(entrytable)[duplicated(names(entrytable))]
for (col in dup_cols) {
  entrytable <- entrytable %>%
    mutate(!!sym(col) := apply(select(entrytable, starts_with(col)), 1, function(x) {
      paste(na.omit(x), collapse = ";")
    })) %>%
    select(-matches(paste0("^", col, "\\..+")))
}

# ---------------------------------------------------------------
# Merge ENTRYFLD and ENTRYTABLE
# ---------------------------------------------------------------

merged_df <- left_join(entryfld, entrytable, by = "KEY")

# Convert date column to Date object
merged_df$Prove_Tatt <- as.Date(merged_df$Prove_Tatt, format = "%Y-%m-%d")

# ---------------------------------------------------------------
# Filter rows for fludb
# ---------------------------------------------------------------

fludb <- merged_df %>%
  filter(NGS_Report == "") %>%
  filter(Prove_Kategori != "3") %>%
  filter(!str_detect(Prove_Kategori, regex("ref", ignore_case = TRUE))) %>%
  filter(Tessy_Reportable_Variable != "")

# Keep fludb values/column names untouched; normalize downstream only where needed.
fludb <- as.data.frame(fludb)
fludb <- clean_names(fludb)

# ---------------------------------------------------------------
# Load and process SEQUENCEDATA
# ---------------------------------------------------------------

filtered_seq <- tbl(conFLU2526, "SEQUENCEDATA") %>%
  collect() %>%
  inner_join(merged_df, by = "KEY") %>%
  filter(grepl("01-HA|02-NA|03-M|04-PB1|05-PB2|07-PA|06-NP|08-NS", EXPERIMENT)) %>%
  mutate(
    EXPERIMENT = str_remove(EXPERIMENT, "\\d+-"),
    EXPERIMENT = ifelse(EXPERIMENT == "M", "MP", EXPERIMENT)
  ) %>%
  filter(TYPE == "SEQUENCE") %>%
  select(KEY, EXPERIMENT, DATA)

# Function to decode and decompress gzipped Base64 sequence data
process_entry <- function(data_gz_base64) {
  tryCatch(
    {
      # Decode Base64
      data_gz_raw <- base64decode(data_gz_base64)

      # Decompress gzip
      data_decompressed <- memDecompress(data_gz_raw, type = "gzip")

      # Remove null bytes
      data_decompressed_no_nulls <- data_decompressed[data_decompressed != as.raw(0)]

      # Convert raw to character
      data_text_no_nulls <- rawToChar(data_decompressed_no_nulls)

      # Remove unwanted characters at beginning
      data_text_no_nulls_cleaned <- str_remove(data_text_no_nulls, "B0t")

      return(data_text_no_nulls_cleaned)
    },
    error = function(e) {
      message("Error processing entry: ", e$message)
      NA
    }
  )
}

# Apply decoding function to all sequence entries
filtered_seq <- filtered_seq %>%
  mutate(Sequence = map_chr(DATA, process_entry)) %>%
  mutate(Sequence = str_sub(Sequence, start = 3)) %>%
  select(KEY, EXPERIMENT, Sequence) %>%
  clean_names()

# ---------------------------------------------------------------
# Clean up
# ---------------------------------------------------------------

# Close database connections opened by SQL_address.R
connections_to_close <- c(
  "conSC22526",
  "conFLU2526",
  "conFLU2425",
  "conBNCOVID19"
)

invisible(lapply(connections_to_close, function(conn_name) {
  if (exists(conn_name, inherits = TRUE)) {
    conn <- get(conn_name, inherits = TRUE)
    if (DBI::dbIsValid(conn)) {
      DBI::dbDisconnect(conn)
    }
  }
}))

# Remove only temporary objects created by this script.
tmp_objects <- c(
  "entryinf",
  "entryfld",
  "entrytable",
  "name_mapping",
  "dup_cols",
  "merged_df",
  "connections_to_close",
  "sql_address_local"
)
rm(list = intersect(tmp_objects, ls()))
