# Endringslogg

Hver versjon av `virus_dashboard.R` og tilhørende dokumentasjon. Hver endring har en kode `E<versjon>-##` og en konsekvensvurdering (se [`README.md`](README.md#konsekvensvurdering-fylles-ut-for-hver-endring)).

Nyeste versjon øverst.

---

## 2.1-dev (foreslått, under test fra 2026-10-15)

**Status:** ikke merget til main. Testes mot LIMS i Test-miljøet. Patchen er laget mot main `eec9705`.

**Sammendrag:** fjerner tester som ikke skal telles (R/X og "Ikke utført"), filtrerer i databasen i stedet for i R, legger til en manglende influensakode og en ny fil (F3) som viser koder som mangler. Retter filterråd i dokumentasjonen.

**Samlet effekt (forventet):** F1 har like mange rader som før. Innholdet i `Auth_*` og `NotAuth_*` endres. F2 får færre rader. F3 er ny. Power BI må endre default-filtrene (`P02`).

**Testsjekkliste**
- [ ] Hvordan "Ikke utført" faktisk ser ut i `ENTRY` / `FORMATTED_ENTRY` (juster mønsteret i `E2.1-03` ved behov)
- [ ] `semi_join` virker mot viewene og er ikke tregere enn før
- [ ] F1: samme antall rader som 2.0. Stikkprøve på en prøve med R/X-test og en med IU-test
- [ ] F2: ingen `value` er IU / IkkeUtført
- [ ] F3: koder ser rimelige ut, og `BVYPCR` er ikke med
- [ ] æøå ser ut som før i Power BI
- [ ] Kjørt med samme R-versjon som serveren
- [ ] `virus_dashboard_compare.R` kjørt mot 2.0- og 2.1-utfilene, og tabellene limt inn under *Målt effekt*

### E2.1-01 Versjon i skripthodet

| | |
|---|---|
| **Saker** | — |
| **Steg / regler / filer** | — |
| **Faggrupper** | — |
| **Forventet effekt** | Ingen på data |
| **Krever PBI-endring** | Nei |

### E2.1-02 Prøvespørringen holdes lat

`SAMPLE_VIEW`-spørringen deles i `samples_db` (lat, i databasen) og `samples` (hentet inn i R).

| | |
|---|---|
| **Saker** | `#22` |
| **Steg / regler / filer** | `S04` |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på data. Gjør `E2.1-03` mulig |
| **Målt effekt** | *Fylles inn etter test* |
| **Krever PBI-endring** | Nei |

### E2.1-03 Filtrer tester og resultater i databasen, og finn tester som ikke skal telles

- `TEST_VIEW` og `RESULT_VIEW` filtreres med `semi_join(samples_db)` før `collect()`. `RESULT_VIEW` hentes én gang.
- `CHANGED_ON` legges til i testene (brukes bare i F3).
- Nytt steg `S13`: `excluded_tests` = tester med `X_TECH_REVIEW` R/X ∪ tester der et resultat er IU / "Ikke utført".
- IU matches med `grepl(..., useBytes = TRUE)`, fordi tekst fra ODBC er Windows-1252 og stringr feiler med *"invalid UTF-8 byte sequence"*.

| | |
|---|---|
| **Saker** | `#20`, `#21`, `#22` |
| **Steg / regler / filer** | `S05`, `S10`, `S13` (nytt). `RG06`, `RG07` |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på data i seg selv (effekten kommer i `E2.1-05` og `E2.1-06`). Kortere kjøretid |
| **Målt effekt** | *Fylles inn etter test (kjøretid, antall IU-tester per faggruppe)* |
| **Krever PBI-endring** | Nei |
| **Hvis det feiler** | Hvis `semi_join` feiler eller er treg mot viewene: `collect()` og så `filter(SAMPLE_NUMBER %in% samples_sample_number)` for det viewet |

### E2.1-04 Legg til `BVYPCR` i PCR-kodene

| | |
|---|---|
| **Saker** | `#23` |
| **Steg / regler / filer** | `S06`. `RG09`. F1, F2 (`analysis_category`) |
| **Faggrupper** | INFLUENSA |
| **Forventet effekt** | Flere influensaprøver med `Auth_PCR` / `NotAuth_PCR`. `BVYPCR`-resultater i F2 hvis de legges til i whitelisten (gjøres ikke her) |
| **Målt effekt** | *Fylles inn etter test* |
| **Krever PBI-endring** | Nei |
| **Åpent** | Antar at `BVYPCR` er influensa B Victoria/Yamagata-PCR. Må bekreftes |

### E2.1-05 Fjern ekskluderte tester før bøtteinndeling

`S07` fjerner testene i `excluded_tests` før klassifisering.

| | |
|---|---|
| **Saker** | `#20`, `#21`, `#17` |
| **Steg / regler / filer** | `S07`. `RG06`, `RG07`. F1 |
| **Faggrupper** | Alle. Størst effekt ventet for HEP_HIV (kansellerte HCVNGS-duplikater) |
| **Forventet effekt** | Antall rader i F1 uendret. R/X-tester forsvinner fra `NotAuth_*`. IU-tester forsvinner fra både `Auth_*` og `NotAuth_*`. Færre prøver telles som analysert. Tester uten `X_TECH_REVIEW` (NA) beholdes i `NotAuth_*`, som før |
| **Målt effekt** | *Fylles inn etter test: antall ikke-tomme celler per faggruppe × bøtte, før og etter* |
| **Krever PBI-endring** | Nei. Tallene i dashboardet endres |
| **Bakoverkompatibel** | Ja, med ett unntak: hvis en bøtte blir tom for alle prøver, forsvinner kolonnen fra F1 (`S07`) |

### E2.1-06 F2 gjenbruker resultatene og fjerner de samme testene

| | |
|---|---|
| **Saker** | `#21`, `#14` |
| **Steg / regler / filer** | `S10`. `RG06`, `RG07`. F2 |
| **Faggrupper** | Alle |
| **Forventet effekt** | Færre rader i F2. Ingen IU-verdier. Nevneren i positivitetsrater blir riktig |
| **Målt effekt** | *Fylles inn etter test: rader per faggruppe × analysis_category, før og etter* |
| **Krever PBI-endring** | Nei |

### E2.1-07 Ny fil F3: analysekoder som ikke er i noen kodeliste

Nytt steg `S14`. `VIRUS_POWERBI_unclassified_codes.tsv`: én rad per faggruppe × analysekode, med `n_tests`, `n_samples`, `last_change`.

| | |
|---|---|
| **Saker** | `#23` |
| **Steg / regler / filer** | `S14` (nytt). `RG09`. F3 (ny) |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på F1 og F2 |
| **Krever PBI-endring** | Nei (filen er til oss, ikke til dashboardet) |
| **Merk** | Ikke filtrert som dashboardet, og dekker all tid. Ikke en feilliste: mange koder er utenfor scope med vilje. Gir `-Inf` og en advarsel hvis `CHANGED_ON` bare er NA i en gruppe. Valgfri: kan droppes uten å påvirke resten |
| **Oppfølging** | Legg til en "Fil 3"-seksjon i utfil-dokumentasjonen hvis F3 beholdes |

### E2.1-08 Utfil-dokumentasjonen: versjon og godkjenningsmerknad

Versjon satt til 2.1-dev. Merknaden om godkjenning sier nå at R/X- og IU-tester er fjernet fra begge filene.

| | |
|---|---|
| **Saker** | `#20`, `#21` |
| **Steg / regler / filer** | Dokumentasjon. `RG06`, `RG07` |
| **Krever PBI-endring** | Nei |

### E2.1-09 Utfil-dokumentasjonen: riktige default-filtre

- Filter 2: ekskluder `SAMPLE.STATUS` **X og R**, ikke C og X. C (*Complete*) beholdes.
- Nytt filter 2b: `TEMPLATE != "STORAGE"`.

| | |
|---|---|
| **Saker** | `#18`, `#19` |
| **Steg / regler / filer** | Dokumentasjon, `P02`. `RG03`, `RG04` |
| **Faggrupper** | Alle. Fryseprøver: særlig INFLUENSA |
| **Forventet effekt** | Ingen på utfilene. **I dashboardet**, når PBI er endret: flere mottatte prøver (Complete-prøver kommer tilbake) og færre (fryseprøver fjernes). For influensa ventes omtrent en halvering fra fryseprøvefilteret |
| **Målt effekt** | *Fylles inn når PBI er endret* |
| **Krever PBI-endring** | **Ja.** Default-filtrene i `P02` må sjekkes og endres |

### E2.1-10 `LIMS-kopi_tabeller.md`: `RESULT_VIEW`

| | |
|---|---|
| **Saker** | `#24` |
| **Krever PBI-endring** | Nei |

### E2.1-11 Stegkoder `[S##]` i skriptet

Kommentarer `[S01]`–`[S12]` ved starten av hvert steg, og en peker til `STEPS.md` øverst. Bare kommentarer.

| | |
|---|---|
| **Saker** | — |
| **Steg / regler / filer** | Alle steg (bare kommentarer) |
| **Faggrupper** | — |
| **Forventet effekt** | Ingen på data |
| **Krever PBI-endring** | Nei |
| **Merk** | Den opprinnelige 2.1-dev-patchen (mot `eec9705`) passer ikke lenger på denne versjonen av skriptet. Bruk patchen som er laget på nytt mot stegkodene. Den legger også til `[S13]` og `[S14]` |

---

## 2.0-dev (i prod, main `eec9705`, 2026-06-05)

*Rekonstruert fra git-historikken. Ikke delt i enkeltendringer.*

- **2026-02-24** (`4773767`, `23f7a6c`, `33fea67`): `TEMPLATE` (fryseprøver) og `child_sample` lagt til i F1. Grunnlag for `RG02` og `RG03`.
- **2026-03-11** (`4673b78`): utfil-dokumentasjonen opprettet.
- **2026-06-05** (`eec9705`): versjon 2 fra dev til main. Analysebøtter `Auth_*` / `NotAuth_*` for seks kategorier (`S06`, `S07`). Ny fil F2 med whitelistede resultater og `analysis_category` (`S09`–`S11`). Lukket `#11`, `#13`.

**Kjente avvik i 2.0** (rettes i 2.1-dev): `RG03`, `RG04` (dokumentasjon), `RG06`, `RG07` (kode). Se `#18`–`#24`.

## 1.x (før 2026-02)

Bare prøvedato og sekvensering.

- **2026-01-29** (`f44f7b5`): mer robust og portabel kjøring.
- **2026-02-09** (`b17420d`): tilkoblingsinformasjon fra konfigurasjon (miljøvariabler) i stedet for i skriptet.

---

## Mal for ny endring

```markdown
### E<versjon>-## Kort beskrivelse

Hva som er endret, og hvorfor (1–3 linjer).

| | |
|---|---|
| **Saker** | #nn |
| **Steg / regler / filer** | S## / P## / RG## / F# |
| **Faggrupper** | Alle / ... |
| **Forventet effekt** | Hvilke tall endres, og i hvilken retning |
| **Målt effekt** | Tall fra testkjøringen, per faggruppe × bøtte (bare aggregerte tall) |
| **Krever PBI-endring** | Ja/nei, og hva |
| **Bakoverkompatibel** | Ja/nei |
```
