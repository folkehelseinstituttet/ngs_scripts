#BN COVID SQL query

sql_address_local <- Sys.getenv(
  "SC2_SQL_ADDRESS_FILE",
  unset = "N:/Virologi/Influensa/2526/WGS_Analyse/Scripts/SQL_address.R"
)
if (!file.exists(sql_address_local)) {
  stop("Local SQL address file not found. Set SC2_SQL_ADDRESS_FILE to your local SQL_address.R path.")
}
source(file = sql_address_local)

# Extract and process entry information fields
entryinf <- tbl(conBNCOVID19, "ENTRYINFOFIELDS") %>%
  select(FIELDID, DISPNAME, NAME) %>%
  collect()


# Extract and process entry fields
entryfld <- tbl(conBNCOVID19, 'ENTRYFLD') %>%
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
entrytable <- tbl(conBNCOVID19, "ENTRYTABLE") %>%
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
  clean_names()


# Further processing, including merging S columns and adding time variables
Totalvariants  <- merged_df %>%
  unite("Spike_mut", s, s2, s3, sep = ";", na.rm = TRUE) %>%
  mutate(
    week = week(as.Date(prove_tatt)),
    # Extract week from Prøve_tatt
    year = year(as.Date(prove_tatt)),
    # Extract year from Prøve_tatt
    wy = yearweek(as.Date(prove_tatt)),
    # Extract year-week from Prøve_tatt
    my = yearmonth(as.Date(prove_tatt))  # Extract year-month from Prøve_tatt
  ) %>%
  mutate(
    coverage_breadth_artic = na_if(coverage_breadth_artic, ""),
    coverage_breadth_swift = na_if(coverage_breadth_swift, ""),
    coverage_breadth_eksterne = na_if(coverage_breadth_eksterne, ""),
    coverage_breadth_nano = na_if(coverage_breadth_nano, ""),
    sekv_oppsett_run_artic = na_if(sekv_oppsett_run_artic, ""),
    sekv_oppsett_nano = na_if(sekv_oppsett_nano, ""),
    sekv_oppsett_sanger = na_if(sekv_oppsett_sanger, ""),
    sekv_oppsett_swift = na_if(sekv_oppsett_swift, "")
  ) %>%
  mutate(
    nc_coverage = coalesce(
      coverage_breadth_artic, 
      coverage_breadth_swift, 
      coverage_breadth_eksterne,
      coverage_breadth_nano
    ),
    ngs_run_id = coalesce(
      sekv_oppsett_run_artic, 
      sekv_oppsett_nano, 
      sekv_oppsett_sanger, 
      sekv_oppsett_swift
    )
  )%>%
  select(
    c(
      "prove_kategori" = "p",
      "pasient_utland" = "reise",
      "prove_tatt" = "prove_tatt",
      "pasient_sykdomsdebut_dato" = "dato_sykdomsdebut",
      "pasient_fylke_name" = "fylkenavn",
      "pasient_landsdel" = "landsdel",
      "prove_lw_id" = "lw_orig_prove",
      "prove_innsender_navn" = "sted",
      "pasient_fylke_nr" = "fylke",
      "pasient_kommentar" = "paskommnt",
      "pasient_aldersgruppe" = "alders_gruppe",
      "pasient_alder" = "alder",
      "pasient_kjnn" = "k",
      "prove_tatt_est" = "sampling_date_est",
      "pasient_status" = "st",
      "pasient_vaks" = "vaks",
      "pasient_antiviralbehandling" = "antiviral_behandling",
      "prove_material" = "materiale",
      "nc_pangolin_short" = "pangolin_nom",
      "nc_clade" = "new_next_strain_nom",
      "pasient_utbrudd" = "utbrudd",
      "pasient_vaks_2uipt" = "vaks2u_fpt",
      "mut_orf1b" = "orf1b",
      "mut_orf1a_3" = "orf3a",
      "mut_e" = "e",
      "mut_orf6" = "orf6",
      "mut_orf7a" = "orf7a",
      "mut_orf7b" = "orf7b",
      "mut_orf8" = "orf8",
      "mut_n" = "n",
      "mut_orf9b" = "orf9b",
      "ngs_instrument_id" = "gisaid_platform",
      "pasient_no" = "pasient_id",
      "nc_pangolin_long" = "full_pango_lineage",
      "key" = "key",
      "prove_kommentar" = "kommentar",
      "nc_coverage",
      "ngs_run_id", 
      "year", 
      "wy", 
      "my")
    )%>%
  filter(nc_coverage != "")  %>%
  filter(prove_tatt != "")

Totalvariants_v <- Totalvariants %>%
  filter(nc_coverage >= 70) %>%
  filter (nc_pangolin_short != "#BESTILT#") %>%
  filter (nc_pangolin_short != "Inkonklusiv") %>%
  filter (nc_pangolin_short != "inkonklusiv") %>%
  filter (nc_pangolin_short != "Se kommentar") %>%
  filter (nc_pangolin_short != "Seekom") %>%
  filter (nc_pangolin_short != "") %>%
  filter (nc_pangolin_short != "Failed") %>%
  filter (nc_pangolin_short != "failed") %>%
  filter (nc_pangolin_short != "Unassigned")

if (exists("close_sql_connections")) close_sql_connections()

rm(entrytable, entryfld, entryinf, merged_df, name_mapping, conBNCOVID19, conFLU2425, conSC22526, filtered_entrytable, duplicated_cols, entryfld_cols, entrytable_cols)

