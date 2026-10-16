# Endringslogg

Hver versjon av `virus_dashboard.R` og tilhørende dokumentasjon. Hver endring har en kode `E<versjon>-##` og en konsekvensvurdering (se [`README.md`](README.md#konsekvensvurdering-fylles-ut-for-hver-endring)).

Nyeste versjon øverst.

---

## 2.2-dev (under arbeid)

**Status:** ikke i prod. Milepæl [*Virus Dashboard 2.2*](https://github.com/folkehelseinstituttet/ngs_scripts/milestone/2). Deler av 2.1 (#20–#22, #18, #19, #24) er ikke ferdige ennå, så skripthodet sier fortsatt 2.1-dev, med en egen linje for 2.2.

| Gren | Saker | Endringer | Status |
|---|---|---|---|
| `vd/40-utelatte-koder` | #40 | `E2.2-01`, `E2.2-02`, `E2.2-03` | PR #47 |
| `vd/42-prove-kode-kobling` | #42 | `E2.2-04`, `E2.2-05` | Pågår (bygger på `vd/40-utelatte-koder`) |

**Testsjekkliste**
- [x] (#40) F5 finnes, med kodene i `excluded_codes`
- [x] (#40) F3 har ingen av kodene i F5, og ellers de samme kodene som før
- [x] (#40) F1 og F2 er uendret (`virus_dashboard_compare.R`, prøvene som finnes i begge kjøringene)
- [x] (#40) `reason` i F5 er ren tekst uten tegnfeil (rettet til ASCII etter første testkjøring)
- [ ] (#42) F4 finnes, bare med prøver fra de siste fem årene, og uten kodene i F5
- [ ] (#42) Antall rader og filstørrelse i F4 er håndterbart for Power BI
- [ ] (#42) F1, F2, F3 og F5 er uendret
- [x] (#40) Ingen advarsel om koder både i en kategoriliste og i `excluded_codes`

### E2.2-01 Liste over koder som bevisst ikke telles

Nytt steg `S15`. Hardkodet liste `excluded_codes` med eksakte analysekoder og begrunnelse: administrative koder og arbeidsflyt (inkludert `N_*4KOM`-kodene) og `Z_`-koder som ikke er i bruk. Begrunnelsene er bare ASCII, fordi æøå i tekst i skriptet ble dobbeltkodet i første testkjøring. Ny vektor `category_codes` med alle koder i kategorilistene, og en advarsel hvis en kode står begge steder.

| | |
|---|---|
| **Saker** | #40 |
| **Steg / regler / filer** | `S15` (nytt). `RG13` (ny) |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på F1 og F2 |
| **Krever PBI-endring** | Nei |

### E2.2-02 F3 tar ikke med koder som bevisst ikke telles, og F5 skrives

`S14` filtrerer bort kodene i `excluded_codes`. `S15` skriver `VIRUS_POWERBI_excluded_codes.tsv` (F5) med kolonnene `ANALYSIS`, `reason` og `rule`.

| | |
|---|---|
| **Saker** | #40 |
| **Steg / regler / filer** | `S14`, `S15`. `RG13`. F3, F5 (ny) |
| **Faggrupper** | Alle |
| **Forventet effekt** | F3 blir mindre: kodene i lista er borte, resten er uendret. F5 er ny. F1 og F2 uendret |
| **Målt effekt** | Testkjøring av `vd/40-utelatte-koder` mot 2.1 dagen før. F3: 234 → 214 rader. 19 rader er de utelatte kodene (én kode står i to faggrupper), og 1 er `INFBVY`, som nå telles (`E2.1-04`). Ingen nye koder i F3, og ingen F5-koder igjen i F3. F5: 18 rader. F1 og F2: for prøvene som finnes i begge kjøringene, er de eneste endringene `INFBVY` og vanlig aktivitet mellom kjøringene (tester godkjent, nye ekstraksjoner) |
| **Krever PBI-endring** | Nei. F5 kan lastes som referansetabell hvis det er ønskelig |
| **Bakoverkompatibel** | Ja |

### E2.2-03 Dokumentasjon av F5 og RG13

Fil 5 i utfil-dokumentasjonen, `S15` i `STEPS.md`, `RG13` i `RULES.md`, og F5 i oversikten i `README.md`.

| | |
|---|---|
| **Saker** | #40 |
| **Krever PBI-endring** | Nei |


### E2.2-04 F4: kobling mellom prøver og analysekoder

Nytt steg `S16`. `VIRUS_POWERBI_sample_codes.tsv`: én rad per prøve og analysekode, med `analysis_category` (`Ukategorisert` for koder utenfor kategorilistene), `n_tests` og `n_auth`. Bare prøver mottatt de siste fem årene, og uten kodene i F5. Ingen `PATIENT` og ingen resultater (`RG08`).

| | |
|---|---|
| **Saker** | #42 |
| **Steg / regler / filer** | `S16` (nytt), `P04` (nytt). `RG08`, `RG13`. F4 (ny) |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på F1, F2, F3 og F5. F4 er ny, og trolig den største fila etter F1 |
| **Målt effekt** | *Fylles inn etter test: antall rader og filstørrelse* |
| **Krever PBI-endring** | **Ja.** Ta inn F4, relasjon til F1 som filtrerer begge veier, og visningene i `P04`. `PATIENT` skal ikke vises, og eksport skal være blokkert (#43) |
| **Bakoverkompatibel** | Ja. Eksisterende visninger påvirkes ikke |
| **Åpent** | Tester med R/X eller "Ikke utført" er med inntil #20/#21 også brukes her |

### E2.2-05 Dokumentasjon av F4

Fil 4 i utfil-dokumentasjonen (med oppsett i Power BI), `S16` og `P04` i `STEPS.md`, F4 i `RULES.md` (`RG08`, `RG13`) og i oversikten i `README.md`. Variablene for utfilene heter nå `outfile_F1` … `outfile_F5`, etter kodene i dokumentasjonen, og alle er deklarert samlet i `S02` med en kommentar om innhold og formål. Stiene er uendret.

| | |
|---|---|
| **Saker** | #42 |
| **Krever PBI-endring** | Nei (men beskriver oppsettet PBI trenger, se `E2.2-04`) |
---

## 2.1-dev (under arbeid fra 2026-10-15)

**Status:** ikke i prod. Milepæl [*Virus Dashboard 2.1*](https://github.com/folkehelseinstituttet/ngs_scripts/milestone/1). Endringene er delt i én gren per sak, og 2.1 er ferdig når alle grenene er merget:

| Gren | Saker | Endringer | Status |
|---|---|---|---|
| `vd/23-analysekoder` | #23, #37 | `E2.1-01`, `E2.1-04`, `E2.1-07`, `E2.1-12`, `E2.1-13` | Merget (#45), ikke i prod ennå |
| `vd/21-ekskluderte-tester` | #20, #21, #22 | `E2.1-02`, `E2.1-03`, `E2.1-05`, `E2.1-06`, `E2.1-08` | Ikke startet |
| `vd/18-dokumenterte-filtre` | #18, #19, #24 | `E2.1-09`, `E2.1-10` | Ikke startet |
| (main) | — | `E2.1-11` | Merget 2026-10-15 |

**Sammendrag:** flere analysekoder og en ny kategori for Sanger-sekvensering, genotyping og resistens, en ny fil (F3) som viser koder som mangler, fjerning av tester som ikke skal telles (R/X og "Ikke utført"), filtrering i databasen i stedet for i R, og riktige filterråd i dokumentasjonen.

**Samlet effekt (forventet):** F1 har like mange rader som før. Innholdet i `Auth_*` og `NotAuth_*` endres, og `Auth_SEQ_TYPING` / `NotAuth_SEQ_TYPING` er nye. F2 får færre rader. F3 er ny. Power BI må endre default-filtrene (`P02`) og ta inn de nye kolonnene.

**Testsjekkliste**
- [x] (#23) F1: samme antall rader som 2.0 (944 719), og `*_SEQ_TYPING`-kolonnene finnes
- [ ] (#23) Stikkprøve på en prøve med `HAGEN1`
- [x] (#23) F3: kodene som er lagt til i `E2.1-04` og `E2.1-12` er ikke med, og resten ser rimelige ut
- [x] (#23, #38) Finnes `BVYPCR` i dataene, eller heter koden `INFBVY`? `BVYPCR` finnes ikke. `INFBVY` er den eldre koden for samme analyse som `INFBVYPCR`, og er lagt til
- [x] (#23) Ny testkjøring etter at `INFBVY` er lagt til: INFLUENSA `Auth_PCR` / `NotAuth_PCR` går opp, og `INFBVY` er borte fra F3. Målt i testkjøringen av #40
- [ ] (#21) Hvordan "Ikke utført" faktisk ser ut i `ENTRY` / `FORMATTED_ENTRY` (juster mønsteret i `E2.1-03` ved behov)
- [ ] (#22) `semi_join` virker mot viewene og er ikke tregere enn før
- [ ] (#20, #21) F1: samme antall rader. Stikkprøve på en prøve med R/X-test og en med IU-test
- [ ] (#21) F2: ingen `value` er IU / IkkeUtført
- [ ] (alle) æøå ser ut som før i Power BI. For #23: prøvekolonnene i F1 og hele F2 er byte-identiske med 2.0, så ingen endring
- [ ] (alle) Kjørt med samme R-versjon som serveren
- [ ] (alle) `virus_dashboard_compare.R` kjørt mot forrige versjon, og tabellen limt inn under *Målt effekt*. Gjort for #23

### E2.1-01 Versjon i skripthodet

Versjon 2.1-dev og en linje som beskriver 2.1. Gjøres i den første grenen (#23). Hver senere gren utvider linjen med sitt.

| | |
|---|---|
| **Saker** | #23 (først), deretter #20–#22 |
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

### E2.1-04 Flere analysekoder i eksisterende lister

Koder fra første F3-kjøring (2026-10-15) der tilhørigheten er klar:

- **NGS_SEQ:** `EV_WGS`, `HBV_WGS`
- **PCR:** `INFBVY`, `ROTARIX_PCR`, `ROVPCR`, `OPXVPCR`. `INFBVY` er den eldre koden for samme analyse som `INFBVYPCR` (som allerede står i listen). `BVYPCR`, som ble meldt fra Power BI-siden, finnes ikke som analysekode, og er ikke med
- **Serologi:** varianter av koder som allerede står i listen: `HBCPIE_BG`, `HCVB_BG`, `HBSEU_BG`, `HIAGB_BG`, `HIIE_BG`, `HIAGNB_FORT`, `HBSNEU_FORT`, `HCVB71`, `HAIF71`, `HIGWB_STRIP`, `HIGWB_ENV`, `HIGWB_GAG`, `HIGWB_POL`, `HIGWB_HIV2`, og søsknene `PAMENZ`, `PAGENZ`

Usikre koder er ikke lagt inn. De er samlet i #38.

| | |
|---|---|
| **Saker** | #23 |
| **Steg / regler / filer** | `S06`. `RG09`. F1, F3 |
| **Faggrupper** | Mest HEP_HIV (serologivariantene), deretter MMR (`PAMENZ`, `PAGENZ`), ROTA (`ROTARIX_PCR`, `ROVPCR`), POL_ENT (`EV_WGS`) og INFLUENSA (`INFBVY`) |
| **Forventet effekt** | Antall rader i F1 uendret. Flere prøver med noe i `Auth_SEROLOGY` / `NotAuth_SEROLOGY`, `*_PCR` og `*_NGS_SEQ`. Kodene forsvinner fra F3. F2 uendret, fordi ingen av kodene står i whitelisten (`S09`) |
| **Målt effekt** | Testkjøring 2026-10-15, 2.0-dev mot `vd/23-analysekoder`, samme data (0 prøver bare i én kjøring). Antall prøver med noe i kolonnen, etter dashboardets default-filtre (`RG02`–`RG04`). F1: 944 719 rader i begge. <br>• HEP_HIV: `Auth_SEROLOGY` 18 804 → 21 120 (+2 316, +12,3 %), `NotAuth_SEROLOGY` 9 133 → 10 702 (+1 569, +17,2 %) <br>• MMR: `Auth_SEROLOGY` 28 844 → 29 883 (+1 039, +3,6 %), `NotAuth_SEROLOGY` 11 739 → 12 044 (+305, +2,6 %), `NotAuth_PCR` +3 <br>• ROTA: `Auth_PCR` 1 831 → 2 580 (+749, +40,9 %), `NotAuth_PCR` 380 → 387 (+7) <br>• Uendret: `*_NGS_SEQ` i alle faggrupper (prøvene med `EV_WGS` / `HBV_WGS` hadde allerede en NGS-kode), og PCR i INFLUENSA (kjøringen hadde `BVYPCR`, som ikke finnes, og ikke `INFBVY`) <br>• **`INFBVY`** (målt i testkjøringen av #40, mot 2.1 dagen før, bare prøver som finnes i begge): 9 388 INFLUENSA-prøver får `Auth_PCR` (60 222 → 69 610 etter filtrene, +15,6 %), og 2 158 som allerede hadde PCR, får en batch-ID til. `INFBVY` er borte fra F3 <br>• F2 byte-identisk. Prøvekolonnene i F1 byte-identiske |
| **Krever PBI-endring** | Nei. Tallene i dashboardet endres |
| **Bakoverkompatibel** | Ja |
| **Avklart** | `BVYPCR` finnes ikke som analysekode. Navnet som ble meldt var trolig visningsnavnet for B Victoria/Yamagata-PCR, som har kodene `INFBVY` (eldre) og `INFBVYPCR` (nåværende). `INFBVY` brukes også utenfor dashboardets faggrupper (`RG01`), som ikke endres |

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

Nytt steg `S14`. `VIRUS_POWERBI_unclassified_codes.tsv`: én rad per faggruppe × analysekode på virusprøver, med `n_tests`, `n_samples` og `last_change`. `CHANGED_ON` hentes fra `TEST_VIEW` til dette (`S05`).

| | |
|---|---|
| **Saker** | #23 |
| **Steg / regler / filer** | `S05`, `S14` (nytt). `RG09`, `RG12`. F3 (ny) |
| **Faggrupper** | Alle |
| **Forventet effekt** | Ingen på F1 og F2. F3 er ny, og har ikke kodene fra `E2.1-04` og `E2.1-12` |
| **Målt effekt** | Testkjøring 2026-10-15: 234 koder. HEP_HIV 154, INFLUENSA 34, POL_ENT 23, MMR 18, ROTA 4, HPV 1, VIRUS_CMN 0. Ingen rader uten faggruppe. Ingen av kodene fra `E2.1-04` og `E2.1-12` er med. De 15 `HCRES_NS*`-kodene er med (`RG12`). |
| **Krever PBI-endring** | Nei (filen er til vedlikehold, ikke til dashboardet) |
| **Merk** | F3 filtrerer selv til virusprøvene, fordi `test` ennå ikke er filtrert i databasen (#22). Ellers ufiltrert og for all tid. Ikke en feilliste: mange koder er utenfor scope med vilje. `last_change` gir NA (ikke `-Inf`) når en gruppe bare har tomme datoer, med samme type i alle grupper |

### E2.1-08 Utfil-dokumentasjonen: godkjenningsmerknad

Merknaden om godkjenning sier at R/X- og IU-tester er fjernet fra begge filene.

| | |
|---|---|
| **Saker** | #20, #21 |
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

### E2.1-12 Ny kategori SEQ_TYPING: Sanger-sekvensering, genotyping og resistens

Ny kodeliste `seq_typing_codes` i `S06`: genotyping (`HAGEN1`, `HCGEN`, `HCGENA`, `HCGR3`, `HEVGEN`), Sanger og annen sekvensering (`SC2_VAR_SANG`, `ENTERO_SEKVENS`, `NORO_SEKVENS`, `NOROSEK`, `ROTAVIRUS_SEKV`, `N_HCSEK`, `N_HIRSEK`, `N_HIDSEK`, `INF_PYRO`) og resistens (`HBRES`, `HCRES`). Nye bøtter `Auth_SEQ_TYPING` / `NotAuth_SEQ_TYPING` i `S07`, og `analysis_category = "Seq_typing"` i `S11`. `HCRES_NS*` er bevisst utelatt (`RG12`).

| | |
|---|---|
| **Saker** | #37 |
| **Steg / regler / filer** | `S06`, `S07`, `S11`. `RG12`. F1, F2, F3 |
| **Faggrupper** | Mest HEP_HIV (`HCGR3`, `HCGEN`, `N_HCSEK`, `HBRES`), deretter VIRUS_CMN / INFLUENSA (`SC2_VAR_SANG`), POL_ENT (`ENTERO_SEKVENS`) og hepatitt A/E (`HAGEN1`, `HEVGEN`) |
| **Forventet effekt** | To nye kolonner i F1, `Auth_SEQ_TYPING` og `NotAuth_SEQ_TYPING`. Kodene forsvinner fra F3. F2 uendret: `Seq_typing` dukker bare opp hvis whitelisten får par for disse kodene |
| **Målt effekt** | Testkjøring 2026-10-15, 2.0-dev mot `vd/23-analysekoder`, samme data (0 prøver bare i én kjøring). Antall prøver med noe i kolonnen, etter dashboardets default-filtre (`RG02`–`RG04`). F1: 944 719 rader i begge. <br>• `Auth_SEQ_TYPING`: INFLUENSA 6 718, HEP_HIV 2 030, POL_ENT 1 069, ROTA 40. Totalt 9 857 (10 104 uten filtre) <br>• `NotAuth_SEQ_TYPING`: INFLUENSA 1 058, HEP_HIV 212, POL_ENT 50. Totalt 1 320 (1 324 uten filtre) <br>• Begge kolonnene finnes i F1. F2 uendret, som forventet |
| **Krever PBI-endring** | **Ja** (#44). Ta inn de to nye kolonnene. Sjekk at Power Query-kilden ikke har et fast antall kolonner (`Columns=` i `Csv.Document`), ellers forsvinner de uten feilmelding |
| **Bakoverkompatibel** | Ja, hvis rapporten bruker kolonnenavn og ikke posisjon |
| **Åpent** | `HCGR3` antas å være HCV-genotyping. `N_HCSEK`, `N_HIRSEK`, `N_HIDSEK` avhenger av hva `N_`-prefikset betyr (#38) |

### E2.1-13 Utfil-dokumentasjonen: F3 og SEQ_TYPING

Versjon satt til 2.1-dev. F3 i fillisten og ny seksjon "Fil 3". `Auth_SEQ_TYPING` / `NotAuth_SEQ_TYPING` i kolonnetabellen for F1 og i tabellen for analyserte prøver. `Seq_typing` blant verdiene for `analysis_category`.

| | |
|---|---|
| **Saker** | #23, #37 |
| **Steg / regler / filer** | Dokumentasjon. F1, F2, F3 |
| **Krever PBI-endring** | Nei (men beskriver kolonnene PBI må ta inn, se `E2.1-12`) |

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
