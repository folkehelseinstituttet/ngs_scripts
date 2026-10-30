# CSV-based influenza GISAID submission.
# Usage: Rscript influenza_gisaid_csv.R RUNID [master.csv]
# FASTA files must be in the same directory as master.csv. Headers must have
# NGS_LW_ID and segment, e.g. >2820073-INFA|01-HA-H1N1.
# The output uses master Key in the submission headers.
# Capture command-line arguments
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Missing required argument: SID (RunID).")
}

# Assign the arguments to variables
SID <- args[1]  # RunID from argument

master_path <- if (length(args) >= 2) args[2] else
  "N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv"
if (!file.exists(master_path)) stop("Master CSV not found: ", master_path)

library(lubridate)
library(tidyverse)
library(stringr)
library(magrittr)
library(dplyr)
library(tidyr)
library(tibble)
library(purrr)

# Repair common UTF-8/latin1 mojibake from upstream DB (e.g. "MÃ¸re" -> "Møre")
fix_mojibake_utf8 <- function(x) {
  x <- as.character(x)
  needs_fix <- !is.na(x) & grepl("Ã|Â|â", x, useBytes = TRUE)
  out <- x
  
  out[needs_fix] <- vapply(x[needs_fix], function(s) {
    codepoints <- utf8ToInt(s)
    if (length(codepoints) == 0L || any(codepoints > 255L)) return(s)
    
    repaired <- tryCatch(rawToChar(as.raw(codepoints)), error = function(e) s)
    validated <- iconv(repaired, from = "UTF-8", to = "UTF-8", sub = "")
    
    if (is.na(validated)) s else validated
  }, FUN.VALUE = character(1))
  
  out
}

# Define metadata
passage <- "Clinical Specimen"
host <- "Human"
Location <- "Norway"
sub_lab <- "Norwegian Institute of Public Health, Department of Virology"
address <- "P.O.Box 222 Skoyen, 0213 Oslo, Norway"
authors <- "Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Dieseth MS"
GISAIDnr <- 3869
Sequencing_Technology <- "Oxford Nanopore"
Assembly_Method <- "IRMA FLU-minion"
Sequencing_Strategy <- "Targeted-amplification "

# Read originating-lab IDs from the semicolon-delimited submitter lookup
Lab_ID <- readr::read_delim(
  "N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender_GISAID.csv",
  delim = ";",
  col_types = readr::cols(.default = readr::col_character()),
  trim_ws = TRUE
) %>%
  select(Innsender_nr, GISAID_Id)

# Preserve identifiers and literal NA text as strings, including leading zeroes.
fludb <- readr::read_delim(master_path, delim = ";",
  col_types = readr::cols(.default = readr::col_character()),
  na = character(), trim_ws = FALSE, name_repair = "minimal", show_col_types = FALSE)
if (nrow(readr::problems(fludb))) stop("Could not parse master CSV.")
required <- c("Key", "NGS_Run_ID", "NGS_Sekvens_Resultat", "GISAID_Kommentar",
  "Pasient_Fylke_Nr", "Pasient_Alder", "Prove_Tatt", "Pasient_Kjnn",
  "Prove_Innsender_ID", "Pasient_Fylke_Name", "Pasient_Status", "Prove_Kategori",
  "Prove_Material", "NGS_LW_ID", paste0("NGS_Reads_", c("HA", "NA", "M", "NS", "NP", "PA", "PB1", "PB2")),
  "NGS_QC_Sum")
if (anyDuplicated(names(fludb))) stop("Master CSV has duplicate column names.")
missing <- setdiff(required, names(fludb))
if (length(missing)) stop("Missing master CSV columns: ", paste(missing, collapse = ", "))
fludb <- fludb[, required]
names(fludb) <- tolower(names(fludb))
master_id_map <- fludb[, c("key", "ngs_lw_id")]

# Proceed with data filtering and selection
fludb <- fludb %>%
  filter(ngs_run_id == SID) %>%
  filter(!is.na(ngs_sekvens_resultat), ngs_sekvens_resultat != "") %>%
  filter(!(ngs_sekvens_resultat %in% c("NA", "N2", "N1"))) %>%
  filter(is.na(gisaid_kommentar) | gisaid_kommentar == "")

# Now select the required columns
fludb <- fludb %>%
  select(
    key,
    ngs_lw_id,
    ngs_sekvens_resultat,
    pasient_fylke_nr,
    pasient_alder,
    prove_tatt,
    pasient_kjnn,
    prove_innsender_id,
    pasient_fylke_name,
    pasient_status,
    prove_kategori,
    prove_material,
    ngs_reads_ha,
    ngs_reads_na,
    ngs_reads_m,
    ngs_reads_ns,
    ngs_reads_np,
    ngs_reads_pa,
    ngs_reads_pb1,
    ngs_reads_pb2,
    ngs_qc_sum
  )

if (!nrow(fludb)) stop("No eligible samples found for run: ", SID)
if (any(!nzchar(trimws(fludb$key))) || anyDuplicated(fludb$key)) {
  stop("Eligible samples must have unique, nonempty Key values.")
}
fludb$ngs_lw_id <- trimws(fludb$ngs_lw_id)
all_lw_ids <- trimws(master_id_map$ngs_lw_id)
if (anyDuplicated(all_lw_ids[nzchar(all_lw_ids) & all_lw_ids %in% fludb$ngs_lw_id])) {
  stop("An eligible NGS_LW_ID is associated with multiple master rows.")
}
if (any(!nzchar(fludb$ngs_lw_id)) || anyDuplicated(fludb$ngs_lw_id)) {
  stop("Eligible samples must have unique, nonempty NGS_LW_ID values.")
}
fludb$prove_tatt <- as.Date(fludb$prove_tatt)

# Read segment FASTAs alongside master.csv. Match the first header field to
# NGS_LW_ID and translate it to Key for the GISAID submission.
fasta_files <- list.files(dirname(master_path), pattern = "\\.(fasta|fa|fna|fas)$",
                          full.names = TRUE, ignore.case = TRUE)
if (!length(fasta_files)) stop("No FASTA files found next to master CSV: ", dirname(master_path))
read_fasta <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  headers <- which(startsWith(lines, ">"))
  if (!length(headers)) stop("No FASTA headers in: ", path)
  if (headers[1] != 1L && any(nzchar(trimws(lines[seq_len(headers[1] - 1L)])))) {
    stop("Sequence data before first FASTA header in: ", path)
  }
  ends <- c(headers[-1] - 1L, length(lines))
  lapply(seq_along(headers), function(i) {
    fields <- trimws(strsplit(substring(lines[headers[i]], 2), "|", fixed = TRUE)[[1]])
    sample_row <- match(fields[1], fludb$ngs_lw_id)
    if (is.na(sample_row)) return(NULL)
    if (length(fields) < 2L) stop("Missing segment in FASTA header: ", lines[headers[i]])
    segment_field <- toupper(sub("^[0-9]+-", "", fields[2]))
    hit_segment <- sub("-.*$", "", segment_field)
    if (hit_segment == "M") hit_segment <- "MP"
    if (!hit_segment %in% c("HA", "NA", "PB1", "PB2", "PA", "MP", "NS", "NP")) {
      stop("Unrecognized segment in FASTA header: ", lines[headers[i]])
    }
    sequence <- if (ends[i] > headers[i]) paste(lines[(headers[i] + 1L):ends[i]], collapse = "") else ""
    sequence <- gsub("\\s+", "", sequence)
    if (!nzchar(sequence)) stop("Empty sequence in FASTA header: ", lines[headers[i]])
    data.frame(key = fludb$key[sample_row], experiment = hit_segment, sequence = sequence, stringsAsFactors = FALSE)
  })
}
records <- unlist(lapply(fasta_files, read_fasta), recursive = FALSE)
records <- Filter(Negate(is.null), records)
if (!length(records)) stop("No FASTA headers matched eligible master NGS_LW_ID values. Check the header format.")
filtered_seq <- do.call(rbind, records)
if (anyDuplicated(paste(filtered_seq$key, filtered_seq$experiment, sep = "|"))) {
  stop("Multiple FASTA records match the same sample and segment. Resolve duplicates before submission.")
}
missing_sequences <- setdiff(fludb$key, filtered_seq$key)
if (length(missing_sequences)) stop("No FASTA records found for samples: ", paste(missing_sequences, collapse = ", "))

# Normalize county names before they are used in output fields
fludb$pasient_fylke_name <- fix_mojibake_utf8(fludb$pasient_fylke_name)

# Data cleaning and manipulation
fludb <- fludb %>% 
  mutate(
    Original_Key = as.character(key),
    
    Subtype = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "H1N1",
      str_starts(ngs_sekvens_resultat, "A/H3N2") ~ "H3N2",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "B",
      TRUE ~ ""
    ),
    
    INFType = case_when(
      str_starts(ngs_sekvens_resultat, "A/") ~ "A",
      str_starts(ngs_sekvens_resultat, "B/") ~ "B",
      TRUE ~ ""
    ),
    
    Lineage = case_when(
      str_starts(ngs_sekvens_resultat, "A/H1N1") ~ "pdm09",
      str_starts(ngs_sekvens_resultat, "B/Victoria") ~ "Victoria",
      TRUE ~ ""
    ),
    
    Host_Gender = if_else(
      toupper(pasient_kjnn) %in% c("M", "F"),
      toupper(pasient_kjnn),
      NA_character_
    ),
    
    Year = year(as.Date(prove_tatt)),
    age = pasient_alder,
    
    # Key format is always XXXX + number, so remove first 4 chars
    Uniq_nr = sub("^.{4}", "", Original_Key),
    
    Isolate_Name = paste(INFType, "Norway", Uniq_nr, Year, sep = "/"),
    
    Specimen_Source = case_when(
      str_starts(prove_material, "SEKRET") ~ "",
      str_starts(prove_material, "NAPHSEKR") ~ "nasopharyngeal swab",
      TRUE ~ ""
    ),
    
    Coverage = rowMeans(
      across(contains("reads"), ~ replace_na(suppressWarnings(as.numeric(.x)), 0)),
      na.rm = TRUE
    )
  )

# Merging with Lab_ID
merged_df <- merge(
  fludb,
  Lab_ID,
  by.x = "prove_innsender_id",
  by.y = "Innsender_nr",
  all.x = TRUE
)

# Replace NA / blank values in GISAID_Id column
merged_df$GISAID_Id <- ifelse(
  is.na(merged_df$GISAID_Id) | merged_df$GISAID_Id == "",
  as.character(GISAIDnr),
  merged_df$GISAID_Id
)

################### FASTA FILE :
tmp <- merged_df %>%
  add_column(
    "Isolate_Id" = "",
    "Segment_Ids" = "",
    "Passage_History" = passage,
    "Host" = host,
    "Authors" = authors,
    "Location" = "Norway",
    "province" = merged_df$pasient_fylke_name,
    "sub_province" = "",
    "Location_Additional_info" = "",
    "Host_Additional_info" = "",
    
    "Seq_Id (HA)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "HA"],
      paste("HA", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (NA)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NA"],
      paste("NA", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (PB1)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB1"],
      paste("PB1", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (PB2)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PB2"],
      paste("PB2", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (PA)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "PA"],
      paste("PA", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (MP)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "MP"],
      paste("MP", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (NS)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NS"],
      paste("NS", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (NP)" = ifelse(
      merged_df$key %in% filtered_seq$key[filtered_seq$experiment == "NP"],
      paste("NP", merged_df$key, sep = "|"),
      ""
    ),
    "Seq_Id (HE)" = "",
    "Seq_Id (P3)" = "",
    "Submitting_Sample_Id" = merged_df$key,
    "Originating_Lab_Id" = merged_df$GISAID_Id,
    "Originating_Sample_Id" = "",
    "Collection_Month" = month(merged_df$prove_tatt),
    "Collection_Year" = year(merged_df$prove_tatt),
    "Collection_Date" = format(as.Date(merged_df$prove_tatt), "%Y-%m-%d"),
    "Antigen_Character" = "",
    "Adamantanes_Resistance_geno" = "",
    "Oseltamivir_Resistance_geno" = "",
    "Zanamivir_Resistance_geno" = "",
    "Peramivir_Resistance_geno" = "",
    "Other_Resistance_geno" = "",
    "Adamantanes_Resistance_pheno" = "",
    "Oseltamivir_Resistance_pheno" = "",
    "Zanamivir_Resistance_pheno" = "",
    "Peramivir_Resistance_pheno" = "",
    "Other_Resistance_pheno" = "",
    "Host_Age" = merged_df$pasient_alder,
    "Host_Age_Unit" = "Y",
    "Health_Status" = "",
    "Note" = "",
    "provider_sample_id" = "",
    "Sampling_Strategy" = ifelse(
      merged_df$prove_kategori == "P1_",
      "Sentinel surveillance (ARI)",
      ifelse(
        merged_df$pasient_status == "Inneliggende",
        "Non-sentinel surveillance (hospital)",
        ifelse(
          merged_df$prove_kategori == "P2_" & merged_df$pasient_status == "Poliklinisk",
          "Non-sentinel surveillance (outpatient)",
          ""
        )
      )
    ),
    "Sequencing_Technology" = Sequencing_Technology,
    "Assembly_Method" = Assembly_Method,
    "Sequencing_Strategy" = Sequencing_Strategy
  )

# Define the desired column order
desired_order <- c(
  "Isolate_Id",
  "Segment_Ids",
  "Isolate_Name",
  "Subtype",
  "Lineage",
  "Passage_History",
  "Location",
  "province",
  "sub_province",
  "Location_Additional_info",
  "Host",
  "Host_Additional_info",
  "Specimen_Source",
  "Sampling_Strategy",
  "Sequencing_Strategy",
  "Sequencing_Technology",
  "Assembly_Method",
  "Coverage",
  "Seq_Id (HA)",
  "Seq_Id (NA)",
  "Seq_Id (PB1)",
  "Seq_Id (PB2)",
  "Seq_Id (PA)",
  "Seq_Id (MP)",
  "Seq_Id (NS)",
  "Seq_Id (NP)",
  "Seq_Id (HE)",
  "Seq_Id (P3)",
  "Submitting_Sample_Id",
  "Authors",
  "Originating_Lab_Id",
  "Originating_Sample_Id",
  "Collection_Month",
  "Collection_Year",
  "Collection_Date",
  "Antigen_Character",
  "Adamantanes_Resistance_geno",
  "Oseltamivir_Resistance_geno",
  "Zanamivir_Resistance_geno",
  "Peramivir_Resistance_geno",
  "Other_Resistance_geno",
  "Adamantanes_Resistance_pheno",
  "Oseltamivir_Resistance_pheno",
  "Zanamivir_Resistance_pheno",
  "Peramivir_Resistance_pheno",
  "Other_Resistance_pheno",
  "Host_Age",
  "Host_Age_Unit",
  "Host_Gender",
  "Health_Status",
  "Note",
  "provider_sample_id"
)

submission <- tmp %>%
  select(all_of(desired_order))

# Define the output file path and filename
output_dir <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/10-GISAID"
output_filename_excel <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".xlsx")
output_path_excel <- file.path(output_dir, output_filename_excel)

# Write the submission dataframe to an Excel file
# write.xlsx(submission, output_path_excel, rownames = FALSE)

# Set the output file path and filename for CSV
output_dir_csv <- "N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/10-GISAID"
output_filename_csv <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".csv")
output_path_csv <- file.path(output_dir_csv, output_filename_csv)

# Create the output filename for the FASTA file
output_filename_fasta <- paste0("GISAID SUBMISSION - ", format(Sys.Date(), "%U-%Y"), ".fasta")
output_path_fasta <- file.path(output_dir_csv, output_filename_fasta)

# Try to locate a source for `ngs_qc_sum` keyed by sample `key`
qc_source <- NULL
if (exists("merged_df") && "ngs_qc_sum" %in% names(merged_df)) {
  qc_source <- merged_df %>% select(key, ngs_qc_sum)
} else if (exists("fludb") && "ngs_qc_sum" %in% names(fludb)) {
  qc_source <- fludb %>% select(key, ngs_qc_sum)
} else if ("ngs_qc_sum" %in% names(tmp)) {
  qc_source <- tmp %>%
    transmute(key = Submitting_Sample_Id, ngs_qc_sum = ngs_qc_sum)
}

if (!is.null(qc_source)) {
  qc_long <- qc_source %>%
    filter(!is.na(ngs_qc_sum), ngs_qc_sum != "") %>%
    mutate(Submitting_Sample_Id = key) %>%
    separate_rows(ngs_qc_sum, sep = "\\|") %>%
    separate(
      ngs_qc_sum,
      into = c("gene", "issue"),
      sep = ":",
      fill = "right",
      extra = "merge"
    ) %>%
    filter(issue %in% c("FS", "MS")) %>%
    mutate(
      target_col = dplyr::recode(
        gene,
        "HA"  = "Seq_Id (HA)",
        "NA"  = "Seq_Id (NA)",
        "PB1" = "Seq_Id (PB1)",
        "PB2" = "Seq_Id (PB2)",
        "PA"  = "Seq_Id (PA)",
        "M"   = "Seq_Id (MP)",
        "MP"  = "Seq_Id (MP)",
        "NS"  = "Seq_Id (NS)",
        "NP"  = "Seq_Id (NP)",
        .default = NA_character_
      )
    ) %>%
    filter(!is.na(target_col)) %>%
    distinct(Submitting_Sample_Id, target_col)
  
  if (nrow(qc_long) > 0) {
    for (i in seq_len(nrow(qc_long))) {
      sid <- qc_long$Submitting_Sample_Id[i]
      col <- qc_long$target_col[i]
      if (col %in% names(submission)) {
        submission[submission$Submitting_Sample_Id == sid, col] <- ""
      }
    }
  }
  
} else {
  warning("ngs_qc_sum not found in current environment; skipped QC-based Seq_Id clearing.")
}

# Keep the FASTA and its metadata segment IDs in agreement after QC filtering.
segment_columns <- setNames(paste0("Seq_Id (", c("HA", "NA", "PB1", "PB2", "PA", "MP", "NS", "NP"), ")"),
                            c("HA", "NA", "PB1", "PB2", "PA", "MP", "NS", "NP"))
keep <- vapply(seq_len(nrow(filtered_seq)), function(i) {
  row <- match(filtered_seq$key[i], submission$Submitting_Sample_Id)
  col <- segment_columns[[filtered_seq$experiment[i]]]
  !is.na(row) && nzchar(submission[[col]][row])
}, logical(1))
filtered_seq <- filtered_seq[keep, , drop = FALSE]
if (!nrow(filtered_seq)) stop("All matching FASTA segments were excluded by QC.")
if (any(!submission$Submitting_Sample_Id %in% filtered_seq$key)) {
  stop("At least one sample has no FASTA segment remaining after QC.")
}
write.csv(submission, output_path_csv, row.names = FALSE, fileEncoding = "UTF-8")
fasta_lines <- unlist(lapply(seq_len(nrow(filtered_seq)), function(i) {
  c(paste0(">", filtered_seq$experiment[i], "|", filtered_seq$key[i]), filtered_seq$sequence[i])
}), use.names = FALSE)
writeLines(fasta_lines, output_path_fasta, useBytes = TRUE)
message("Wrote ", output_path_csv, " and ", output_path_fasta)
