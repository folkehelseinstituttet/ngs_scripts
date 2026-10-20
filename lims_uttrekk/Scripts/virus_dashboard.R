# Virus Dashboard: uttrekk fra LIMS til Power BI.
# Stegkodene [S##] er beskrevet i ../virus_dashboard/STEPS.md

library(odbc)
library(tidyverse)
library(lubridate)

# Version 2.1-dev
# Versjon 1 inneholdt kun info om prøvedato og sekvensering.
# Versjon 2 legger på mer info om analyser og resultater. 
# Versjon 2.1: ny kategori SEQ_TYPING (Sanger/genotyping/resistens), flere analysekoder,
#   og Fil 3 med uklassifiserte koder (#23, #37).
# Versjon 2.2 (under arbeid): liste over analysekoder som bevisst ikke telles, og Fil 5 (#40),
#   og Fil 4 med kobling mellom prøver og analysekoder (#42).
#   Fil 6 med resultatfelt som ikke er i whitelisten, og flere resultater i Fil 2 (#56, #46).

## ==================================================
## [S01] Validate required environment variables
## ==================================================

required_vars <- c(
  "OUTDIR",
  "SQL_DRIVER",
  "SQL_SERVER",
  "SQL_DATABASE",
  "RUN_ENV"
)

missing <- required_vars[Sys.getenv(required_vars) == ""]
if (length(missing) > 0) {
  stop(
    "Missing required environment variables: ",
    paste(missing, collapse = ", ")
  )
}

## ==================================================
## [S02] Resolve variables
## ==================================================

run_env   <- Sys.getenv("RUN_ENV")   # Test or Prod
outdir    <- Sys.getenv("OUTDIR")
sqldriver <- Sys.getenv("SQL_DRIVER")
sqlserver <- Sys.getenv("SQL_SERVER")
database  <- Sys.getenv("SQL_DATABASE")

## ==================================================
## [S02] Validate output directory
## ==================================================

if (!dir.exists(outdir)) {
  stop(
    "OUTDIR does not exist: ", outdir,
    "\nEnvironment: ", run_env
  )
}

# Name output files
# Alle utfilene skrives til <OUTDIR>/<RUN_ENV>/ToOrdinary/LW_Datauttrekk/.
# Kodene F1-F5 er de samme som i dokumentasjonen (../virus_dashboard/STEPS.md).
outpath <- file.path(outdir, run_env, "ToOrdinary", "LW_Datauttrekk")

# F1: én rad per prøve, med prøveinfo og Auth_*/NotAuth_*-kolonner per analysekategori.
#     Hovedtabellen i dashboardet. Skrives i [S08]
outfile_F1 <- file.path(outpath, "VIRUS_POWERBI_lw_uttrekk.tsv")
# F2: én rad per resultatverdi, bare for whitelistede (ANALYSIS, NAME)-par.
#     Til resultater i dashboardet (Ct-verdier, konklusjoner, genotyper). Skrives i [S11]
outfile_F2 <- file.path(outpath, "VIRUS_POWERBI_results.tsv")
# F3: analysekoder på virusprøver som ikke står i noen kategoriliste, per faggruppe, med antall.
#     Vedlikeholdsfil for kodelistene, ikke til dashboardet. Skrives i [S14]
outfile_F3 <- file.path(outpath, "VIRUS_POWERBI_unclassified_codes.tsv")
# F4: én rad per prøve og analysekode, for prøver mottatt de siste fem årene.
#     Kobling mellom prøver og analysekoder i dashboardet. Skrives i [S16]
outfile_F4 <- file.path(outpath, "VIRUS_POWERBI_sample_codes.tsv")
# F5: analysekoder som bevisst ikke telles, med begrunnelse.
#     Referanseliste, ikke koblet til prøver. Skrives i [S15]
outfile_F5 <- file.path(outpath, "VIRUS_POWERBI_excluded_codes.tsv")
# F6: resultatfelt på virusprøver som ikke er i whitelisten og ikke bevisst utelatt, med antall.
#     Vedlikeholdsfil for whitelisten, ikke til dashboardet. Skrives i [S18]
outfile_F6 <- file.path(outpath, "VIRUS_POWERBI_unlisted_result_fields.tsv")

# Ikke en datafil: skrives bare hvis tilkoblingen til LIMS feiler [S03], og slettes
# når tilkoblingen virker. Utfilene fra forrige kjøring blir da stående (#28)
errorfile <- file.path(outpath, "VIRUS_POWERBI_error.txt")

## ==================================================
## [S03] Establish connection to LIMS
## ==================================================

con <- tryCatch(
  {
    odbc::dbConnect(odbc::odbc(),
                    Driver = sqldriver,
                    Server = sqlserver,
                    Database = database
    )
  },
  error = function(e) {
    # Skriv feilen til en egen fil, ikke til F1, så Power BI ikke laster en feilmelding som data (#28)
    cat(
      "ERROR: Unable to connect to database.\n",
      "Time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n",
      "Environment: ", run_env, "\n",
      "Message: ", e$message, "\n",
      file = errorfile
    )
    stop("Connection failed")
  }
)

# Tilkoblingen virker: fjern en gammel feilfil, så den ikke blir stående
if (file.exists(errorfile)) file.remove(errorfile)

## ==================================================
## Extract data from LIMS
## ==================================================

# [S04] Lage liste med relevante faggrupper til filtrering
faggrupper <- c("HEP_HIV", "HPV", "INFLUENSA", "MMR", "POL_ENT", "ROTA", "VIRUS_CMN")

# Hente ut metadata om alle prøver fra SAMPLE-tabellen
samples <- tbl(con, "SAMPLE_VIEW") %>% 
  # Velge ut relevant kolonner først. Dette for å forenkle hva som skal hentes ut av driveren
  select(ORIGINAL_SAMPLE, PARENT_SAMPLE, TEMPLATE, SAMPLE_NUMBER, TEXT_ID, GROUP_NAME, SAMPLED_DATE, RECD_DATE, X_MEDICAL_REVIEW, STATUS, X_AGENS, PATIENT) %>% 
  # Filtrer på faggrupper
  filter(GROUP_NAME %in% faggrupper) %>% 
  collect() %>% 
  # Remove identical rows
  distinct() %>%
  # Add column indicating if sample is a child sample
  # Child sample have a different ORIGNIAL_SAMPLE than SAMPLE_NUMBER
  mutate(child_sample = if_else(ORIGINAL_SAMPLE == SAMPLE_NUMBER, "NO", "YES"))

# Trekke ut SAMPLE_NUMBER
samples_sample_number <- samples %>% distinct(SAMPLE_NUMBER) %>% pull(SAMPLE_NUMBER)

# [S05] Hent tester
# Finne batch eller sekvenserings run
test <- tbl(con, "TEST_VIEW") %>% 
  # CHANGED_ON brukes bare i Fil 3 [S14]
  select("TEST_NUMBER", "SAMPLE_NUMBER", "ANALYSIS", "X_TECH_REVIEW", "BATCH", "CHANGED_ON") %>% 
  collect()

## ==================================================
## [S06] Define analysis code groups
## ==================================================

ngs_seq_codes <- c("NGS", "SC2_NGS", "MPX_WGS", "SC2_WGS", "INF_WGS", "RSV_WGS",
                   "ROV_WGS", "HPV_WGS", "UKJVIRUS_WGS", "HCRES_NGS", "HCVNGS",
                   "HCGEN_NGS", "HCVNGS_PROSJ", "SC2_VAR_NGS",
                   # Lagt til fra Fil 3 (#23)
                   "EV_WGS", "HBV_WGS")

extraction_codes <- c("EKSTRAKSJON", "EKSTR", "EXT", "EXTPRI", "EXTFLU", "EXTNEP",
                      "EXT_MOR", "EXT_PAR", "EXT_ROTA", "EXT_ROTA_S",
                      "EXT_NORO", "EXT_NORO_S", "EXT_B19", "EXT_RUB",
                      "EXTPRI_SA2R", "EXTPRI_A", "EXTPRI_B", "EXTPRI_FYR", "PROVEPREP")

culture_codes <- c("DYRKING", "VDYRKE", "VDYRKA", "BGM", "L20B", "A549", "RD",
                   "FORT_ROTA", "FORT_ROTA_S", "FORT_NORO", "FORT_NORO_S")

pcr_codes <- c(
  # Influensa
  "INFABPCR", "INFA_TRICDC", "INFB_TRICDC", "SC2_TRICDC", "INFSC2",
  "INFAH1H3", "INFBVYPCR", "INFB_VIC", "INFB_YAM",
  # INFBVY er den eldre koden for samme analyse som INFBVYPCR (#23)
  "INFBVY",
  "IAH1C1", "IAH3C1", "IACDC1", "IBCDC1", "IASAC1",
  "INAH5A", "INAH5B", "INFAH9", "INFAN9", "H7VLA2", "RNPPCR",
  # Luftveir / VIRUS_CMN
  "RSVABPCR", "RSVA_PCR", "RSVB_PCR", "RINPCR", "RSPCR",
  "HMPVPCR", "ADPCR", "PA1PCR", "PA2PCR", "PA3PCR",
  "COV229EPCR", "COVNL63PCR", "COVOC43PCR", "COVHKU1PCR", "MPLPNEUPCR",
  "NCOV2019RDRP", "SARSCOV2RDRP", "SABEPCR", "SABNPCR", "SABRDRP",
  "SEK_COV", "EV_D68_PCR", "EV_D68_PCR_2",
  # Entero / POL_ENT
  "ENTERO_PCR_RNA", "ENTPCR", "ENT_RNA",
  # Rota / Noro
  "ROTA_PCR_RNA", "ROTAVP4_PCR", "ROTAVP6_PCR", "ROTAVP7_PCR", "ROTA_RIDAGENE",
  "NORO_PCR_RNA", "NOROPCR", "NOROPCR_RT",
  # MMR / B19 / Parvovirus
  "MOPCR", "MOPCR_RT", "MOPCR_CDC", "MOPCR_CDC_REPL",
  "RUPCR", "RUPCR_CDC", "RUPCR_CDC_REPL",
  "PAPCR_CDC", "PAPCR_CDC_REPL", "PARPCR", "PARPCR_PRIM", "PARPCR_SEK",
  "B19PCR",
  # HEP_HIV
  "HCVPCR", "HIRPCR", "HIDPCR", "HAPCR", "HAPCR-PRIM", "HAPCR-SEK",
  "HBQPCR", "HBQPCR_BG", "HBSPCR1", "HBSPCR2",
  "HBQPCRSENS_1ML", "HBQPCRSANSLAV",
  "HEVPCR", "HAVPCR", "HCPCR",
  # Arbovirus
  "DENPCR-IH", "DENPCR-ALT", "DENPCR-CDC",
  "CHIPCR-IH", "CHIPCR-ALT", "ZIKPCR-ALTO", "VNVPCR-IH",
  "YFVPCR", "TBEPCR",
  # HPV
  "HPV_QPCR", "HPV_LUMINEX",
  # Lagt til fra Fil 3 (#23)
  "ROTARIX_PCR", "ROVPCR", "OPXVPCR"
)

serology_codes <- c(
  # Influensa
  "IASRH1",
  # MMR / B19 / Parvo
  "MOGENZ", "MOGMIC", "MOMENZ", "MOMMIC",
  "RUGENZ", "RUMMED", "RUMMIC", "RUGSER", "RUMEUR", "RUGEUR", "MOMEUR", "MOGEUR",
  "PAMSER", "PAMMIC", "PAGSER", "PAGMIC", "PAGT",
  "B19GSER", "B19MSER", "B19GBIO", "B19MBIO",
  "TBEGSER", "TBEMSER", "TBEGENZ", "TBEMENZ", "TBEGIF", "TBEMIF",
  # HEP_HIV
  "HIAGB", "HIAGNB", "HIIE", "HIGWB",
  "HBSEU", "HBCPIE", "HBEIF", "HBSIFQ", "HBSNEU", "HBSGEN1", "HBSGEN2",
  "HAIF", "HAIFV", "HAMF", "HBSKVA", "HBSKVAR",
  "WBLT22_STRIP", "HCV_LIA", "HCVB", "HDAGDS", "HDIEDS",
  # Arbovirus / VIRUS_CMN
  "DENGIF", "DENMIF", "DENNS1",
  "CHIGIF", "CHIMIF", "YFVGIF", "YFVMIF",
  "JEVGIF", "JEVMIF", "VNVGIF", "VNVMIF",
  "ZIKGIF", "ZIKMIF", "ZIGEUR", "ZIMEUR",
  "HANGIF", "HANMIF", "SFVGIF", "SFVMIF", "SINGIF", "SINMIF",
  "DEGEUR", "DEMEUR", "CHIMEUR", "CHIGEUR",
  # Lagt til fra Fil 3 (#23): varianter (_BG, _FORT, 71, WB-strips) av koder over
  "HBCPIE_BG", "HCVB_BG", "HBSEU_BG", "HIAGB_BG", "HIIE_BG",
  "HIAGNB_FORT", "HBSNEU_FORT", "HCVB71", "HAIF71",
  "HIGWB_STRIP", "HIGWB_ENV", "HIGWB_GAG", "HIGWB_POL", "HIGWB_HIV2",
  "PAMENZ", "PAGENZ"
)

# Sanger-sekvensering, genotyping og resistens (ikke NGS) (#37).
# HCRES_NS*-kodene (én per legemiddel) er bevisst utelatt: de er delresultater av samme analyse (RG12).
seq_typing_codes <- c(
  # Genotyping
  "HAGEN1", "HCGEN", "HCGENA", "HCGR3", "HEVGEN",
  # Sanger / annen sekvensering
  "SC2_VAR_SANG", "ENTERO_SEKVENS", "NORO_SEKVENS", "NOROSEK", "ROTAVIRUS_SEKV",
  "N_HCSEK", "N_HIRSEK", "N_HIDSEK", "INF_PYRO",
  # Resistens
  "HBRES", "HCRES"
)

## ==================================================
## [S15] Codes deliberately not counted
## ==================================================

# Analysekoder som bevisst ikke telles (RG13, #40). De står ikke i noen kategoriliste,
# tas ikke med i Fil 3, og skrives til Fil 5. Bare eksakte koder.
# Begrunnelsene er bare ASCII: æøå i tekst i skriptet blir feil når skriptet kjøres på serveren.
excluded_codes <- tribble(
  ~ANALYSIS,           ~reason,
  # Administrative koder og arbeidsflyt
  "SC2_STAMMENR",      "Administrativ",
  "LVAKONKL",          "Administrativ",
  "FECESFORB",         "Administrativ",
  "DONOR",             "Administrativ",
  "VHBBEH",            "Administrativ",
  "VHCBEH",            "Administrativ",
  "HBVAKM",            "Administrativ",
  "EAE",               "Administrativ",
  "ZZ_SABEPCR_FYR_QC", "Administrativ",
  "N_HA4KOM",          "Administrativ",
  "N_HB4KOM",          "Administrativ",
  "N_HC4KOM",          "Administrativ",
  "N_HD4KOM",          "Administrativ",
  "N_HE4KOM",          "Administrativ",
  "N_HT4KOM",          "Administrativ",
  # Koder som ikke er i bruk lenger
  "Z_HCNGS",           "Ikke i bruk",
  "Z_SC2_DEL6970",     "Ikke i bruk",
  "Z_SC2_TRI_OMIKRON", "Ikke i bruk"
) %>%
  mutate(rule = "RG13")

# Alle koder som telles i en kategori
category_codes <- c("NGS_PREP", ngs_seq_codes, extraction_codes, culture_codes,
                    pcr_codes, serology_codes, seq_typing_codes)

# En kode skal bare stå ett sted. Står den både i en kategoriliste og her, telles den
both <- intersect(excluded_codes$ANALYSIS, category_codes)
if (length(both) > 0) {
  warning("Koder b\u00e5de i en kategoriliste og i excluded_codes (telles): ",
          paste(both, collapse = ", "))
}

## ==================================================
## [S07] Classify tests into buckets
## ==================================================

ngs_info <- test %>% 
  # Behold virusprøver
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>% 
  # Behold relevante analysekoder
  filter(ANALYSIS %in% c("NGS_PREP", ngs_seq_codes,
                         extraction_codes, culture_codes,
                         pcr_codes, serology_codes, seq_typing_codes)) %>%
  # Gruppere prøvene etter bucket
  mutate(bucket = case_when(
    ANALYSIS == "NGS_PREP" & X_TECH_REVIEW == "A"          ~ "Auth_NGS_PREP",
    ANALYSIS == "NGS_PREP"                                 ~ "NotAuth_NGS_PREP",
    ANALYSIS %in% ngs_seq_codes & X_TECH_REVIEW == "A"     ~ "Auth_NGS_SEQ",
    ANALYSIS %in% ngs_seq_codes                            ~ "NotAuth_NGS_SEQ",
    ANALYSIS %in% extraction_codes & X_TECH_REVIEW == "A"  ~ "Auth_EXTRACTION",
    ANALYSIS %in% extraction_codes                         ~ "NotAuth_EXTRACTION",
    ANALYSIS %in% culture_codes & X_TECH_REVIEW == "A"     ~ "Auth_CULTURE",
    ANALYSIS %in% culture_codes                            ~ "NotAuth_CULTURE",
    ANALYSIS %in% pcr_codes & X_TECH_REVIEW == "A"         ~ "Auth_PCR",
    ANALYSIS %in% pcr_codes                                ~ "NotAuth_PCR",
    ANALYSIS %in% serology_codes & X_TECH_REVIEW == "A"    ~ "Auth_SEROLOGY",
    ANALYSIS %in% serology_codes                           ~ "NotAuth_SEROLOGY",
    ANALYSIS %in% seq_typing_codes & X_TECH_REVIEW == "A"  ~ "Auth_SEQ_TYPING",
    ANALYSIS %in% seq_typing_codes                         ~ "NotAuth_SEQ_TYPING",
    TRUE                                                  ~ NA_character_
  )) %>%
  filter(!is.na(bucket)) %>%
  # Beholde relevante kolonner
  select(SAMPLE_NUMBER, bucket, BATCH) %>% 
  # Tester uten batch-ID får en fast verdi, så en test alltid gir en ikke-tom celle.
  # Ellers blir paste() til teksten "NA", som ikke kan skilles fra "ingen test" (#48)
  mutate(BATCH = if_else(is.na(BATCH) | BATCH == "", "UTEN_BATCH", BATCH)) %>%
  # For hver SAMPLE_NUMBER og bucket, concatenate BATCH med komma
  group_by(SAMPLE_NUMBER, bucket) %>% 
  summarise(value = paste(unique(BATCH), collapse = ","), .groups = "drop") %>% 
  # Spre (pivot_wider) hver prøve på en enkelt linje
  pivot_wider(names_from = bucket,
              values_from = value,
              values_fill = "") # Empty string if bucket absent
  
  
# [S08] Joine med sample-info
final <- left_join(samples, ngs_info, by = c("SAMPLE_NUMBER" = "SAMPLE_NUMBER")) %>%
  rename("SAMPLE.STATUS" = STATUS) %>%
  # Prøver uten tester i en kategori får tom celle, ikke NA, så "ingen test" alltid er tom (#48)
  mutate(across(matches("^(Auth|NotAuth)_"), ~ coalesce(.x, "")))

# Write File 1: sample-level wide table
write_tsv(final, outfile_F1)

## ==================================================
## File 2: VIRUS_POWERBI_results.tsv
## Long-format diagnostic result values per sample
## ==================================================

# [S09] Whitelist of (ANALYSIS, NAME) pairs with diagnostic value.
# Admin/workflow fields (Autohandling, MSISLABDB, Rådatafil, Utført av, etc.)
# are intentionally excluded.
# æøå i NAME skrives som \u-escape (f.eks. "p\u00e5"), så navnet blir likt uansett hvordan
# skriptet leses på serveren. Navnene fra LIMS gjøres om til UTF-8 før matching i [S10] (#46).
result_whitelist <- tribble(
  ~ANALYSIS,       ~NAME,
  # --- PCR: influensa ---
  "INFABPCR",      "Influensa A",
  "INFABPCR",      "Influensa B",
  "INFABPCR",      "ct. A",
  "INFABPCR",      "ct. B",
  "INFA_TRICDC",   "Resultat",
  "INFA_TRICDC",   "ct. INFA",
  "INFB_TRICDC",   "Resultat",
  "INFB_TRICDC",   "ct. INFB",
  "SC2_TRICDC",    "Resultat",
  "SC2_TRICDC",    "ct. SC2",
  "INFSC2",        "Resultat",
  "INFSC2",        "ct. SC2",
  "INFSC2",        "ct. InfA",
  "INFSC2",        "ct. InfB",
  "IAH3C1",        "Resultat",
  "IAH3C1",        "H3",
  "IAH3C1",        "ct. H3",
  "IASRH1",        "Resultat",
  "IASRH1",        "H1pdm09",
  "IASRH1",        "ct. H1",
  # --- PCR: RSV ---
  "RSVA_PCR",      "Resultat",
  "RSVA_PCR",      "ct. RSVA",
  "RSVB_PCR",      "Resultat",
  "RSVB_PCR",      "ct. RSVB",
  "RSVABPCR",      "ct. RSVA",
  "RSVABPCR",      "ct. RSVB",
  # --- PCR: HEP_HIV (#56) ---
  "HIRPCR",        "Resultat",
  "HIRPCR",        "Konklusjon",
  # --- Serology: arbovirus (IF-tester, står i serology_codes) ---
  "DENGIF",        "Resultat DENV-1",
  "DENGIF",        "Resultat DENV-2",
  "DENGIF",        "Resultat DENV-3",
  "DENGIF",        "Resultat DENV-4",
  "DENGIF",        "Konklusjon DENV-1",
  "DENGIF",        "Konklusjon DENV-2",
  "DENGIF",        "Konklusjon DENV-3",
  "DENGIF",        "Konklusjon DENV-4",
  "CHIGIF",        "Resultat",
  "CHIGIF",        "Konklusjon",
  # --- Serology: MMR / B19 ---
  "MOGENZ",        "Konklusjon",
  "MOGENZ",        "Result_num",
  "MOGENZ",        "Titer",
  "MOGENZ",        "S / Positiv CO %",
  "MOGMIC",        "Konklusjon",
  "MOGMIC",        "Result_num",
  "MOGMIC",        "S / Positiv CO %",
  "PAMSER",        "Konklusjon",
  "PAMSER",        "Result_num_avlest",
  "PAMSER",        "S / Positiv CO %",
  "PAMMIC",        "Konklusjon",
  "PAMMIC",        "Result_num",
  "PAMMIC",        "S / Positiv CO %",
  "MOMENZ",        "Konklusjon",
  "MOMENZ",        "Result_num",
  "MOMENZ",        "S / Positiv CO %",
  "RUGENZ",        "Konklusjon",
  "RUGENZ",        "Result_num",
  "RUGENZ",        "Titer",
  "RUGSER",        "Konklusjon",
  "RUGSER",        "Result_num_avlest",
  "B19GSER",       "Konklusjon",
  "B19GSER",       "Result_num_avlest",
  "B19MSER",       "Konklusjon",
  "B19MSER",       "Result_num_avlest",
  # --- Serology: HEP_HIV ---
  "HIAGB",         "Konklusjon",
  "HIAGB",         "Result_num",
  "HIAGB",         "S/CO prosent",
  "HAIFV",         "Konklusjon",
  "HAIFV",         "Resultat_txt",
  "HAIFV",         "Resultat_num",
  "HCVB",          "Konklusjon",
  "HCVB",          "Result_num",
  "HCVB",          "S/CO prosent",
  # --- NGS/WGS typing + QC ---
  "NGS",           "Genotype fra skript",
  "NGS",           "Gj. snittlig dybde",
  "NGS",           "Dekning % av genomet",
  "NGS",           "Kvalitet p\u00e5 sekvensen",
  # Lagt til fra resultatfeltene på NGS (#56)
  "NGS",           "Genotype fra skript alt. 1",
  "NGS",           "Genotype fra skript alt. 2",
  "NGS",           "Genotype manuell",
  "NGS",           "SekvensID",
  "NGS_PREP",      "NGS-status",
  "NGS_PREP",      "Ct",
  "NGS_PREP",      "Agens",
  "SC2_NGS",       "Genetisk variant",
  "SC2_NGS",       "Stammenr",
  "INF_WGS",       "Subtype",
  "INF_WGS",       "Clade",
  "RSV_WGS",       "Clade",
  "MPX_WGS",       "Klade",
  "MPX_WGS",       "Lineage",
  "MPX_WGS",       "Stammenavn",
  # --- Culturing ---
  "VDYRKE",        "Konklusjon",
  "VDYRKE",        "Funn",
  "VDYRKE",        "eMSIS status",
  "VDYRKA",        "Konklusjon",
  "VDYRKA",        "Funn"
)

# Navn fra LIMS kommer som Windows-1252, navn fra skriptet som UTF-8. Gjør begge om til
# UTF-8 før de sammenlignes, ellers matcher aldri navn med æøå (#46). Tekst som allerede
# er gyldig UTF-8 (også ren ASCII) beholdes. Base-funksjoner, ikke stringr (#32)
to_utf8 <- function(x) {
  ok <- validUTF8(x)
  x[!ok] <- iconv(x[!ok], from = "CP1252", to = "UTF-8")
  Encoding(x) <- "UTF-8"
  x
}

# Alle koder i whitelisten skal stå i en kategoriliste, ellers får de tom analysis_category i F2
not_in_category <- setdiff(result_whitelist$ANALYSIS, category_codes)
if (length(not_in_category) > 0) {
  warning("Koder i result_whitelist som ikke st\u00e5r i en kategoriliste: ",
          paste(not_in_category, collapse = ", "))
}

## ==================================================
## [S17] Result fields deliberately not included
## ==================================================

# Resultatfelt som bevisst ikke tas med i F2 (RG14, #56): administrasjon og arbeidsflyt,
# og fritekst, som kan inneholde hva som helst. Gjelder feltnavnet på alle analysekoder.
# Feltene er heller ikke med i F6. Bare eksakte navn, med \u-escape for æøå.
# Begrunnelsene er bare ASCII, som i excluded_codes [S15].
excluded_result_fields <- tribble(
  ~NAME,                       ~reason,
  "Autohandling",              "Administrativ",
  "Autohandling_tabres",       "Administrativ",
  "MSISLABDB",                 "Administrativ",
  "R\u00e5datafil",            "Administrativ",
  "Utf\u00f8rt av",            "Administrativ",
  "utf\u00f8rt av",            "Administrativ",
  "Tabular Results sekvens",   "Administrativ",
  "Tabular Results SeqSphere", "Administrativ",
  "eMSIS ref",                 "Administrativ",
  "Meldeskjemanr",             "Administrativ",
  "Fritekst",                  "Fritekst",
  "Kommentar",                 "Fritekst",
  "Kommentar_NGS",             "Fritekst",
  "Felles kommentar",          "Fritekst",
  "Netlab Kommentar",          "Fritekst",
  "Agenskommentar",            "Fritekst"
) %>%
  mutate(rule = "RG14")

# Et felt skal bare stå ett sted. Står det både i whitelisten og her, kommer det med i F2
both_fields <- intersect(result_whitelist$NAME, excluded_result_fields$NAME)
if (length(both_fields) > 0) {
  warning("Resultatfelt b\u00e5de i result_whitelist og i excluded_result_fields (tas med): ",
          paste(both_fields, collapse = ", "))
}

# [S10] Hent resultater for virusprøvene. Alle feltene brukes i F6 [S18],
# de whitelistede i F2
results_virus <- tbl(con, "RESULT_VIEW") %>%
  select(SAMPLE_NUMBER, TEST_NUMBER, ANALYSIS, NAME, ENTRY, FORMATTED_ENTRY,
         ENTERED_ON, CHANGED_ON) %>%
  collect() %>%
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>%
  mutate(
    value = coalesce(
      na_if(as.character(FORMATTED_ENTRY), ""),
      na_if(as.character(ENTRY), "")
    ),
    # Brukes bare til matching. NAME beholdes som den kom fra LIMS
    name_key = to_utf8(NAME)
  ) %>%
  filter(!is.na(value))

# Behold whitelistede par
results_file2 <- results_virus %>%
  inner_join(result_whitelist, by = c("ANALYSIS", "name_key" = "NAME")) %>%
  # Linjeskift i en verdi deler raden i to i TSV-fila. Byttes med mellomrom (#39).
  # useBytes, fordi teksten fra LIMS er Windows-1252 (andre bytes endres ikke)
  mutate(value = gsub("[\r\n]+", " ", value, useBytes = TRUE)) %>%
  select(SAMPLE_NUMBER, TEST_NUMBER, ANALYSIS, NAME, value, ENTERED_ON, CHANGED_ON)

# [S11] Map each ANALYSIS code to a broad category so Power BI can offer
# two-level filtering (category → analysis code) via separate slicers.
category_lookup <- bind_rows(
  tibble(ANALYSIS = "NGS_PREP",       analysis_category = "NGS_PREP"),
  tibble(ANALYSIS = ngs_seq_codes,    analysis_category = "NGS_SEQ"),
  tibble(ANALYSIS = extraction_codes, analysis_category = "Extraction"),
  tibble(ANALYSIS = culture_codes,    analysis_category = "Culture"),
  tibble(ANALYSIS = pcr_codes,        analysis_category = "PCR"),
  tibble(ANALYSIS = serology_codes,   analysis_category = "Serology"),
  tibble(ANALYSIS = seq_typing_codes, analysis_category = "Seq_typing")
)

results_file2 <- left_join(results_file2, category_lookup, by = "ANALYSIS")

# Write File 2: long-format results table
write_tsv(results_file2, outfile_F2)

## ==================================================
## [S14] File 3: VIRUS_POWERBI_unclassified_codes.tsv
## Analysekoder på virusprøver som ikke er i noen kategori, og ikke bevisst utelatt
## (for å finne manglende koder, #23, #40)
## ==================================================

unclassified <- test %>%
  # Behold virusprøver. Ellers kommer koder fra alle faggrupper i LIMS med
  filter(SAMPLE_NUMBER %in% samples_sample_number) %>%
  filter(!ANALYSIS %in% category_codes,
         !ANALYSIS %in% excluded_codes$ANALYSIS) %>%
  left_join(distinct(samples, SAMPLE_NUMBER, GROUP_NAME), by = "SAMPLE_NUMBER") %>%
  group_by(GROUP_NAME, ANALYSIS) %>%
  summarise(n_tests     = n(),
            n_samples   = n_distinct(SAMPLE_NUMBER),
            # Unngår -Inf og advarsel når alle CHANGED_ON er NA. CHANGED_ON[NA_integer_]
            # er NA med samme klasse som CHANGED_ON, så typen er lik i alle grupper
            last_change = if (all(is.na(CHANGED_ON))) CHANGED_ON[NA_integer_] else max(CHANGED_ON, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(desc(n_tests))

write_tsv(unclassified, outfile_F3)

## ==================================================
## [S15] File 5: VIRUS_POWERBI_excluded_codes.tsv
## Analysekoder som bevisst ikke telles (#40). Ikke koblet til prøver
## ==================================================

write_tsv(excluded_codes %>% arrange(rule, reason, ANALYSIS), outfile_F5)

## ==================================================
## [S16] File 4: VIRUS_POWERBI_sample_codes.tsv
## Kobling mellom prøver og analysekoder, siste fem år (#42, RG08)
## ==================================================

# Prøver mottatt de siste fem årene (rullerende). Prøver uten mottaksdato er ikke med
f4_start <- Sys.Date() %m-% years(5)
recent_samples <- samples %>%
  filter(!is.na(RECD_DATE), as.Date(RECD_DATE) >= f4_start) %>%
  distinct(SAMPLE_NUMBER) %>%
  pull(SAMPLE_NUMBER)

# Én rad per prøve og analysekode. Koder i excluded_codes (Fil 5) er ikke med.
# Koder som ikke står i en kategoriliste, får kategorien "Ukategorisert"
sample_codes <- test %>%
  filter(SAMPLE_NUMBER %in% recent_samples,
         !ANALYSIS %in% excluded_codes$ANALYSIS) %>%
  group_by(SAMPLE_NUMBER, ANALYSIS) %>%
  summarise(n_tests = n(),
            n_auth  = sum(X_TECH_REVIEW %in% "A"),
            .groups = "drop") %>%
  left_join(category_lookup, by = "ANALYSIS") %>%
  mutate(analysis_category = coalesce(analysis_category, "Ukategorisert")) %>%
  select(SAMPLE_NUMBER, ANALYSIS, analysis_category, n_tests, n_auth)

write_tsv(sample_codes, outfile_F4)

## ==================================================
## [S18] File 6: VIRUS_POWERBI_unlisted_result_fields.tsv
## Resultatfelt på virusprøver som ikke er i whitelisten, og ikke bevisst utelatt
## (for å utvide whitelisten, #56)
## ==================================================

# Én rad per faggruppe, analysekode og resultatfelt. Bare felt med verdi, som i F2.
# Koder i excluded_codes (F5) og felt i excluded_result_fields (RG14) er ikke med
unlisted_fields <- results_virus %>%
  filter(!ANALYSIS %in% excluded_codes$ANALYSIS,
         !name_key %in% excluded_result_fields$NAME) %>%
  anti_join(result_whitelist, by = c("ANALYSIS", "name_key" = "NAME")) %>%
  left_join(distinct(samples, SAMPLE_NUMBER, GROUP_NAME), by = "SAMPLE_NUMBER") %>%
  group_by(GROUP_NAME, ANALYSIS, name_key) %>%
  summarise(n_values    = n(),
            n_samples   = n_distinct(SAMPLE_NUMBER),
            # Som i F3 [S14]: NA med samme klasse når alle CHANGED_ON er NA
            last_change = if (all(is.na(CHANGED_ON))) CHANGED_ON[NA_integer_] else max(CHANGED_ON, na.rm = TRUE),
            .groups = "drop") %>%
  left_join(category_lookup, by = "ANALYSIS") %>%
  mutate(analysis_category = coalesce(analysis_category, "Ukategorisert"),
         # Om koden har noen felt i whitelisten. FALSE = ingen resultater fra koden i F2
         analysis_in_whitelist = ANALYSIS %in% result_whitelist$ANALYSIS) %>%
  # NAME skrives som UTF-8, så navnet kan kopieres rett inn i whitelisten (med \u-escape for æøå)
  select(GROUP_NAME, ANALYSIS, analysis_category, analysis_in_whitelist,
         NAME = name_key, n_values, n_samples, last_change) %>%
  arrange(desc(n_values))

write_tsv(unlisted_fields, outfile_F6)

# [S12] Close connection
odbc::dbDisconnect(con)
