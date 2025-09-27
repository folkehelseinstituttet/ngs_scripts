#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Usage: make_lw_import.R <Summary.csv> [output.tsv]", call. = FALSE)
}

input_file  <- args[1]
run         <- args[2]
output_file <- paste0(args[2], "_HCV_genotype_and_GLUE_summary.tsv")

# Read input
final <- read_csv(input_file, show_col_types = FALSE)

# Transform the imported summary data
lw_import <- final %>%
  # Change "." to ","
  mutate(
    fraction_mapped_reads_vs_median = str_replace(fraction_mapped_reads_vs_median, "\\.", ","),
    Percent_reads_mapped_of_trimmed_with_dups_major = str_replace(Percent_reads_mapped_of_trimmed_with_dups_major, "\\.", ","),
    Major_cov_breadth_min_1 = str_replace(Major_cov_breadth_min_1, "\\.", ","),
    Major_avg_depth = str_replace(Major_avg_depth, "\\.", ","),
    Major_cov_breadth_min_5 = str_replace(Major_cov_breadth_min_5, "\\.", ","),
    Major_cov_breadth_min_10 = str_replace(Major_cov_breadth_min_10, "\\.", ","),
    percent_mapped_reads_major_firstmapping = str_replace(percent_mapped_reads_major_firstmapping, "\\.", ","),
    percent_mapped_reads_minor_firstmapping = str_replace(percent_mapped_reads_minor_firstmapping, "\\.", ","),
    Minor_cov_breadth_min_5 = str_replace(Minor_cov_breadth_min_5, "\\.", ","),
    Minor_avg_depth = str_replace(Minor_avg_depth, "\\.", ","),
    Minor_cov_breadth_min_10 = str_replace(Minor_cov_breadth_min_10, ",", ",")
  ) %>%
  select(
    "Sample" = sampleName,
    "Total mapped reads all references, with duplicates" = total_mapped_reads,
    fraction_mapped_reads_vs_median,
    "Percent mapped reads of trimmed:" = Percent_reads_mapped_of_trimmed_with_dups_major,
    "Majority genotype:" = Major_genotype_mapping,
    "Number of mapped reads:" = Reads_withdup_mapped_major,
    "Percent covered:" = Major_cov_breadth_min_1,
    "Number of mapped reads without duplicates:" = Reads_nodup_mapped_major,
    "Percent most abundant majority genotype" = percent_mapped_reads_major_firstmapping,
    "Average depth without duplicates:" = Major_avg_depth,
    "Percent covered above depth=5 without duplicates:" = Major_cov_breadth_min_5,
    "Percent covered above depth=9 without duplicates:" = Major_cov_breadth_min_10,
    "Most abundant minority genotype:" = Minor_genotype_mapping,
    "Percent most abundant minority genotype:" = percent_mapped_reads_minor_firstmapping,
    "Number of mapped reads minor:" = Reads_withdup_mapped_minor,
    "Percent covered minor:" = Minor_cov_breadth_min_5,
    "Number of mapped reads minor without duplicates:" = Reads_nodup_mapped_minor,
    "Average depth minor without duplicates:" = Minor_avg_depth,
    "Percent covered above depth=5 minor without duplicates:" = Minor_cov_breadth_min_5,
    "Percent covered above depth=9 minor without duplicates:" = Minor_cov_breadth_min_10,
    "Script name and stringency:" = script_name_stringency,
    "Total number of reads before trim:" = total_raw_reads,
    "Total number of reads after trim:" = total_trimmed_reads,
    "Majority quality:" = major_typable,
    "Minor quality:" = minor_typable,
    sequencer_id,
    Reference,
    GLUE_genotype,
    GLUE_subtype,
    starts_with("glecaprevir"),
    starts_with("grazoprevir"),
    starts_with("paritaprevir"),
    starts_with("voxilaprevir"),
    starts_with("NS34A"),
    starts_with("daclatasvir"),
    starts_with("elbasvir"),
    starts_with("ledipasvir"),
    starts_with("ombitasvir"),
    starts_with("pibrentasvir"),
    starts_with("velpatasvir"),
    starts_with("NS5A"),
    starts_with("dasabuvir"),
    starts_with("sofosbuvir"),
    starts_with("NS5B"),
    `HCV project version`,
    `GLUE engine version`,
    starts_with("PHE")
  ) %>%
  # Convert "YES" to "Typbar" and "NO" to "Ikke typbar" in the "Majority quality:" and "Minor quality:" columns
  mutate(`Majority quality:` = case_when(
    `Majority quality:` == "YES" ~ "Typbar",
    `Majority quality:` == "NO" ~ "Ikke typbar",
    TRUE ~ `Majority quality:`)) %>%
  mutate(`Minor quality:` = case_when(
    `Minor quality:` == "YES" ~ "Typbar",
    `Minor quality:` == "NO" ~ "Ikke typbar",
    `Minor quality:` == "UNKNOWN" ~ "Ikke typbar",
    TRUE ~ `Minor quality:`)) %>%
  distinct()

# Write output
write_tsv(lw_import, file = output_file)
