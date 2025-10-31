# Capture command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Assign the arguments to variables
#SID <- args[1] #RunID from argument
min_date <- args[1]
min_date <- "2025-01-01"



source("N:/Virologi/Influensa/ARoh/Scripts/Color palettes.R ")
source("N:/Virologi/Influensa/RARI/2526/BN SC2 25-26.R")

library(lubridate)
library(tidyverse)
library(writexl)
library(stringr)
library(stringi)
library(tsibble)
library(officer)
library(magrittr)
library(dplyr)
library(tidyr)
library(tibble)
library(openxlsx)
library(readxl)
library(base64enc)
library(purrr)


# Define metadata
passage <- "Clinical Specimen"
host <- "Human"
Location <- "Norway"
sub_lab <- "Norwegian Institute of Public Health, Department of Virology"
address <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; , Knutsen MF"
GISAIDnr <- 3869  # Converting directly to numeric
Sequencing_Technology <- "Oxford Nanopore - GridION"
Assembly_Method <- "IRMA CoV-minion-long-reads"
Sequencing_Strategy <- "Targeted-amplification "

# Read Lab_ID data
Lab_ID <- read_excel("N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender Laboratory.xlsx")

source("N:/Virologi/Influensa/RARI/2526/BN SC2 25-26.R")

lab_lookup_table <- tribble(
  ~`Lab code`, ~`Lab`, ~`Lab_address`,
  "FHI-SMLV",	"Norwegian Institute of Public Health, Department of Virology",	"P.O.Box 222 Skoyen, 0213 Oslo, Norway",
  "Sykehuset ??stfold HF Kalnes",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MEDMIKR",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "MOLLEBYEN-LS",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MIKR",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "KALNES-MIKRGENINF",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "Sykehuset ??stfold HF",	"Ostfold Hospital Trust - Kalnes, Centre for Laboratory Medicine, Section for gene technology and infection serology", "P.O.Box 300, N-1714 Graalum, Norway",
  "AHUS-MIKR",	"Akershus University Hospital, Department for Microbiology and Infectious Disease Control",	"P.O.Box 1000, N-1478 Loerenskog, Norway",
  "ULLEV-MIKRVIR",	"Oslo University Hospital, Department of Microbiology",	"P.O.Box 4956 Nydalen, N-0424 Oslo, Norway",
  "BANKG??RDEN LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "BJ??LSEN LEGESENTER AS",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FAGERNES LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FORSAND LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "FURST-MIKRSER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GILDESK??L LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GJERDRUM LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GRATANGEN LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "GRINI M??LLE LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "HELSETORGET LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "H??VDINGG??RDEN LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "ILADALEN LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LEGENE I GR??NLANDSLEIRET",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LEGENE P?? BRYGGEN",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LILLESAND LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "OVERHALLA LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "PRESTFOSS LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "R??STAD LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SIO HELSE BLINDERN",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SJ??GATA MEDICAL",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "SOLVANG LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STABEKK LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STANGE LEGESENTER",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "STAVERN LEGEKONTOR",	"Furst Medical Laboratory",	"Soeren Bulls vei 25, N-1051 Oslo, Norway",
  "LILLEH-MIKR",	"Innlandet Hospital Trust, Division Lillehammer, Department for Medical Microbiology", "P.O.Box 990, N-2629 Lillehammer, Norway",
  "DRAM-MIKR",	"Medical Microbiology Unit, Department for Laboratory Medicine, Drammen Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  "TONSBERG-MIKR",	"Vestfold Hospital, Toensberg, Department of Microbiology",	"P.O.Box 2168, N-3103 Toensberg, Norway",
  "SKIEN-MIKR",	"Unilabs Laboratory Medicine", "Leirvollen 19, N-3736 Skien, Norway",
  "KRSAND-MIKR",	"Hospital of Southern Norway - Kristiansand, Department of Medical Microbiology",	"P.O.Box 416 Lundsiden, N-4604 Kristiansand, Norway",
  "STAVANG-MIKR",	"Dept. of Medical Microbiology, Stavanger University Hospital, Helse Stavanger HF", "P.O.Box 8100, N-4068 Stavanger, Norway",
  "HAUKE-MIKR",	"Haukeland University Hospital, Dept. of Microbiology",	"P.O.Box 1400, N-5021 Bergen, Norway",
  "HAUKE-MIKRVIR",	"Haukeland University Hospital, Dept. of Microbiology",	"P.O.Box 1400, N-5021 Bergen, Norway",
  "HAUGESU-MIKR",	"Haugesund Hospital, laboratory for Medical Microbiology", "P.O.Box 2170, N-5504 Haugesund, Norway",
  "FORDE-MIKR",	"Foerde Hospital, Department of Microbiology", "P.O.Box 1000, N-6807 Foerde, Norway",
  "MOLDE-MIKR",	"Department of Medical Microbiology - section Molde, Molde Hospital",	"Parkveien 84, N-6407 Molde, Norway",
  "STOLAV-MIKR",	"Department of Medical Microbiology, St. Olavs hospital",	"P.O.box 3250 Torgarden, N-7006 Trondheim, Norway",
  "LEVANG-MIKR",	"Levanger Hospital, laboratory for Medical Microbiology", "P.O.box 333, N-7601 Levanger, Norway",
  "BODO-MIKR",	"Nordland Hospital - Bodo, Laboratory Department, Molecular Biology Unit", "P.O.Box 1480, N-8092 Bodo, Norway",
  "TROMSO-MIKR",	"University Hospital of Northern Norway, Department for Microbiology and Infectious Disease Control",	"P.O.Box 56, N-9038 Tromsoe, Norway",
  "BODO-MIKR",	NA, NA,
  "AALESUND-MIKR",	"Department of medical microbiology, section Aalesund, Aalesund Hospital", "N-6026 Aalesund, Norway",
  "BYGDELEGENE-RAKKESTAD",	NA, NA,
  "ETNE LEGEKONTOR",	NA, NA,
  "BAERUM-MIKR", "Department of Medical Microbiology, Baerum Hospital, Vestre Viken Health Trust", "P.O.Box 800, N-3004 Drammen, Norway",
  "UNILABS-MIKR-SKIEN",	"Telemark Hospital Trust ??? Skien, Dept. of Medical Microbiology",	"P.O.Box 2900 Kj??rbekk, N-3710 Skien"
) %>%
  mutate(`Lab code` = as.character(`Lab code`))


# Proceed with data filtering and selection
sarsdb <- sarsdb %>%
  filter(prove_tatt > min_date) %>%                      # Ensure SID is defined and matches the column
  filter(nc_coverage >= 0.75) 

# Use join to add the labs and addresses
sarsdb <- sarsdb %>% 
  left_join(lab_lookup_table,
            by = c("prove_innsender_navn" = "Lab code")) 

# Now select the required columns
sarsdb <- sarsdb %>% select("key","prove_tatt","pasient_fylke_name","pasient_kjnn","prove_material", "pasient_alder", "prove_kategori","pasient_fylke_nr","prove_innsender_id",  
                            "ngs_depth", "ngs_primer_vers", "nc_pangolin_long")

# Data cleaning and manipulation
sarsdb <- sarsdb %>% 
  mutate(
    Host_Gender = if_else(toupper(pasient_kjnn) %in% c("M", "F"), toupper(pasient_kjnn), NA_character_),
    Year = lubridate::year(as.Date(prove_tatt)),
    Uniq4 = stringr::str_sub(key, -4, -1),                     # last 4 digits
    Isolate_Name = paste("hCoV-19", "Norway", Uniq4, Year, sep = "/"),
    Specimen_Source = dplyr::case_when(
      stringr::str_starts(prove_material, "NAPHSEKR") ~ "nasopharyngeal swab",
      TRUE ~ ""
    ),
    Primer_vers = dplyr::case_when(
      stringr::str_starts(ngs_primer_vers, "VM.3") ~ "Midnight version 3",
      TRUE ~ NA_character_
    )
  )


merged_df <- merge(sarsdb, Lab_ID, by.x = "prove_innsender_id", by.y = "Innsender nr", all.x = TRUE)

# Replace NA and non-numeric values in GISAID_Nr column
merged_df$GISAID_Nr <- ifelse(is.na(merged_df$GISAID_Nr) | is.na(merged_df$GISAID_Nr), GISAIDnr, merged_df$GISAID_Nr)

# ---- NEXTSTRAIN METADATA TSV EXPORT ----
library(dplyr)
library(stringr)

# safe getter
get_col_vec <- function(df, name, default = NA_character_) {
  if (name %in% names(df)) df[[name]] else rep(default, nrow(df))
}
`%||%` <- function(a,b) ifelse(is.na(a) | (is.character(a) & a==""), b, a)

# sex per Nextstrain
sex_vec <- dplyr::case_when(
  sarsdb$Host_Gender %in% c("M","m") ~ "male",
  sarsdb$Host_Gender %in% c("F","f") ~ "female",
  TRUE ~ ""
)

# location (municipality) if available
location_vec <- get_col_vec(sarsdb, "pasient_kommune_name", "")

# purpose of sequencing
pasient_status_vec <- get_col_vec(sarsdb, "pasient_status", NA_character_)
purpose_vec <- dplyr::case_when(
  sarsdb$prove_kategori == "P1_" ~ "Sentinel surveillance (ARI)",
  sarsdb$prove_kategori == "P2_" & pasient_status_vec == "Poliklinisk" ~ "Non-sentinel surveillance (outpatient)",
  pasient_status_vec == "Inneliggende" ~ "Non-sentinel surveillance (hospital)",
  TRUE ~ ""
)

# try to pick a gisaid accession column if present
epi_candidates <- c("EPI_ISL", "gisaid_epi_isl", "GISAID_EPI_ISL", "GISAID_accession", "GISAID_acc", "EPI_ISL_id", "GISAID_Nr")
epi_col <- epi_candidates[ epi_candidates %in% names(merged_df) ]
gisaid_epi_vec <- if (length(epi_col)) merged_df[[epi_col[1]]] else rep(NA_character_, nrow(merged_df))
gisaid_epi_vec <- ifelse(!is.na(gisaid_epi_vec) & grepl("^EPI[_-]?ISL[_-]?\\d+$", as.character(gisaid_epi_vec), ignore.case = TRUE),
                         as.character(gisaid_epi_vec), NA_character_)

# optional: compute sequence length from filtered_seq
length_df <- NULL
if (exists("filtered_seq") && all(c("key","sequence") %in% names(filtered_seq))) {
  length_df <- filtered_seq %>%
    mutate(length = nchar(gsub("\\s+", "", sequence))) %>%
    distinct(key, length)
}

ns_meta <- merged_df %>%
  mutate(
    strain  = sarsdb$Isolate_Name,                         # <??? key change
    virus   = "SARS-CoV-2",
    gisaid_epi_isl = gisaid_epi_vec,
    date    = format(as.Date(sarsdb$prove_tatt), "%Y-%m-%d"),
    region  = "Europe",
    country = "Norway",
    division = sarsdb$pasient_fylke_name %||% "",
    location = location_vec,
    region_exposure = "Europe",
    country_exposure = "Norway",
    division_exposure = sarsdb$pasient_fylke_name %||% "",
    segment = "genome",
    length = NA_integer_,
    host = "Human",
    age  = as.character(sarsdb$pasient_alder %||% NA_character_),
    sex  = sex_vec,
    pangolin_lineage = get_col_vec(sarsdb, "nc_pangolin_long", ""),
    GISAID_clade     = get_col_vec(sarsdb, "GISAID_clade", ""),
    originating_lab  = get_col_vec(sarsdb, "Lab", ""),
    submitting_lab   = "Norwegian Institute of Public Health, Department of Virology",
    authors          = authors,
    url = "", title = "", paper_url = "",
    date_submitted = "",
    purpose_of_sequencing = purpose_vec
  )

if (!is.null(length_df)) {
  ns_meta <- ns_meta %>% left_join(length_df, by = "key") %>%
    mutate(length = dplyr::coalesce(.data$length.y, .data$length.x)) %>%
    select(-dplyr::any_of(c("length.x","length.y")))
}

ns_cols <- c(
  "strain","virus","gisaid_epi_isl","date","region","country","division","location",
  "region_exposure","country_exposure","division_exposure","segment","length",
  "host","age","sex","pangolin_lineage","GISAID_clade","originating_lab",
  "submitting_lab","authors","url","title","paper_url","date_submitted","purpose_of_sequencing"
)
for (mc in setdiff(ns_cols, names(ns_meta))) ns_meta[[mc]] <- NA_character_
ns_meta <- ns_meta %>% select(dplyr::all_of(ns_cols))

# Define the output file path and filename
output_dir <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-Nextstrain"

ns_out_dir <- output_dir

ns_out_file <- file.path(ns_out_dir, paste0("nextstrain_metadata_", format(Sys.Date(), "%Y-%m-%d"), ".tsv"))
write.table(ns_meta, ns_out_file, sep = "\t", quote = TRUE, row.names = FALSE, na = "")



message("Nextstrain metadata written to: ", ns_out_file)


# Create the output filename for the FASTA file
output_filename_fasta <- paste0("nextstrain_fasta", format(Sys.Date(), "%U-%Y"), ".fasta")
output_path_fasta <- file.path(output_dir, output_filename_fasta)

# ---- FASTA HEADER FIX ----
stopifnot(all(c("key","sequence") %in% names(filtered_seq)))

# ensure key types match
filtered_seq <- filtered_seq %>% mutate(key = as.character(key))
name_map <- sarsdb %>% distinct(key, Isolate_Name)

fasta_df <- filtered_seq %>%
  left_join(name_map, by = "key")

# warn if any names missing
n_missing <- sum(is.na(fasta_df$Isolate_Name))
if (n_missing > 0) warning(n_missing, " sequences missing Isolate_Name; check keys vs sarsdb")

file_con <- file(output_path_fasta, open = "w")
for (i in seq_len(nrow(fasta_df))) {
  header <- fasta_df$Isolate_Name[i]
  if (is.na(header) || header == "") header <- fasta_df$key[i]  # last-resort fallback
  seqi <- fasta_df$sequence[i]
  cat(">", header, "\n", seqi, "\n", file = file_con, sep = "")
}
close(file_con)

# ---- END FASTA HEADER FIX ----
