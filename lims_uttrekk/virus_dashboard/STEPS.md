# Stegregister

Hvert steg i uttrekket har en fast kode. `S##` er steg i `virus_dashboard.R`, `P##` er steg på Power BI-siden. Nummeret er en ID, ikke en rekkefølge: nye steg får neste ledige nummer, selv om de legges inn midt i skriptet.

**Gjelder versjon:** 2.0-dev (main, `eec9705`). Endringer som er foreslått i 2.1-dev er markert med *2.1-dev*.

**Kobling til koden:** hvert steg starter med en kommentar `[S##]` i `virus_dashboard.R` (f.eks. `## [S07] Classify tests into buckets`). Søk etter koden for å finne steget. `S02` har to seksjoner. `S14` er merket fra #23. `S13` merkes når #20–#22 legges inn. Nye steg skal alltid få en `[S##]`-kommentar.

## Oversikt

| Kode | Steg | Leser | Skriver | Regler |
|---|---|---|---|---|
| `S01` | Valider miljøvariabler | Miljø | — | — |
| `S02` | Les variabler og sett utfilnavn | Miljø | `outpath`, `outfile_F1` … `outfile_F5` | — |
| `S03` | Koble til LIMS | SQL Server | `con` | — |
| `S04` | Hent prøver | `SAMPLE_VIEW` | `samples`, `samples_sample_number` | `RG01`, flagg for `RG02` |
| `S05` | Hent tester | `TEST_VIEW` | `test` | — |
| `S06` | Definer analysekodegrupper | — | sju kodelister (seks før #37) | `RG09`, `RG12` |
| `S07` | Klassifiser tester i bøtter | `test`, kodelister | `ngs_info` | `RG05`, (`RG06`, `RG07` fra 2.1-dev) |
| `S08` | Bygg og skriv F1 | `samples`, `ngs_info` | **F1** | — |
| `S09` | Resultat-whitelist | — | `result_whitelist` | `RG10` |
| `S10` | Hent og filtrer resultater for F2 | `RESULT_VIEW` | `results_file2` | `RG10`, (`RG06`, `RG07` fra 2.1-dev) |
| `S11` | Analysekategori og skriv F2 | `results_file2`, kodelister | **F2** | `RG12` |
| `S12` | Lukk tilkobling | — | — | — |
| `S13` | *2.1-dev:* Finn tester som ikke skal telles | `test`, `results` | `excluded_tests` | `RG06`, `RG07` |
| `S14` | *2.1-dev (#23):* Bygg og skriv F3 | `test`, `samples`, kodelister, `excluded_codes` | **F3** | `RG09`, `RG12`, `RG13` |
| `S15` | *2.2-dev (#40):* Koder som bevisst ikke telles, og skriv F5 | — | `excluded_codes`, `category_codes`, **F5** | `RG13` |
| `S16` | *2.2-dev (#42):* Kobling mellom prøver og analysekoder, skriv F4 | `test`, `samples`, `category_lookup`, `excluded_codes` | **F4** | `RG08`, `RG13` |
| `P01` | Relasjon F1–F2 | F1, F2 | Datamodell | — |
| `P02` | Default-filtre for prøver | F1 | — | `RG02`, `RG03`, `RG04` |
| `P03` | Telle analyserte prøver | F1 | Measures | `RG05`, `RG08` |
| `P04` | *2.2-dev (#42):* Fra analysekode til prøver, og fra prøve til analysekoder | F1, F4 | Visninger | `RG08` |

## Utfiler

| Kode | Fil | Grain | Skrives i |
|---|---|---|---|
| `F1` | `VIRUS_POWERBI_lw_uttrekk.tsv` | Én rad per prøve | `S08` |
| `F2` | `VIRUS_POWERBI_results.tsv` | Én rad per resultatverdi | `S11` |
| `F3` | `VIRUS_POWERBI_unclassified_codes.tsv` (*2.1-dev*, #23) | Én rad per faggruppe × analysekode. Vedlikeholdsfil, ikke til dashboardet | `S14` |
| `F4` | `VIRUS_POWERBI_sample_codes.tsv` (*2.2-dev*, #42) | Én rad per prøve × analysekode, siste fem år | `S16` |
| `F5` | `VIRUS_POWERBI_excluded_codes.tsv` (*2.2-dev*, #40) | Én rad per analysekode. Koder som bevisst ikke telles, ikke koblet til prøver | `S15` |

Alle skrives til `<OUTDIR>/<RUN_ENV>/ToOrdinary/LW_Datauttrekk/`. Kolonner: se [`../Scripts/VIRUS_POWERBI_output_columns.md`](../Scripts/VIRUS_POWERBI_output_columns.md).

---

## Steg i `virus_dashboard.R`

### S01 Valider miljøvariabler

**Gjør:** stopper skriptet hvis `OUTDIR`, `SQL_DRIVER`, `SQL_SERVER`, `SQL_DATABASE` eller `RUN_ENV` mangler. Variablene settes av `AutoReport.bat`.

### S02 Les variabler og sett utfilnavn

**Gjør:** leser miljøvariablene og stopper hvis `OUTDIR` ikke finnes. Setter alle utfilene samlet: `outpath` (`<OUTDIR>/<RUN_ENV>/ToOrdinary/LW_Datauttrekk`) og `outfile_F1` … `outfile_F5`, hver med en kommentar om innhold, formål og hvilket steg som skriver den. Nye utfiler skal deklareres her, med neste ledige F-kode.

### S03 Koble til LIMS

**Gjør:** åpner ODBC-tilkoblingen til LIMS-kopien.

**Kjente svakheter**
- Hvis tilkoblingen feiler, skriver `tryCatch` feilmeldingen **inn i F1**. Power BI laster da en feilmelding som data, og forrige gyldige F1 er borte. Se `#28`.
- Tekst fra ODBC kommer som Windows-1252, ikke UTF-8. stringr/ICU feiler på æøå. Bruk base-funksjoner med `useBytes = TRUE`, eller konverter først. Se `E2.1-03`.

### S04 Hent prøver

**Gjør:** henter 12 kolonner fra `SAMPLE_VIEW` for de sju virusfaggruppene (`RG01`), fjerner identiske rader og legger til `child_sample` (`YES` hvis `ORIGINAL_SAMPLE != SAMPLE_NUMBER`).

**Viktig:** skriptet **filtrerer ikke** bort barneprøver, fryseprøver eller kansellerte prøver. Det eksporterer feltene (`child_sample`, `TEMPLATE`, `SAMPLE.STATUS`), og filtreringen skjer i Power BI (`P02`).

*2.1-dev:* spørringen holdes lat (`samples_db`), så S05 og S10 kan filtreres i databasen.

### S05 Hent tester

**Gjør:** henter `TEST_NUMBER`, `SAMPLE_NUMBER`, `ANALYSIS`, `X_TECH_REVIEW` og `BATCH` fra `TEST_VIEW`.

*2.1-dev (#23):* `CHANGED_ON` legges til. Den brukes bare i F3 (`S14`) og er borte før F1.

**Kjente svakheter:** 2.0 henter **hele** `TEST_VIEW` inn i R før filtrering, også tester på prøver som ikke er virusprøver. *2.1-dev (#22):* filtreres i databasen med `semi_join` mot `samples_db`.

### S06 Definer analysekodegrupper

**Gjør:** hardkodede lister: `NGS_PREP` (én kode), `ngs_seq_codes`, `extraction_codes`, `culture_codes`, `pcr_codes`, `serology_codes` og, fra 2.1-dev, `seq_typing_codes` (Sanger, genotyping, resistens; #37). Listene styrer både bøttene i F1 (`S07`), `analysis_category` i F2 (`S11`) og hva som regnes som uklassifisert i F3 (`S14`).

*2.1-dev (#23):* koder fra første F3-kjøring lagt til der tilhørigheten er klar (varianter `_BG`, `_FORT`, `71` og WB-strips av koder som allerede står i en liste, `*_WGS`, `*PCR`, søsken av eksisterende koder). Kommentarene i koden sier hvilke. Usikre koder venter på avklaring i #38. Per-legemiddel-kodene `HCRES_NS*` er bevisst utelatt (`RG12`).

**Kjente svakheter:** en kode som ikke står i en liste kommer ikke med i dashboardet (`RG09`). Matching er eksakt og skiller mellom store og små bokstaver. F3 (`S14`) viser kodene som mangler. En kode må bare stå i én liste. På sikt bør listene hentes fra ANALYSIS-mastertabellen (`#26`).

### S07 Klassifiser tester i bøtter

**Gjør:** for hver test på en virusprøve med en kode i S06: legger testen i `Auth_<kategori>` hvis `X_TECH_REVIEW == "A"`, ellers i `NotAuth_<kategori>` (`RG05`). Samler unike `BATCH` per prøve og bøtte, kommaseparert, og sprer til én rad per prøve.

**Kategorier:** `NGS_PREP`, `NGS_SEQ`, `EXTRACTION`, `CULTURE`, `PCR`, `SEROLOGY`, og fra 2.1-dev `SEQ_TYPING` (#37). Altså opptil 14 kolonner.

**Kjente svakheter**
- 2.0: `NotAuth_*` tar med alt som ikke er A, også R (avvist) og X (kansellert). Det bryter `RG06`. *2.1-dev* fjerner dem (`E2.1-05`).
- 2.0: tester med resultat "Ikke utført" telles som analysert. Det bryter `RG07`. *2.1-dev* fjerner dem (`E2.1-05`).
- Hvis en bøtte ikke finnes for noen prøve, mangler kolonnen helt i F1 (`pivot_wider` lager bare kolonner som har data).
- 2.0: en test uten `BATCH` ga teksten `NA` i bøtta, det samme som "ingen test". *2.1-dev* gir slike tester verdien `UTEN_BATCH` (#48, `E2.1-14`).

### S08 Bygg og skriv F1

**Gjør:** `left_join` av prøvene (S04) med bøttene (S07), så alle prøver kommer med, også de uten tester. Gir `STATUS` nytt navn, `SAMPLE.STATUS`. Skriver F1.

*2.1-dev (#48):* tomme bøtter blir `""`, ikke `NA`, så "ingen test" alltid er tom (`E2.1-15`). `NA` i de andre kolonnene (f.eks. `X_MEDICAL_REVIEW`) betyr fortsatt manglende informasjon.

### S09 Resultat-whitelist

**Gjør:** en liste med ca. 100 `(ANALYSIS, NAME)`-par med diagnostisk verdi (Ct-verdier, titere, konklusjoner, genotype/klade, NGS-QC). Administrasjonsfelt er utelatt med vilje (`RG10`).

### S10 Hent og filtrer resultater for F2

**Gjør:** henter resultatene for virusprøvene, beholder bare par i whitelisten (S09), og setter `value` til `FORMATTED_ENTRY` eller, hvis tom, `ENTRY`. Rader uten verdi fjernes.

*2.1-dev:* `RESULT_VIEW` hentes én gang tidligere i skriptet (filtrert i databasen) og brukes både i S13 og her. Testene i `excluded_tests` fjernes (`E2.1-06`).

### S11 Analysekategori og skriv F2

**Gjør:** legger til `analysis_category` fra kodelistene i S06, så Power BI kan filtrere i to nivåer (kategori → analysekode). Skriver F2.

*2.1-dev (#37):* ny verdi `Seq_typing`. Den dukker bare opp hvis whitelisten i `S09` får par for disse kodene, noe den ikke har ennå.

### S12 Lukk tilkobling

**Gjør:** `dbDisconnect`.

### S13 Finn tester som ikke skal telles (*2.1-dev*)

**Gjør:** lager `excluded_tests`, som er unionen av
- tester med `X_TECH_REVIEW` R eller X (`RG06`), og
- tester der **minst ett** resultat har `ENTRY` eller `FORMATTED_ENTRY` lik IU / "Ikke utført" (`RG07`). Matches på bytes på grunn av Windows-1252.

Brukes i S07 og S10.

**Åpent:** skal én IU på et delresultat utelukke hele testen? Se `#25`.

### S14 Bygg og skriv F3 (*2.1-dev*, #23)

**Gjør:** teller alle analysekoder på virusprøver som ikke står i noen liste i S06, per faggruppe (prøvens `GROUP_NAME`): `n_tests`, `n_samples`, `last_change` (siste `CHANGED_ON`, NA hvis ingen test har dato).

**Merk**
- *2.2-dev (#40):* koder i `excluded_codes` (`S15`) er ikke med, så F3 bare viser koder som ikke er avklart.
- F3 filtrerer selv til virusprøvene (`samples_sample_number`), fordi `test` i 2.0 inneholder hele `TEST_VIEW`. Filteret blir overflødig, men ufarlig, når #22 filtrerer i databasen.
- F3 er ellers ikke filtrert som dashboardet. Den tar med barne-, fryse- og kansellerte prøver og tester med R/X eller IU, så ingen kode går tapt.
- Den inneholder bare aggregerte tall, og er en vedlikeholdsfil, ikke en del av dashboardet.
- `last_change` bruker `CHANGED_ON[NA_integer_]` i stedet for `NA` når alle datoer mangler, så kolonnen har samme type i alle grupper uansett dplyr-versjon.

### S15 Koder som bevisst ikke telles, og skriv F5 (*2.2-dev*, #40)

**Gjør:** to seksjoner i koden.
- Rett etter kodelistene (`S06`): en hardkodet liste `excluded_codes` med analysekode og begrunnelse (`RG13`), og `category_codes`, alle koder som står i en kategoriliste. Hvis en kode står i begge, gir skriptet en advarsel, og koden telles.
- Etter F3: skriver lista til F5.

**Merk**
- Bare eksakte koder, ingen mønstre. En ny administrativ eller utgått kode dukker derfor opp i F3 til noen legger den inn.
- Lista påvirker bare F3 (og senere F4, #42). F1 og F2 er uendret, fordi de bare teller koder i kategorilistene.
- Per-legemiddel-kodene `HCRES_NS*` står ikke i lista. De blir stående i F3 (`RG12`).

### S16 Kobling mellom prøver og analysekoder, skriv F4 (*2.2-dev*, #42)

**Gjør:** for prøver mottatt de siste fem årene (rullerende, etter `RECD_DATE`): én rad per prøve og analysekode med `analysis_category` fra `category_lookup` (`S11`), eller `Ukategorisert`, og `n_tests` / `n_auth`. Koder i `excluded_codes` (`S15`) er ikke med. Skriver F4.

**Merk**
- Femårsgrensen og at `PATIENT` ikke er med, følger av `RG08`.
- Prøver uten mottaksdato er ikke med (se #34).
- Tester med R/X eller "Ikke utført" er med i `n_tests` inntil `excluded_tests` (`S13`, #20/#21) også brukes her.
- Filtrerer til virusprøvene via prøvelista, fordi `test` ennå ikke er filtrert i databasen (#22).

---

## Steg på Power BI-siden

Disse stegene eies av Power BI-siden. Beskrivelsen er hentet fra utfil-dokumentasjonen og er **ikke kontrollert mot rapporten**. Power BI-siden fyller inn hvordan det faktisk er gjort.

### P01 Relasjon F1–F2

F1 (1) til F2 (\*) på `SAMPLE_NUMBER`.

### P02 Default-filtre for prøver

Skal implementere `RG02` (barneprøver), `RG03` (fryseprøver) og `RG04` (kansellerte/avviste). Hvis filtrene er bygd etter 2.0-dokumentasjonen, ekskluderer de `SAMPLE.STATUS` C (*Complete*) og tar med fryseprøver. Se `#18`, `#19`.

### P03 Telle analyserte prøver

En prøve regnes som analysert i en kategori hvis `Auth_<kategori>` ikke er tom (`RG05`). Dashboardet viser tellinger, og enkeltprøver bare med prøvenummer og analysekoder, uten `PATIENT` (`RG08`).

### P04 Fra analysekode til prøver, og fra prøve til analysekoder (*2.2-dev*, #42)

Utsnitt på `F4[ANALYSIS]` som filtrerer F1, og en tabell over F4 for valgt prøve. Relasjonen F1–F4 må filtrere begge veier, eller et measure må håndtere det. `PATIENT` vises ikke, og eksport er blokkert (`RG08`, #43).
