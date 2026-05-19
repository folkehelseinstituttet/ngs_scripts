#BN COVID SQL query


sql_address_local <- Sys.getenv(
  "SC2_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Source_files/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop("Local SQL address file not found. Set SC2_SQL_ADDRESS_FILE to your local SQL_address.R path.")
}
source(file = sql_address_local)

# Extract and process entry information fields
entryinf <- tbl(conSC22526, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect()


# Extract and process entry fields
entryfld <- tbl(conSC22526, 'ENTRYFLD') %>%
  collect() %>%
  left_join(entryinf, by = 'FIELDID') %>%
  mutate(FIELDID = DISPNAME) %>%
  pivot_wider(names_from = DISPNAME, values_from = CONTENT) %>%
  select(-OBJACTIONID, -FIELDID, -NAME) %>%
  group_by(KEY) %>%
  summarise(across(
    everything(),
    ~ ifelse(all(is.na(.x)), NA, paste(na.omit(.x), collapse = ";"))
  ))


# Extract entry table
entrytable <- tbl(conSC22526, "ENTRYTABLE") %>%
  collect()

# Get the mapping of DISPNAME to column names
name_mapping <- entryinf %>%
  filter(!is.na(DISPNAME)) %>%
  select(NAME, DISPNAME) %>%
  distinct()

# Replace column names in 'entrytable' dataframe with DISPNAME from 'entryinf'
entrytable <- entrytable %>%
  rename_with( ~ ifelse(
    . %in% name_mapping$NAME,
    as.character(name_mapping$DISPNAME[match(., name_mapping$NAME)]),
    .
  ), .cols = everything())


entrytable_cols <- names(entrytable)
entryfld_cols <- names(entryfld)

# Step 2: Find columns that are duplicated (i.e., present in both dataframes)
duplicated_cols <- intersect(entrytable_cols, entryfld_cols)

# Step 3: Filter entrytable to exclude duplicated columns
filtered_entrytable <- entrytable %>% select(-all_of(duplicated_cols), KEY)

merged_df <- left_join(filtered_entrytable, entryfld, by = "KEY") %>%
  clean_names() %>%
  select(-levelid, -prkey, -endtcreated, -endtmodif, -objactionid, -objlck, -objowner, -objshared) # remove BN admin columns from the data 


# Further processing, including merging S columns and adding time variables
SC2db  <- merged_df %>%
  mutate(
    mut_s_1 = na_if(mut_s_1, "NA"),
    mut_s_2 = na_if(mut_s_2, "NA"),
    mut_s_3 = na_if(mut_s_3, "NA"),
    mut_s_4 = na_if(mut_s_4, "NA")
  ) %>%
  unite("Spike_mut", mut_s_1, mut_s_2, mut_s_3, mut_s_4, sep = ";", na.rm = TRUE) %>%
  mutate(
    week = week(as.Date(prove_tatt)),
    year = year(as.Date(prove_tatt)),
    wy = yearweek(as.Date(prove_tatt)),
    my = yearmonth(as.Date(prove_tatt))
  ) %>%
  filter(prove_tatt != "")

# Preserve the pre-filter SC2 dataset for downstream QC/pass-fail analyses.
SC2db_prefilter <- SC2db


SC2db_v <- SC2db %>%
  filter(
    (nc_coverage == "NA" | nc_coverage >= 0.7) &     # Include "NA" or values >= 0.7
      Spike_mut !=""
  )


# Extract keys from SC2db_v
keys_in_SC2db <- SC2db_v$key

# Filter Totalvariants_v to exclude keys already in SC2db_v
Totalvariants_v_filtered <- Totalvariants_v %>%
  filter(!key %in% keys_in_SC2db)

# Combine the filtered Totalvariants_v with SC2db_v
SC2db_v <- bind_rows(SC2db_v, Totalvariants_v_filtered)

if (exists("close_sql_connections")) close_sql_connections()

rm(entrytable, entryfld, entryinf, merged_df, name_mapping, conBNCOVID19, conFLU2425, conSC22526, filtered_entrytable, duplicated_cols, entryfld_cols, entrytable_cols, SC2db, keys_in_SC2db)

