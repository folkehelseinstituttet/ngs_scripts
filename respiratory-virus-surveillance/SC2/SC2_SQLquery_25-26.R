# SC2 25-26 SQL query
# Self-contained script intended for sourcing by analysis/orchestration scripts.
# Responsibility: load raw SQL tables, apply duplicate-column harmonization, and output raw merged dataframe only.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(janitor)
  library(dbplyr)
})

disconnect_if_valid <- function(con_obj) {
  if (inherits(con_obj, "DBIConnection")) {
    tryCatch({
      if (DBI::dbIsValid(con_obj)) DBI::dbDisconnect(con_obj)
    }, error = function(e) NULL)
  }
  invisible(NULL)
}

sql_address_local <- Sys.getenv(
  "SC2_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Source_files/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop(
    "Local SQL address file not found. Set SC2_SQL_ADDRESS_FILE to your local SQL_address.R path."
  )
}
source(file = sql_address_local)

if (!inherits(conSC22526, "DBIConnection")) {
  stop("Failed to initialize connection object 'conSC22526'.")
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

entryinf <- tbl(conSC22526, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect()

entryfld <- tbl(conSC22526, "ENTRYFLD") %>%
  collect() %>%
  left_join(entryinf, by = "FIELDID") %>%
  mutate(FIELDID = DISPNAME) %>%
  pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(everything(), ~ ifelse(all(is.na(.x)), NA, paste(na.omit(.x), collapse = ";"))))

entrytable <- tbl(conSC22526, "ENTRYTABLE") %>% collect()

name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

entrytable <- entrytable %>%
  rename_with(~ ifelse(. %in% name_mapping$NAME, as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]), .), .cols = everything()) %>%
  collapse_duplicate_columns()

entryfld <- entryfld %>% collapse_duplicate_columns()

duplicated_cols <- intersect(names(entrytable), names(entryfld))
filtered_entrytable <- entrytable %>% select(-all_of(duplicated_cols), KEY)

SC2_25_26_raw_merged <- left_join(filtered_entrytable, entryfld, by = "KEY") %>%
  clean_names()

rm(entrytable, entryfld, entryinf, name_mapping, filtered_entrytable, duplicated_cols)
