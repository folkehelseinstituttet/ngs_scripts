# Saksoversikt

Alle saker for Virus Dashboard ligger på GitHub med etiketten [`virus-dashboard`](https://github.com/folkehelseinstituttet/ngs_scripts/issues?q=label%3Avirus-dashboard). **Status, diskusjon og beslutninger finnes bare der.** Denne filen er en indeks som kobler sakene til steg (`S`/`P`), regler (`RG`) og endringer (`E`).

**Nyttige filtre**
- [Åpne saker](https://github.com/folkehelseinstituttet/ngs_scripts/issues?q=is%3Aopen+label%3Avirus-dashboard)
- [Til test](https://github.com/folkehelseinstituttet/ngs_scripts/issues?q=is%3Aopen+label%3A%22status%3A+til+test%22)
- [Milepæl Virus Dashboard 2.1](https://github.com/folkehelseinstituttet/ngs_scripts/milestone/1) / [2.2](https://github.com/folkehelseinstituttet/ngs_scripts/milestone/2)
- [Uttrekkssiden](https://github.com/folkehelseinstituttet/ngs_scripts/issues?q=is%3Aopen+label%3A%22side%3A+uttrekk%22) / [Power BI-siden](https://github.com/folkehelseinstituttet/ngs_scripts/issues?q=is%3Aopen+label%3A%22side%3A+power-bi%22)

## Etiketter

| Etikett | Betydning |
|---|---|
| `virus-dashboard` | Alle Virus Dashboard-saker |
| `side: uttrekk` / `side: power-bi` / `side: drift` | Hvem som må gjøre noe: `virus_dashboard.R`, Power BI-rapporten, eller server/tilkobling/kjøring. En sak kan ha flere |
| `bug` / `enhancement` / `documentation` / `question` / `regel` | Type: feil, ny funksjon, dokumentasjon, spørsmål, telleregel (`RG##`) |
| `status: idé` → `status: planlagt` → `status: pågår` → `status: til test` | Status. Bytt etikett når statusen endres. `I prod` = lukket. `Avvist` = lukket med `wontfix` |
| `status: utsatt` | Venter på noe utenfor vår kontroll |
| `fg: <faggruppe>` | Gjelder særlig én faggruppe. Ingen `fg:`-etikett = alle |

Milepæler samler sakene som løses i en versjon (f.eks. *Virus Dashboard 2.1*).

---

## Indeks

`Tidl.` er den midlertidige ID-en sakene hadde før de ble opprettet på GitHub (2026-10-15). Eldre dokumenter og commits kan bruke den.

| Sak | Tidl. | Tittel | Side | Koblinger |
|---|---|---|---|---|
| `#10` | | Innsenders agens / innsenders resultat | Begge | Nye kolonner i `S04` eller `S10` |
| `#11` | | Eget uttrekk for analysekoder og eget for resultater (lukket, 2.0) | Uttrekk | F1/F2-oppdelingen, `S09`–`S11` |
| `#12` | | Rekvirent, og utvikling over tid | Begge | Feltet er ikke bekreftet. Kandidater i `ORDERS_VIEW`: `X_CLINICIAN`, `x_sample_submitter`, `X_GB_REKVID`. Ny kolonne i F1 |
| `#13` | | Nedtrekksmeny med analysekoder (lukket, 2.0) | PBI | `analysis_category`, `S11` |
| `#14` | | Positivitetsrater per agens/analyse over tid | PBI | Bygger på F2. Avhenger av `RG07` (`E2.1-06`), ellers er IU med i nevneren |
| `#15` | | Andel/antall innkomne prøver som er analysert | PBI | `P03`, `RG02`–`RG07`. Se også `#17 (1)`, `#31` |
| `#16` | | Forside med overordnet statistikk | Begge | Svartid (mottatt → analysert) krever en "ferdig"-dato, f.eks. `TEST.X_TECH_REVIEW_ON` eller `SAMPLE.DATE_COMPLETED`, som ikke eksporteres ennå |
| `#17 (1)` | | Innkomne vs. analyserte prøver (HCV) | PBI | Bruk HCVNGS: *Utført* vs. kansellert. En prøve kan ha både en kansellert og en utført kopi. Avhenger av `RG06`, `RG07` |
| `#17 (2)` | | Klinisk vs. overvåkning (HCV) | Begge | Testliste `HCVNGS_KLINISK` vs. `HCVNGS_OVERV`. Overvåkningsprøver er flagget som prosjekt. Ny kolonne i F1 |
| `#17 (3)` | | Geografisk fordeling | Begge | Fylke er trolig enkelt. Kommune/adresse er trolig for detaljert og må avklares med faggruppeleder. Kandidater: `SAMPLE_VIEW.X_ZIPCODE`, `ORDERS_VIEW.X_SAMPLED_LOC_ZIP`, `ORDERS_VIEW.X_COMMUNE` |
| `#18` | NY-01 | Dokumentasjonen ekskluderer `SAMPLE.STATUS` C (*Complete*) | Begge | `RG04`, `P02`, `E2.1-09` |
| `#19` | NY-02 | Ingen default-filter for fryseprøver | Begge | `RG03`, `P02`, `E2.1-09` |
| `#20` | NY-03 | R/X-tester telles i `NotAuth_*` | Uttrekk | `RG06`, `S07`, `S13`, `E2.1-03`, `E2.1-05` |
| `#21` | NY-04 | Tester med "Ikke utført" telles som analysert | Uttrekk | `RG07`, `S07`, `S10`, `S13`, `E2.1-03`, `E2.1-05`, `E2.1-06` |
| `#22` | NY-05 | Hele `TEST_VIEW` og `RESULT_VIEW` hentes inn i R | Uttrekk | `S04`, `S05`, `S10`, `E2.1-02`, `E2.1-03` |
| `#23` | NY-06 | Manglende analysekoder, og ingen oversikt over hvilke som mangler | Uttrekk | `RG09`, `S06`, `S14`, `E2.1-04`, `E2.1-07`, `E2.1-13`. Gren `vd/23-analysekoder`. Se #37, #38 |
| `#24` | NY-07 | `LIMS-kopi_tabeller.md` sier `RESULTS_VIEW`, koden bruker `RESULT_VIEW` | Uttrekk | `E2.1-10` |
| `#25` | NY-08 | Skal én IU på et delresultat utelukke hele testen? | Uttrekk | `RG07`, `S13`. Avhenger av Instrument Series-tabellen (bestilt 2026-03-20) |
| `#26` | NY-09 | Hent kodelister fra ANALYSIS-mastertabellen | Begge | `RG09`, `S06`. Venter på view (bestilt 2026-03-20) |
| `#27` | NY-10 | Skal avviste tester vises i dashboardet? | Begge | `RG11`, `RG06`, `S07`, `S13` |
| `#28` | NY-11 | Ved tilkoblingsfeil skrives feilmeldingen inn i F1 | Uttrekk | `S03` |
| `#29` | NY-12 | Automatisk oppdatering i Power BI | PBI | — |
| `#30` | NY-13 | Auto-uttrekk nede (databasetilkobling) | Drift | `S03` |
| `#31` | NY-14 | Prøver som er mottatt, men aldri satt opp til PCR | PBI | Nær `#15`. `P03` |
| `#32` | NY-15 | Langsiktig løsning på tegnkoding (ODBC Windows-1252) | Uttrekk | `S03` |
| `#33` | NY-16 | Versjonsnavn: skal `-dev` fjernes ved merge til main? | Uttrekk | README, *Versjoner* |
| `#34` | NY-17 | Prøver uten dato | Begge | `S04` |
| `#35` | NY-18 | Finne registreringsfeil (f.eks. mottaksdato før prøvetakingsdato) | Begge | `S04` |
| `#36` | NY-19 | Bruke `SAMPLE.STATUS` / `X_MEDICAL_REVIEW` til å finne prøver som "henger" | PBI | `RG05` |
| `#37` | | Ny kategori SEQ_TYPING (Sanger, genotyping, resistens) | Begge | `S06`, `S07`, `S11`, `RG12`, `E2.1-12`. Del av #23. Krever PBI-endring (nye kolonner) |
| `#38` | | Avklare usikre analysekoder fra første F3-kjøring | Uttrekk | `S06`, `RG09`. Oppfølging av #23. Spørsmål til faggruppene og LIMS-forvaltningen (`N_`-prefiks, suffikser). `INFBVY` avklart og lagt til under #23 |
| `#39` | | Linjeskift i resultatverdier ødelegger rader i F2 | Uttrekk | `S10`, F2. Finnes fra 2.0 |
| `#40` | | Liste over analysekoder som bevisst ikke tas med (F5) | Uttrekk | `S15` (nytt), `RG13` (ny), `RG12`, F3, F5 (ny). 2.2 |
| `#41` | | Regelavklaring: skal dashboardet vise enkeltprøver og analysekodene deres? | Begge | `RG08`, `P01`, `P03`. Må avklares før #42. 2.2 |
| `#42` | | F4: kobling mellom prøver og analysekoder | Begge | `S16` (nytt), F4 (ny), `RG08`, `RG09`, `RG13`. Avhenger av #40 og #41. 2.2 |

**Ny sak:** opprett den på GitHub med malen *Virus Dashboard* (tittel `[VD] …`, etiketten `virus-dashboard` settes automatisk). Sett side-, type- og statusetiketter, og legg til en rad her hvis saken berører steg, regler eller endringer.
