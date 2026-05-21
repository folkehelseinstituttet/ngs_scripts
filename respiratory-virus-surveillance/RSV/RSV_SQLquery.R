# RSV 23-24 SQL query
# Self-contained script intended for sourcing by analysis/orchestration scripts.
# Responsibility: load raw SQL tables, apply duplicate-column harmonization, and output raw merged dataframe only.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(janitor)
  library(lubridate)
  library(dbplyr)
})

sql_address_local <- Sys.getenv(
  "RSV_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Source_files/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop("Local SQL address file not found. Set RSV_SQL_ADDRESS_FILE to your local SQL_address.R path.")
}
source(file = sql_address_local)

safe_utf8 <- function(x) {
  x <- as.character(x)
  y <- iconv(x, from = "", to = "UTF-8", sub = NA)
  bad <- is.na(y)
  if (any(bad)) y[bad] <- iconv(x[bad], from = "latin1", to = "UTF-8", sub = "")
  y[is.na(y)] <- ""
  y
}

collapse_duplicate_columns <- function(df) {
  dup_cols <- names(df)[duplicated(names(df))]
  for (col in unique(dup_cols)) {
    df <- df %>%
      mutate(!!sym(col) := apply(select(df, starts_with(col)), 1, function(x) {
        vals <- na.omit(x)
        if (length(vals) == 0) return(NA_character_)
        paste(vals, collapse = ";")
      })) %>%
      select(-matches(paste0("^", col, "\\..+")))
  }
  df
}

entryinf <- tbl(conRSV2324, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect() %>%
  mutate(DISPNAME = safe_utf8(DISPNAME), NAME = safe_utf8(NAME))

entryfld <- tbl(conRSV2324, "ENTRYFLD") %>%
  collect() %>%
  left_join(entryinf, by = "FIELDID") %>%
  mutate(FIELDID = DISPNAME) %>%
  pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(everything(), ~ ifelse(all(is.na(.x)), NA, paste(na.omit(.x), collapse = ";"))))

names(entryfld) <- safe_utf8(names(entryfld))
entryfld <- entryfld %>% collapse_duplicate_columns()

entrytable <- tbl(conRSV2324, "ENTRYTABLE") %>% collect()
names(entrytable) <- safe_utf8(names(entrytable))

name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

entrytable <- entrytable %>%
  rename_with(~ ifelse(. %in% name_mapping$NAME, as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]), .), .cols = everything())

names(entrytable) <- safe_utf8(names(entrytable))
entrytable <- entrytable %>% collapse_duplicate_columns()

duplicated_cols <- intersect(names(entrytable), names(entryfld))
filtered_entrytable <- entrytable %>% select(-all_of(duplicated_cols), KEY)

RSV_23_24_raw_merged <- left_join(filtered_entrytable, entryfld, by = "KEY") %>%
  clean_names()

rm(entrytable, entryfld, entryinf, name_mapping, filtered_entrytable, duplicated_cols)
