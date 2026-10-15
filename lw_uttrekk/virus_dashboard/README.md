# Virus Dashboard: utvikling og styring

Denne mappen samler alt som trengs for å forstå, endre og etterprøve uttrekket fra LabWare til Virus Dashboard i Power BI.

| Dokument | Innhold |
|---|---|
| [`STEPS.md`](STEPS.md) | **Stegregister.** Hva hvert steg i `virus_dashboard.R` (og på Power BI-siden) gjør, input/output, hvilke regler det implementerer, kjente svakheter |
| [`RULES.md`](RULES.md) | **Regelregister.** Telleregler og faglige beslutninger, med kilde, dato og hvor de er implementert |
| [`ISSUES.md`](ISSUES.md) | **Saksoversikt.** Alle åpne og lukkede saker med status, side og koblinger til steg/regler/endringer |
| [`CHANGELOG.md`](CHANGELOG.md) | **Endringslogg.** Hver versjon og hver endring, med konsekvensvurdering (hvilke filer, faggrupper og tall som påvirkes) |
| [`../Scripts/VIRUS_POWERBI_output_columns.md`](../Scripts/VIRUS_POWERBI_output_columns.md) | **Utfiler.** Kolonnebeskrivelse og anbefalte filtre for Power BI |

Kode: [`../Scripts/virus_dashboard.R`](../Scripts/virus_dashboard.R). Kjøres hver natt fra [`../Batch/AutoReport.bat`](../Batch/AutoReport.bat), i Test og Prod.

---

## Oversikt

```
LabWare-kopi (SQL Server)
  SAMPLE_VIEW ─┐
  TEST_VIEW  ──┼─> virus_dashboard.R ─┬─> F1  VIRUS_POWERBI_lw_uttrekk.tsv   (én rad per prøve)
  RESULT_VIEW ─┘                      ├─> F2  VIRUS_POWERBI_results.tsv      (én rad per resultat)
                                      └─> F3  VIRUS_POWERBI_unclassified_codes.tsv  (fra 2.1-dev)
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
| `#nn` | **Sak** på GitHub (`folkehelseinstituttet/ngs_scripts`) | `#17` Kommentarer fra faggruppe | GitHub, `ISSUES.md` |
| `NY-##` | **Sak som ikke er opprettet på GitHub ennå**. Byttes ut med `#nn` når saken opprettes | `NY-03` R/X-tester telles som NotAuth | `ISSUES.md` |
| `E<versjon>-##` | **Endring** som er implementert eller foreslått i en versjon | `E2.1-03` Fjern R/X-tester før bøtteinndeling | `CHANGELOG.md` |
| `F1`–`F3` | **Utfil** | `F2` = `VIRUS_POWERBI_results.tsv` | `STEPS.md` |

Bruk kodene i commit-meldinger, PR-er, saker og kodekommentarer, f.eks. `E2.1-06 (#17, RG07): fjern IU-tester fra F2`. Da kan man søke seg fra en sak til koden og tilbake.

**Status for saker:** `Idé` → `Planlagt` → `Pågår` → `Til test` → `I prod`. Eller `Avvist` / `Utsatt`, med begrunnelse.

**Status for regler:** `Vedtatt` (bestemt, ikke nødvendigvis implementert), `Implementert` (med versjon), `Avvik` (koden gjør noe annet enn regelen), `Åpen` (ikke bestemt).

**Versjoner:** `MAJOR.MINOR`. `-dev` betyr at versjonen ikke er i prod ennå. *Forslag:* `-dev` fjernes når endringen merges til main og kjører i prod. Ikke endelig bestemt.

---

## Arbeidsflyt for en endring

1. **Sak.** Opprett en sak på GitHub med `[VD]` først i tittelen (eller en `NY-##` i `ISSUES.md` inntil videre). Beskriv problemet, ikke løsningen. Angi side (uttrekk, Power BI eller begge) og hvilke faggrupper det gjelder.
2. **Gren.** Lag en gren fra main: `vd/<saksnr>-kort-navn`, f.eks. `vd/17-ikke-utfort`.
3. **Endring.** Skriv koden. Legg til en `E`-oppføring under neste versjon i `CHANGELOG.md` og fyll ut konsekvensvurderingen (se under).
4. **Registre.** Oppdater `STEPS.md` hvis et steg endres eller kommer til, `RULES.md` hvis en regel implementeres eller endres, og utfil-dokumentasjonen hvis kolonner endres.
5. **Test.** Kjør gammel og ny versjon i Test-miljøet, rett etter hverandre, med hver sin utmappe. Sammenlign med [`../Scripts/virus_dashboard_compare.R`](../Scripts/virus_dashboard_compare.R) (se under), og lim tabellen inn under *Målt effekt* i endringsloggen. Sjekk at R-versjonen er den samme som på serveren (se `AutoReport.bat`).
6. **Power BI.** Hvis endringen krever endring i Power BI (*Krever PBI-endring: ja*), lag en egen sak for Power BI-siden og koble den til `E`-koden.
7. **Merge.** Merge til main. Sett saken til `I prod` med dato, og lukk den.

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

`ngs_scripts` er et **offentlig** repo. Saker, dokumentasjon og endringslogg skal **bare** inneholde aggregerte tall (f.eks. "INFLUENSA: Auth_PCR −312"). Aldri prøvenummer, pasient-ID, resultater for enkeltprøver, navn, skjermbilder fra LabWare eller lenker til interne systemer. Detaljerte notater og møtereferater hører hjemme internt.
