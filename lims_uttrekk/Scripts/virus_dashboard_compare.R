# Sammenligner to kjøringer av virus_dashboard.R (før og etter en endring).
# Gir aggregerte tellinger per faggruppe, til "Målt effekt" i
# ../virus_dashboard/CHANGELOG.md. Skriver aldri ut prøvenummer eller resultater.
#
# Bruk:
#   Rscript virus_dashboard_compare.R <før-mappe> <etter-mappe> [utfil.tsv]
#
# Hver mappe må inneholde VIRUS_POWERBI_lw_uttrekk.tsv (F1) og
# VIRUS_POWERBI_results.tsv (F2). VIRUS_POWERBI_unclassified_codes.tsv (F3)
# tas med hvis den finnes.
#
# Kjør begge versjonene rett etter hverandre mot samme database, ellers
# blandes effekten av endringen med nye prøver. Målet "Prøver bare i før/etter"
# viser om det har skjedd.

suppressPackageStartupMessages(library(tidyverse))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Bruk: Rscript virus_dashboard_compare.R <før-mappe> <etter-mappe> [utfil.tsv]")
}
dir_before <- args[1]
dir_after  <- args[2]
outfile    <- if (length(args) >= 3) args[3] else NA

f1_name <- "VIRUS_POWERBI_lw_uttrekk.tsv"
f2_name <- "VIRUS_POWERBI_results.tsv"
f3_name <- "VIRUS_POWERBI_unclassified_codes.tsv"

for (d in c(dir_before, dir_after)) {
  for (f in c(f1_name, f2_name)) {
    if (!file.exists(file.path(d, f))) stop("Finner ikke ", file.path(d, f))
  }
}

## ==================================================
## Lese filene
## ==================================================

# Tekst fra LIMS kan være Windows-1252. latin1 gir alltid gyldige strenger,
# og kolonnene som brukes her er ASCII, så de blir like uansett.
read_lw <- function(path, ...) {
  read_tsv(path, col_types = cols(.default = col_character()),
           locale = locale(encoding = "latin1"), progress = FALSE, ...)
}

read_f1 <- function(dir) {
  read_lw(file.path(dir, f1_name),
          col_select = c(any_of(c("SAMPLE_NUMBER", "GROUP_NAME", "TEMPLATE",
                                  "SAMPLE.STATUS", "child_sample")),
                         matches("^(Auth|NotAuth)_")))
}

read_f2 <- function(dir) {
  read_lw(file.path(dir, f2_name),
          col_select = any_of(c("SAMPLE_NUMBER", "analysis_category", "value")))
}

# Default-filtrene i dashboardet (RG02, RG03, RG04)
dashboard_filter <- function(f1) {
  f1 %>%
    filter(child_sample == "NO",
           is.na(`SAMPLE.STATUS`) | !`SAMPLE.STATUS` %in% c("X", "R"),
           is.na(TEMPLATE) | TEMPLATE != "STORAGE")
}

# "Ikke utført" (RG07). Etter latin1-lesing er "ø" ett eller to tegn.
is_iu <- function(x) grepl("^\\s*(IU|ikke ?utf.{1,2}rt)\\s*$", x, ignore.case = TRUE)

## ==================================================
## Tellinger for én kjøring
## ==================================================

# Legger til en TOTALT-rad per mål
with_total <- function(df) {
  bind_rows(df,
            df %>% group_by(omfang, maal) %>%
              summarise(n = sum(n), .groups = "drop") %>%
              mutate(faggruppe = "TOTALT"))
}

count_run <- function(dir) {
  f1 <- read_f1(dir)
  f2 <- read_f2(dir) %>%
    left_join(distinct(f1, SAMPLE_NUMBER, GROUP_NAME), by = "SAMPLE_NUMBER")
  bucket_cols <- grep("^(Auth|NotAuth)_", names(f1), value = TRUE)

  scopes <- list(alle = f1, dashboard = dashboard_filter(f1))

  counts <- imap_dfr(scopes, function(d, scope) {
    samples <- d %>%
      count(faggruppe = GROUP_NAME, name = "n") %>%
      mutate(maal = "F1 prøver")

    buckets <- d %>%
      select(GROUP_NAME, all_of(bucket_cols)) %>%
      pivot_longer(-GROUP_NAME, names_to = "bucket", values_to = "v") %>%
      filter(!is.na(v), v != "") %>%
      count(faggruppe = GROUP_NAME, bucket, name = "n") %>%
      mutate(maal = paste("F1", bucket)) %>%
      select(-bucket)

    f2_scope <- semi_join(f2, d, by = "SAMPLE_NUMBER")

    results <- f2_scope %>%
      mutate(analysis_category = replace_na(analysis_category, "(ingen)")) %>%
      count(faggruppe = GROUP_NAME, analysis_category, name = "n") %>%
      mutate(maal = paste("F2 rader", analysis_category)) %>%
      select(-analysis_category)

    iu <- f2_scope %>%
      filter(is_iu(value)) %>%
      count(faggruppe = GROUP_NAME, name = "n") %>%
      mutate(maal = "F2 IU-verdier")

    bind_rows(samples, buckets, results, iu) %>% mutate(omfang = scope)
  })

  f3_path <- file.path(dir, f3_name)
  if (file.exists(f3_path)) {
    f3 <- read_lw(f3_path, col_select = any_of("GROUP_NAME"))
    counts <- bind_rows(counts,
                        f3 %>% count(faggruppe = GROUP_NAME, name = "n") %>%
                          mutate(maal = "F3 koder", omfang = "alle"))
  }

  list(counts = with_total(counts), samples = distinct(f1, SAMPLE_NUMBER, GROUP_NAME))
}

## ==================================================
## Sammenligne
## ==================================================

before <- count_run(dir_before)
after  <- count_run(dir_after)

# Prøver som bare finnes i én av kjøringene (bør være 0 hvis kjøringene er
# gjort mot samme database)
only_in <- function(a, b, label) {
  anti_join(a, b, by = "SAMPLE_NUMBER") %>%
    count(faggruppe = GROUP_NAME, name = "n") %>%
    mutate(maal = label, omfang = "alle")
}
drift <- bind_rows(
  only_in(before$samples, after$samples, "Prøver bare i før"),
  only_in(after$samples, before$samples, "Prøver bare i etter")
) %>% with_total() %>% mutate(foer = 0L, etter = n) %>% select(-n)

comparison <- full_join(
  rename(before$counts, foer = n),
  rename(after$counts, etter = n),
  by = c("omfang", "faggruppe", "maal")
) %>%
  bind_rows(drift) %>%
  mutate(foer   = replace_na(foer, 0L),
         etter  = replace_na(etter, 0L),
         endring = etter - foer,
         endring_pst = if_else(foer > 0, round(100 * endring / foer, 1), NA_real_)) %>%
  arrange(omfang, faggruppe == "TOTALT", faggruppe, maal) %>%
  select(omfang, faggruppe, maal, foer, etter, endring, endring_pst)

## ==================================================
## Skrive ut
## ==================================================

if (!is.na(outfile)) {
  write_tsv(comparison, outfile)
  message("Skrev ", nrow(comparison), " rader til ", outfile)
}

drift_n <- sum(drift$etter[drift$faggruppe != "TOTALT"])
if (drift_n > 0) {
  message("ADVARSEL: ", drift_n, " prøver finnes bare i én av kjøringene. ",
          "Endringene under blander effekten av koden med nye/endrede data.")
}

# Markdown-tabell med bare målene som endret seg, klar til CHANGELOG.md
changed <- filter(comparison, endring != 0)
if (nrow(changed) == 0) {
  cat("Ingen endringer i tellingene.\n")
} else {
  fmt_pct <- function(x) ifelse(is.na(x), "ny", sprintf("%+.1f %%", x))
  cat("| Omfang | Faggruppe | Mål | Før | Etter | Endring |\n")
  cat("|---|---|---|---:|---:|---:|\n")
  cat(sprintf("| %s | %s | %s | %d | %d | %+d (%s) |\n",
              changed$omfang, changed$faggruppe, changed$maal,
              changed$foer, changed$etter, changed$endring,
              fmt_pct(changed$endring_pst)), sep = "")
}
