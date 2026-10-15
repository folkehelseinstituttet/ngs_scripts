# Saksoversikt

Alle saker for Virus Dashboard, med status og koblinger til steg (`S`/`P`), regler (`RG`) og endringer (`E`).

**Kilde:** GitHub-saker (`#nn`) er kilden for sine saker. `NY-##` er saker som ikke er opprettet på GitHub ennå. Når en `NY-##` opprettes, skriv `#nn` i ID-kolonnen og behold `NY-##` i parentes, så gamle referanser fortsatt kan følges. Når alle saker er på GitHub, kan denne filen krympes til en ID-tabell.

**Side:** `Uttrekk` (`virus_dashboard.R`), `PBI` (Power BI-rapporten), `Begge`, `Drift` (server, tilkobling, kjøring).
**Type:** `Feil`, `Regel`, `Funksjon`, `Dok`, `Drift`, `Spørsmål`.
**Status:** `Idé` → `Planlagt` → `Pågår` → `Til test` → `I prod`, eller `Avvist` / `Utsatt`.

*Sist oppdatert: 2026-10-15.*

---

## Åpne saker på GitHub

| ID | Tittel | Side | Type | Faggruppe | Status | Koblinger |
|---|---|---|---|---|---|---|
| `#10` | Innsenders agens / innsenders resultat | Begge | Funksjon | INFLUENSA | Idé | Nye kolonner i `S04` eller `S10` |
| `#12` | Rekvirent, og utvikling over tid | Begge | Funksjon | Alle | Idé | Feltet er ikke bekreftet. Kandidater i `ORDERS_VIEW`: `X_CLINICIAN`, `x_sample_submitter`, `X_GB_REKVID`. Ny kolonne i F1 |
| `#14` | Positivitetsrater per agens/analyse over tid | PBI | Funksjon | Alle | Planlagt | Bygger på F2. Avhenger av `RG07` (`E2.1-06`), ellers er IU med i nevneren |
| `#15` | Andel/antall innkomne prøver som er analysert | PBI | Funksjon | Alle | Planlagt | `P03`, `RG02`–`RG07`. Se også `#17 (1)`, `NY-14` |
| `#16` | Forside med overordnet statistikk | Begge | Funksjon | Alle | Planlagt | Svartid (mottatt → analysert) krever en "ferdig"-dato, f.eks. `TEST.X_TECH_REVIEW_ON` eller `SAMPLE.DATE_COMPLETED`, som ikke eksporteres ennå |
| `#17 (1)` | Innkomne vs. analyserte prøver (HCV) | PBI | Funksjon | HEP_HIV | Planlagt | Bruk HCVNGS: *Utført* vs. kansellert. En prøve kan ha både en kansellert og en utført kopi. Avhenger av `RG06`, `RG07` |
| `#17 (2)` | Klinisk vs. overvåkning (HCV) | Begge | Funksjon | HEP_HIV | Idé | Testliste `HCVNGS_KLINISK` vs. `HCVNGS_OVERV`. Overvåkningsprøver er flagget som prosjekt. Ny kolonne i F1 |
| `#17 (3)` | Geografisk fordeling | Begge | Funksjon | Alle | Idé | Fylke er trolig enkelt. Kommune/adresse er trolig for detaljert og må avklares med faggruppeleder. Kandidater: `SAMPLE_VIEW.X_ZIPCODE`, `ORDERS_VIEW.X_SAMPLED_LOC_ZIP`, `ORDERS_VIEW.X_COMMUNE` |

## Saker som ikke er på GitHub ennå

| ID | Tittel | Side | Type | Faggruppe | Status | Koblinger |
|---|---|---|---|---|---|---|
| `NY-01` | Dokumentasjonen ekskluderer `SAMPLE.STATUS` C (*Complete*) | Begge | Feil | Alle | Til test (dok.). PBI: må sjekkes | `RG04`, `P02`, `E2.1-09` |
| `NY-02` | Ingen default-filter for fryseprøver | Begge | Feil | Alle (særlig INFLUENSA) | Til test (dok.). PBI: må sjekkes | `RG03`, `P02`, `E2.1-09` |
| `NY-03` | R/X-tester telles i `NotAuth_*` | Uttrekk | Feil | Alle | Til test | `RG06`, `S07`, `S13`, `E2.1-03`, `E2.1-05` |
| `NY-04` | Tester med "Ikke utført" telles som analysert | Uttrekk | Feil | Alle (særlig HEP_HIV, `#17`) | Til test | `RG07`, `S07`, `S10`, `S13`, `E2.1-03`, `E2.1-05`, `E2.1-06` |
| `NY-05` | Hele `TEST_VIEW` og `RESULT_VIEW` hentes inn i R | Uttrekk | Drift | Alle | Til test | `S04`, `S05`, `S10`, `E2.1-02`, `E2.1-03` |
| `NY-06` | Manglende analysekoder (f.eks. `BVYPCR`) | Uttrekk | Feil | INFLUENSA, flere? | Til test (`BVYPCR`). Flere koder: venter på F3 | `RG09`, `S06`, `E2.1-04`, `E2.1-07` |
| `NY-07` | `LIMS-kopi_tabeller.md` sier `RESULTS_VIEW`, koden bruker `RESULT_VIEW` | Uttrekk | Dok | — | Til test | `E2.1-10` |
| `NY-08` | Skal én IU på et delresultat utelukke hele testen? Hvilket resultat er hovedresultatet? | Uttrekk | Spørsmål | Alle | Åpen | `RG07`, `S13`. Avhenger av Instrument Series-tabellen (bestilt 2026-03-20) |
| `NY-09` | Hent kodelister fra ANALYSIS-mastertabellen i stedet for hardkoding | Begge | Funksjon | Alle | Utsatt (venter på view, bestilt 2026-03-20) | `RG09`, `S06` |
| `NY-10` | Skal avviste tester vises i dashboardet? | Begge | Spørsmål | Alle | Åpen | `RG11`, `RG06`, `S07`, `S13` |
| `NY-11` | Ved tilkoblingsfeil skrives feilmeldingen inn i F1 | Uttrekk | Feil | Alle | Idé | `S03`. Skriv til logg eller egen `.error`-fil, og la forrige F1 stå |
| `NY-12` | Automatisk oppdatering i Power BI | PBI | Drift | — | Ukjent (åpen siden 2026-06-11) | — |
| `NY-13` | Auto-uttrekk nede (databasetilkobling) | Drift | Drift | — | Ukjent (meldt 2026-06-12, ikke bekreftet løst) | `S03` |
| `NY-14` | Prøver som er mottatt, men aldri satt opp til PCR | PBI | Funksjon | Alle | Idé | Nær `#15`. `P03` |
| `NY-15` | Langsiktig løsning på tegnkoding (ODBC Windows-1252) | Uttrekk | Drift | Alle | Idé | `S03`. `encoding = "windows-1252"` i `dbConnect` endrer bytes i alle utfiler. Sjekk først Power BI-importen og de andre skriptene i `AutoReport.bat` |
| `NY-16` | Versjonsnavn: skal `-dev` fjernes ved merge til main? | Uttrekk | Spørsmål | — | Åpen | README, *Versjoner* |
| `NY-17` | Prøver uten dato: hva betyr det, og hvordan telles de? | Begge | Spørsmål | Alle | Idé | `S04`. Fra `../TODO_virus_dashboard.md` |
| `NY-18` | Finne registreringsfeil (f.eks. mottaksdato før prøvetakingsdato) | Begge | Funksjon | Alle | Idé | `S04`. Fra `../TODO_virus_dashboard.md` |
| `NY-19` | Bruke `SAMPLE.STATUS` / `X_MEDICAL_REVIEW` til å finne prøver som "henger" | PBI | Funksjon | Alle | Idé | `RG05`. Fra `../TODO_virus_dashboard.md` |

## Lukkede saker

| ID | Tittel | Status | Koblinger |
|---|---|---|---|
| `#11` | Eget uttrekk for analysekoder og eget for resultater | I prod (2.0, lukket 2026-06-08) | F1/F2-oppdelingen, `S09`–`S11` |
| `#13` | Nedtrekksmeny med analysekoder | I prod (2.0, lukket 2026-06-08) | `analysis_category`, `S11` |

---

## Mal for ny sak

Bruk denne strukturen i GitHub-saken (tittel: `[VD] Kort beskrivelse`), eller som en ny rad her:

```markdown
**Side:** Uttrekk / PBI / Begge / Drift
**Type:** Feil / Regel / Funksjon / Dok / Drift / Spørsmål
**Faggrupper:** Alle / ...
**Problem:** hva er feil eller mangler, og hvordan det synes i dashboardet.
**Berører:** S## / P## / RG## / F#
**Kilde:** hvem som meldte det, og når (ingen navn i offentlige saker hvis det ikke trengs).
```
