# Regelregister

Telleregler og faglige beslutninger for Virus Dashboard. En regel sier **hva** som skal telles. `STEPS.md` sier **hvor** det gjøres. Når koden og en regel er uenige, er det en sak (status `Avvik`).

**Status:** `Vedtatt` (bestemt), `Implementert <versjon>`, `Avvik` (koden gjør noe annet), `Åpen` (ikke bestemt).

## Oversikt

| Kode | Regel | Status | Implementert i | Kilde |
|---|---|---|---|---|
| `RG01` | Bare de sju virusfaggruppene | Implementert 1.0 | `S04` | Opprinnelig kravnotat (nov. 2025) |
| `RG02` | Ekskluder barneprøver | Vedtatt. Flagg i uttrekket, filter i PBI | `S04` (flagg), `P02` | Møte 2026-02-24 |
| `RG03` | Ekskluder fryseprøver | Vedtatt. **Mangler i dokumentasjonen (2.0)** | `P02` | Møte 2026-02-24 |
| `RG04` | Ekskluder kansellerte og avviste prøver | **Avvik i dokumentasjonen (2.0)** | `P02` | Møte 2026-02-24 |
| `RG05` | Analysert = teknisk godkjent | Implementert 2.0 | `S07`, `P03` | Møte 2026-02-24 |
| `RG06` | Tester med `X_TECH_REVIEW` R eller X telles ikke | **Avvik (2.0)**. Foreslått i 2.1-dev | `S13`, `S07`, `S10` | Møte 2026-03-20 |
| `RG07` | Tester med resultat "Ikke utført" telles ikke | **Avvik (2.0)**. Foreslått i 2.1-dev | `S13`, `S07`, `S10` | Møte 2026-03-20 |
| `RG08` | Dashboardet viser bare tellinger | Vedtatt | `P03` | Møte 2026-02-24 |
| `RG09` | Bare analysekoder i kodelistene telles | Implementert 2.0. **Midlertidig** | `S06` | Designvalg 2.0 |
| `RG10` | F2 har bare whitelistede resultatfelt | Implementert 2.0 | `S09`, `S10` | Designvalg 2.0 (#11) |
| `RG11` | Avviste tester i dashboardet? | **Åpen** | — | Møte 2026-03-20 |

---

## RG01 Bare de sju virusfaggruppene

`GROUP_NAME` er en av `HEP_HIV`, `HPV`, `INFLUENSA`, `MMR`, `POL_ENT`, `ROTA`, `VIRUS_CMN`.

**Konsekvens:** nye faggrupper kommer ikke med automatisk. Endres listen, endres alle tall i F1, F2 og F3.

## RG02 Ekskluder barneprøver

`child_sample == "NO"`, dvs. `ORIGINAL_SAMPLE == SAMPLE_NUMBER`.

**Hvorfor:** barneprøver er restmateriale eller avledede rør (alikvot, ekstraksjonsrør). Tas de med, telles samme pasientprøve flere ganger.

## RG03 Ekskluder fryseprøver

`TEMPLATE != "STORAGE"`.

**Hvorfor:** fryseprøver er ekstrakter med eget LIMS-nummer (f.eks. de fleste influensaprøver). Tas de med, ser det ut som det har kommet inn omtrent dobbelt så mange prøver.

**Avvik:** feltet eksporteres, men 2.0-dokumentasjonen anbefaler ikke filteret. Se `#19`, `E2.1-09`.

## RG04 Ekskluder kansellerte og avviste prøver

`SAMPLE.STATUS` er ikke `X` (Cancelled) eller `R` (Rejected). `C` betyr *Complete* og skal **beholdes**.

**Hvorfor:** kansellerte og avviste prøver er som regel feilregistreringer.

**Avvik:** 2.0-dokumentasjonen sier at C og X skal ekskluderes. Hvis Power BI følger den, forsvinner alle ferdige prøver. Se `#18`, `E2.1-09`.

## RG05 Analysert = teknisk godkjent

En test teller som utført når `X_TECH_REVIEW == "A"` (`Auth_*`). Ventende eller ikke vurderte tester vises i `NotAuth_*` og kan brukes til å finne prøver som "henger".

## RG06 Tester med `X_TECH_REVIEW` R eller X telles ikke

Avviste (R) og kansellerte (X) tester skal verken telles i `Auth_*` eller `NotAuth_*`, og resultatene deres skal ikke være i F2.

**Avvik i 2.0:** `case_when` legger alt som ikke er A i `NotAuth_*`. Se `#20`. Foreslått rettet i `E2.1-05` og `E2.1-06`.

**Se også:** `RG11`.

## RG07 Tester med resultat "Ikke utført" telles ikke

En test med resultat IU (kode) / "IkkeUtført" (tekst) i `RESULT.ENTRY` er ikke analysert, selv om den er teknisk godkjent.

**Hvorfor:** ellers telles uutførte tester som analysert, og IU-verdier havner i nevneren for positivitetsrater (#14). Gjelder blant annet kansellerte HCVNGS-duplikater (#17).

**Avvik i 2.0:** ikke håndtert. Se `#21`. Foreslått i `E2.1-03`, `E2.1-05`, `E2.1-06`.

**Åpent:** hele testen ekskluderes hvis **ett** delresultat er IU. Om det er riktig, avhenger av hvilket resultat som er hovedresultatet. Se `#25`.

## RG08 Dashboardet viser bare tellinger

Dashboardet viser aggregerte tall, aldri resultater for enkeltpasienter. F2 inneholder resultatverdier for å kunne telle (f.eks. positive), men de skal ikke vises enkeltvis.

## RG09 Bare analysekoder i kodelistene telles

En test kommer bare med i F1 og får bare `analysis_category` i F2 hvis koden står i en av listene i `S06`.

**Konsekvens:** nye eller manglende koder blir usynlige (f.eks. `BVYPCR`, `#23`). F3 (`E2.1-07`) viser hvilke koder som mangler.

**Midlertidig:** bør erstattes av ANALYSIS-mastertabellen (`#26`).

## RG10 F2 har bare whitelistede resultatfelt

Bare `(ANALYSIS, NAME)`-par i `S09` kommer med i F2. Administrasjons- og arbeidsflytfelt (Autohandling, MSISLABDB, Rådatafil, Utført av osv.) er utelatt.

**Konsekvens:** nye resultattyper må legges til i whitelisten for å komme med.

## RG11 Avviste tester i dashboardet? (åpen)

Møtet 2026-03-20 nevnte at avviste tester (R) kanskje er relevante å vise. 2.1-dev fjerner dem (`RG06`).

**Hvis de skal vises:** ta `"R"` ut av `excluded_tests` (`S13`) og legg til `Rej_*`-bøtter i `S07`. Det gir nye kolonner i F1 og krever PBI-endring.

---

## Mal for ny regel

```markdown
## RGnn Kort navn

Presis definisjon (felt og verdier).

**Hvorfor:** begrunnelse.
**Kilde:** møte/sak og dato.
**Implementert i:** S##/P## (versjon), eller ikke ennå.
**Konsekvens:** hvilke tall som endres hvis regelen endres.
```
