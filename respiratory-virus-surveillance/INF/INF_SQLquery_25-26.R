# INF 25-26 SQL query
# Self-contained script intended for sourcing by analysis/orchestration scripts.
# Responsibility: load raw SQL tables, apply duplicate-column harmonization, and output raw merged dataframe only.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(janitor)
  library(odbc)
  library(dbplyr)
})

sql_address_local <- Sys.getenv(
  "INF_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Source_files/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop("Local SQL address file not found. Set INF_SQL_ADDRESS_FILE to your local SQL_address.R path.")
}
source(sql_address_local)

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

entryinf <- tbl(conFLU2526, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect()

entryfld <- tbl(conFLU2526, "ENTRYFLD") %>%
  collect() %>%
  left_join(entryinf, by = "FIELDID") %>%
  mutate(FIELDID = DISPNAME) %>%
  pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(everything(), ~ if (all(is.na(.))) NA_character_ else paste(na.omit(.), collapse = ";"))) %>%
  collapse_duplicate_columns()

entrytable <- tbl(conFLU2526, "ENTRYTABLE") %>% collect()

name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

entrytable <- entrytable %>%
  rename_with(~ ifelse(. %in% name_mapping$NAME, as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]), .), .cols = everything()) %>%
  collapse_duplicate_columns()

INF_25_26_raw_merged <- left_join(entryfld, entrytable, by = "KEY") %>%
  clean_names()

rm(entryinf, entryfld, entrytable, name_mapping)
