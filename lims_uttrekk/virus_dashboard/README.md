# Virus Dashboard: utvikling og styring

Denne mappen samler alt som trengs for å forstå, endre og etterprøve uttrekket fra LIMS til Virus Dashboard i Power BI.

| Dokument | Innhold |
|---|---|
| [`STEPS.md`](STEPS.md) | **Stegregister.** Hva hvert steg i `virus_dashboard.R` (og på Power BI-siden) gjør, input/output, hvilke regler det implementerer, kjente svakheter |
| [`RULES.md`](RULES.md) | **Regelregister.** Telleregler og faglige beslutninger, med kilde, dato og hvor de er implementert |
| [`ISSUES.md`](ISSUES.md) | **Saksindeks.** Etiketter, filtre og koblinger fra hver GitHub-sak til steg/regler/endringer. Status ligger på GitHub |
| [`CHANGELOG.md`](CHANGELOG.md) | **Endringslogg.** Hver versjon og hver endring, med konsekvensvurdering (hvilke filer, faggrupper og tall som påvirkes) |
| [`../Scripts/VIRUS_POWERBI_output_columns.md`](../Scripts/VIRUS_POWERBI_output_columns.md) | **Utfiler.** Kolonnebeskrivelse og anbefalte filtre for Power BI |

Kode: [`../Scripts/virus_dashboard.R`](../Scripts/virus_dashboard.R). Kjøres hver natt fra [`../Batch/AutoReport.bat`](../Batch/AutoReport.bat), i Test og Prod.

---

## Oversikt

```
LIMS-kopi (SQL Server)
  SAMPLE_VIEW ─┐
  TEST_VIEW  ──┼─> virus_dashboard.R ─┬─> F1  VIRUS_POWERBI_lw_uttrekk.tsv   (én rad per prøve)
  RESULT_VIEW ─┤                      ├─> F2  VIRUS_POWERBI_results.tsv      (én rad per resultat)
  REGION_VIEW ─┘ (fylke, fra 2.2-dev)
                                      ├─> F3  VIRUS_POWERBI_unclassified_codes.tsv  (fra 2.1-dev)
                                      ├─> F4  VIRUS_POWERBI_sample_codes.tsv        (fra 2.2-dev)
                                      ├─> F5  VIRUS_POWERBI_excluded_codes.tsv      (fra 2.2-dev)
                                      └─> F6  VIRUS_POWERBI_unlisted_result_fields.tsv  (fra 2.2-dev)
                                                   │
                                                   v
                                      Power BI: Virus Dashboard (F1 1:* F2 på SAMPLE_NUMBER)
```

---

## ID-system

Alle ting som skal kunne refereres har en fast kode. Kodene endres aldri, og gjenbrukes aldri, selv om noe slettes eller flyttes. Nye ting får neste ledige nummer.

| Kode | Hva | Eksempel | Register |
|---|---|---|---|
| `S##` | **Steg** i `virus_dashboard.R` | `S07` Klassifiser tester i bøtter | `STEPS.md` |
| `P##` | **Steg på Power BI-siden** | `P02` Default-filtre | `STEPS.md` |
| `RG##` | **Regel**: telleregel eller faglig beslutning | `RG03` Ekskluder fryseprøver | `RULES.md` |
| `#nn` | **Sak** på GitHub (`folkehelseinstituttet/ngs_scripts`, etikett `virus-dashboard`). De midlertidige ID-ene `NY-01`–`NY-19` er nå `#18`–`#36` | `#20` R/X-tester telles som NotAuth | GitHub, `ISSUES.md` |
| `E<versjon>-##` | **Endring** som er implementert eller foreslått i en versjon | `E2.1-03` Fjern R/X-tester før bøtteinndeling | `CHANGELOG.md` |
| `F1`–`F6` | **Utfil** | `F2` = `VIRUS_POWERBI_results.tsv` | `STEPS.md` |

Bruk kodene i commit-meldinger, PR-er, saker og kodekommentarer, f.eks. `E2.1-06 (#17, RG07): fjern IU-tester fra F2`. Da kan man søke seg fra en sak til koden og tilbake.

**Status for saker:** etiketter på GitHub: `status: idé` → `status: planlagt` → `status: pågår` → `status: til test` → lukket (= i prod). Eller `status: utsatt`, eller lukket med `wontfix` (avvist), med begrunnelse. Se [`ISSUES.md`](ISSUES.md#etiketter).

**Status for regler:** `Vedtatt` (bestemt, ikke nødvendigvis implementert), `Implementert` (med versjon), `Avvik` (koden gjør noe annet enn regelen), `Åpen` (ikke bestemt).

**Versjoner:** `MAJOR.MINOR`. `-dev` betyr at versjonen ikke er ferdig. `-dev` fjernes i skripthodet når den siste saken i versjonens milepæl er merget til main (#33). Til da står `-dev` også på main.

---

## Arbeidsflyt for en endring

1. **Sak.** Opprett en sak på GitHub med malen *Virus Dashboard*. Beskriv problemet, ikke løsningen. Sett etiketter for side, type, status og eventuelt faggruppe, og legg den i milepælen for versjonen den skal løses i. Legg til en rad i `ISSUES.md` hvis den berører steg, regler eller endringer.
2. **Gren.** Lag en gren fra main: `vd/<saksnr>-kort-navn`, f.eks. `vd/21-ikke-utfort`. Sett saken til `status: pågår`.
3. **Endring.** Skriv koden. Legg til en `E`-oppføring under neste versjon i `CHANGELOG.md` og fyll ut konsekvensvurderingen (se under).
4. **Registre.** Oppdater `STEPS.md` hvis et steg endres eller kommer til, `RULES.md` hvis en regel implementeres eller endres, og utfil-dokumentasjonen hvis kolonner endres.
5. **Test.** Kjør gammel og ny versjon i Test-miljøet, rett etter hverandre, med hver sin utmappe. Sammenlign med [`../Scripts/virus_dashboard_compare.R`](../Scripts/virus_dashboard_compare.R) (se under), og lim tabellen inn under *Målt effekt* i endringsloggen. Sjekk at R-versjonen er den samme som på serveren (se `AutoReport.bat`).
6. **PR.** Åpne en PR med Virus Dashboard-malen (`…/compare/main...<gren>?template=virus_dashboard.md`), med `closes #nn`. Sett saken til `status: til test` mens den testes.
7. **Power BI.** Hvis endringen krever endring i Power BI (*Krever PBI-endring: ja*), lag en egen sak med `side: power-bi` og koble den til `E`-koden.
8. **Merge og prod.** Merge til main, og kopier skriptet til Prod på serveren. Saken lukkes av `closes #nn`. Skriv i saken hvilken dato endringen kom i prod.

### Konsekvensvurdering (fylles ut for hver endring)

Hver endring i `CHANGELOG.md` skal svare på:

- **Steg / regler / filer:** hvilke `S`, `P`, `RG` og `F` som berøres.
- **Faggrupper:** alle, eller hvilke.
- **Forventet effekt:** hvilke tall endres, og i hvilken retning. Eksempel: "Antall rader i F1 uendret. `NotAuth_*` blir tomme for prøver som bare har R/X-tester."
- **Målt effekt:** tallene fra testkjøringen, per faggruppe og bøtte. Fylles inn etter test.
- **Krever PBI-endring:** ja/nei, og hva.
- **Bakoverkompatibel:** om eksisterende Power BI-visninger fortsatt virker uten endring.

### Måle effekten: `virus_dashboard_compare.R`

```
Rscript virus_dashboard_compare.R <før-mappe> <etter-mappe> [utfil.tsv]
```

Hver mappe skal inneholde F1 og F2 (og eventuelt F3) fra én kjøring. Skriptet teller per faggruppe (og `TOTALT`), både for alle prøver (`alle`) og etter dashboardets default-filtre `RG02`–`RG04` (`dashboard`):

- `F1 prøver`, og antall prøver med noe i hver `Auth_*`- / `NotAuth_*`-kolonne
- `F2 rader <analysis_category>` og `F2 IU-verdier`
- `F3 koder`, hvis F3 finnes
- `Prøver bare i før` / `Prøver bare i etter`: bør være 0. Hvis ikke, er kjøringene gjort mot ulike data, og endringene blander kode og nye prøver

Den skriver ut en Markdown-tabell med bare målene som endret seg, klar til å limes inn i `CHANGELOG.md`. Med `utfil.tsv` skrives alle målene til fil. Resultatet inneholder bare aggregerte tall.

---

## Viktig: repoet er offentlig

`ngs_scripts` er et **offentlig** repo. Saker, dokumentasjon og endringslogg skal **bare** inneholde aggregerte tall (f.eks. "INFLUENSA: Auth_PCR −312"). Aldri prøvenummer, pasient-ID, resultater for enkeltprøver, navn, skjermbilder fra LIMS eller lenker til interne systemer. Detaljerte notater og møtereferater hører hjemme internt.
