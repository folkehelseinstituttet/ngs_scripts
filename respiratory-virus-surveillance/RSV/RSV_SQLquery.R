# RSV SQL query

source(file = "N:/Virologi/Influensa/2526/WGS_Analyse/Scripts/SQL_address.R")

# Load required packages used by the query pipeline.
library(dplyr)
library(tidyr)
library(janitor)
library(lubridate)
library(dbplyr)

safe_utf8 <- function(x) {
  x <- as.character(x)
  y <- iconv(x, from = "", to = "UTF-8", sub = NA)
  bad <- is.na(y)
  if (any(bad)) {
    # Fallback for legacy DB values/headers stored in Latin-1/Windows-1252.
    y[bad] <- iconv(x[bad], from = "latin1", to = "UTF-8", sub = "")
  }
  y[is.na(y)] <- ""
  y
}

safe_parse_date <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_
  parsed <- suppressWarnings(lubridate::parse_date_time(
    x,
    orders = c("Y-m-d", "d.m.Y", "d/m/Y", "Y/m/d")
  ))
  as.Date(parsed)
}

safe_num <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

# Extract and process entry information fields.
entryinf <- tbl(conRSV2324, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect() %>%
  mutate(
    DISPNAME = safe_utf8(DISPNAME),
    NAME = safe_utf8(NAME)
  )

# Extract and process entry fields.
entryfld <- tbl(conRSV2324, "ENTRYFLD") %>%
  collect() %>%
  left_join(entryinf, by = "FIELDID") %>%
  mutate(FIELDID = DISPNAME) %>%
  pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(
    everything(),
    ~ ifelse(all(is.na(.x)), NA, paste(na.omit(.x), collapse = ";"))
  ))

names(entryfld) <- safe_utf8(names(entryfld))

# Extract entry table.
entrytable <- tbl(conRSV2324, "ENTRYTABLE") %>%
  collect()
names(entrytable) <- safe_utf8(names(entrytable))

# Get the mapping of DISPNAME to column names.
name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

# Replace column names in entrytable with DISPNAME from entryinf.
entrytable <- entrytable %>%
  rename_with( ~ ifelse(
    . %in% name_mapping$NAME,
    as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]),
    .
  ), .cols = everything())

# Normalize potentially mixed encodings in column names before clean_names().
names(entrytable) <- safe_utf8(names(entrytable))
names(entryfld) <- safe_utf8(names(entryfld))

entrytable_cols <- names(entrytable)
entryfld_cols <- names(entryfld)

# Find duplicated columns between entrytable and entryfld.
duplicated_cols <- intersect(entrytable_cols, entryfld_cols)

# Keep KEY and remove duplicated columns from entrytable before merge.
filtered_entrytable <- entrytable %>% select(-all_of(duplicated_cols), KEY)

# Merge and normalize column names.
rsvdb <- left_join(filtered_entrytable, entryfld, by = "KEY") %>%
  clean_names() %>%
  select(-any_of(c(
    "levelid", "prkey", "endtcreated", "endtmodif",
    "objactionid", "objlck", "objowner", "objshared"
  )))

# Normalize all character fields to UTF-8 to avoid downstream string warnings.
rsvdb <- rsvdb %>%
  mutate(across(where(is.character), safe_utf8))

# Add date-derived helper columns when prove_tatt is available.
if ("prove_tatt" %in% names(rsvdb)) {
  rsvdb <- rsvdb %>%
    mutate(
      prove_tatt = na_if(prove_tatt, ""),
      prove_tatt = safe_parse_date(prove_tatt),
      week = week(prove_tatt),
      year = year(prove_tatt),
      wy = sprintf("%d-W%02d", isoyear(prove_tatt), isoweek(prove_tatt)),
      my = format(prove_tatt, "%Y-%m")
    )
}

if (exists("close_sql_connections")) close_sql_connections()

rm(
  entrytable, entryfld, entryinf, name_mapping,
  filtered_entrytable, duplicated_cols, entryfld_cols,
  entrytable_cols, conRSV2324
)
