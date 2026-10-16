# Dokumentasjon for LIMS-uttrekksfiler til Virus Dashboard

Generert av `virus_dashboard.R` (v2.1-dev).  
Skriptet produserer **to filer** som begge lastes inn i Power BI, og en tredje fil til vedlikehold av analysekodelistene:

| Fil | Format | Granularitet |
|---|---|---|
| `VIRUS_POWERBI_lw_uttrekk.tsv` | Tab-separert, én rad per prøve (wide) | Prøvenivå |
| `VIRUS_POWERBI_results.tsv` | Tab-separert, én rad per resultat (long) | Resultatnivå |
| `VIRUS_POWERBI_unclassified_codes.tsv` | Tab-separert, én rad per faggruppe og analysekode | Aggregert (kun tellinger). Ikke til Dashboardet |
| `VIRUS_POWERBI_sample_codes.tsv` | Tab-separert, én rad per prøve og analysekode | Kobling mellom prøver og analysekoder, siste fem år |
| `VIRUS_POWERBI_excluded_codes.tsv` | Tab-separert, én rad per analysekode | Liste over koder som bevisst ikke telles. Ikke koblet til prøver |

Filene kobles i Power BI via `SAMPLE_NUMBER` (mange-til-én fra resultatfilen til prøvefilen).

---

Kun prøver som tilhører følgende faggrupper (`GROUP_NAME`) er inkludert:

| GROUP_NAME | 
|---|
| `HEP_HIV` | 
| `HPV` | 
| `INFLUENSA` | 
| `MMR` | 
| `POL_ENT` | 
| `ROTA` | 
| `VIRUS_CMN` | 

---

## Fil 1: `VIRUS_POWERBI_lw_uttrekk.tsv`

Én rad per prøve. Brukes til telling, tidsserier og filtrering på faggruppe og analysestatus.

### Kolonner hentet direkte fra LIMS
| Kolonne | Beskrivelse |
|---|---|
| `ORIGINAL_SAMPLE` | Hvis dette nummeret er identisk med `SAMPLE_NUMBER`, regnes prøven **ikke** som en barneprøve. |
| `PARENT_SAMPLE` | Inneholder alltid nummeret "0". Ikke informativt for Dashboardet. |
| `TEMPLATE` | Hvis det står "STORAGE" her er dette en såkalt Fryseprøve. |
| `SAMPLE_NUMBER` | Det som vi ofte kaller "LIMS-nummer". Primærnøkkel. Kobling til resultatfilen. |
| `TEXT_ID` |  |
| `GROUP_NAME` | Faggruppe |
| `SAMPLED_DATE` | Prøvetakningsdato |
| `RECD_DATE` | Mottaksdato |
| `X_MEDICAL_REVIEW` | Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Canceled. N = Not reviewed. R = Rejected. NA = Missing information |
| `SAMPLE.STATUS` | Fra prøvetabellen (omdøpt fra `STATUS`). Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Cancelled. R = Rejected. C = Complete. P = In-progress. I = Incomplete. U = Unreceived |
| `X_AGENS` | Agens fra prøvetabellen. Skrevet inn ved prøvemottak. |
| `PATIENT` | Unik ID for pasient. Identisk nummer betyr samme pasient. |

### Kolonner avledet fra LIMS

Alle `Auth_*`- og `NotAuth_*`-kolonner inneholder kommaseparerte batch-IDer dersom prøven har en eller flere tester av den aktuelle typen. En test uten batch-ID står som `UTEN_BATCH`. Tom streng (`""`) betyr at prøven ikke har noen slik test registrert. Fra 2.1-dev står det aldri `NA` i disse kolonnene (#48), så regelen er: ikke tom = har test.

> **Merk om godkjenning:** `X_TECH_REVIEW == "A"` betyr at analysen er teknisk godkjent i LIMS. Analyser som er ventende, avvist eller ikke vurdert vises i `NotAuth_*`-kolonnene.

| Kolonne | Betingelse | Beskrivelse |
|---|---|---|
| `child_sample` | `if_else(ORIGINAL_SAMPLE == SAMPLE_NUMBER, "NO", "YES")` | Angir om prøven er en barneprøve. |
| `Auth_NGS_PREP` | `ANALYSIS == "NGS_PREP"` og `X_TECH_REVIEW == "A"` | Godkjent biblioteksprep-batch. |
| `NotAuth_NGS_PREP` | `ANALYSIS == "NGS_PREP"` og `X_TECH_REVIEW != "A"` | Ikke-godkjent biblioteksprep-batch. |
| `Auth_NGS_SEQ` | `ANALYSIS` i NGS/WGS-kodene og `X_TECH_REVIEW == "A"` | Godkjent sekvenseringskjøring. Dekker NGS, SC2_NGS, MPX_WGS, INF_WGS, RSV_WGS, HPV_WGS m.fl. |
| `NotAuth_NGS_SEQ` | `ANALYSIS` i NGS/WGS-kodene og `X_TECH_REVIEW != "A"` | Ikke-godkjent sekvenseringskjøring. |
| `Auth_EXTRACTION` | Ekstraksjonsanalyse og `X_TECH_REVIEW == "A"` | Godkjent ekstraksjon. Dekker EKSTR, EXT, EXTPRI, PROVEPREP m.fl. |
| `NotAuth_EXTRACTION` | Ekstraksjonsanalyse og `X_TECH_REVIEW != "A"` | Ikke-godkjent ekstraksjon. |
| `Auth_CULTURE` | Dyrkingsanalyse og `X_TECH_REVIEW == "A"` | Godkjent dyrking. Dekker DYRKING, VDYRKE, VDYRKA, BGM, L20B, A549, RD m.fl. |
| `NotAuth_CULTURE` | Dyrkingsanalyse og `X_TECH_REVIEW != "A"` | Ikke-godkjent dyrking. |
| `Auth_PCR` | PCR-analyse og `X_TECH_REVIEW == "A"` | Godkjent PCR. Dekker influensa-, RSV-, arbovirus-, entero-, HEP/HIV-, MMR-, HPV-PCR m.fl. |
| `NotAuth_PCR` | PCR-analyse og `X_TECH_REVIEW != "A"` | Ikke-godkjent PCR. |
| `Auth_SEROLOGY` | Serologianalyse og `X_TECH_REVIEW == "A"` | Godkjent serologi. Dekker EIA, IgG/IgM, HI-test, Western blot m.fl. på tvers av alle faggrupper. |
| `NotAuth_SEROLOGY` | Serologianalyse og `X_TECH_REVIEW != "A"` | Ikke-godkjent serologi. |
| `Auth_SEQ_TYPING` | Sanger-/genotyping-/resistensanalyse og `X_TECH_REVIEW == "A"` | Godkjent sekvensering som ikke er NGS. Dekker HAGEN1, HCGEN, HEVGEN, SC2_VAR_SANG, ENTERO_SEKVENS, NORO_SEKVENS, HBRES, HCRES m.fl. |
| `NotAuth_SEQ_TYPING` | Sanger-/genotyping-/resistensanalyse og `X_TECH_REVIEW != "A"` | Ikke-godkjent sekvensering som ikke er NGS. |

---

## Fil 2: `VIRUS_POWERBI_results.tsv`

Én rad per resultatverdi per prøve. Brukes til å vise faktiske analyseresultater — Ct-verdier, titere, konklusjoner, genotyper og QC-metrikker.

Kun et utvalg av `(ANALYSIS, NAME)`-par med diagnostisk verdi er inkludert. Rene administrasjons- og arbeidsflytfelt (Autohandling, MSISLABDB, Rådatafil, Utført av osv.) er ekskludert.

### Kolonner

| Kolonne | Beskrivelse |
|---|---|
| `SAMPLE_NUMBER` | LIMS-nummer. Kobling til Fil 1. |
| `TEST_NUMBER` | LIMS test-ID. |
| `ANALYSIS` | Analysekode (f.eks. `INFA_TRICDC`, `MOGENZ`, `NGS`). |
| `analysis_category` | Overordnet kategori for analysen. Verdier: `PCR`, `Serology`, `NGS_SEQ`, `NGS_PREP`, `Extraction`, `Culture`, `Seq_typing`. Brukes til hierarkisk filtrering i Power BI. |
| `NAME` | Navn på resultatparameter (f.eks. `Resultat`, `ct. INFA`, `Titer`, `Clade`). |
| `value` | Resultaverdi. Tekst eller tall avhengig av analyse. |
| `ENTERED_ON` | Tidspunkt da resultatet ble registrert. |
| `CHANGED_ON` | Tidspunkt da resultatet sist ble endret. |

### Inkluderte analyse- og resultattyper

| Kategori | Analyser | Eksempler på NAME |
|---|---|---|
| PCR influensa | `INFABPCR`, `INFA_TRICDC`, `INFB_TRICDC`, `SC2_TRICDC`, `INFSC2`, `IAH3C1`, `IASRH1` | `Resultat`, `ct. INFA`, `ct. H3`, `H1pdm09` |
| PCR RSV | `RSVA_PCR`, `RSVB_PCR`, `RSVABPCR` | `Resultat`, `ct. RSVA`, `ct. RSVB` |
| PCR arbovirus | `DENGIF`, `CHIGIF` | `Resultat DENV-1/2/3/4`, `Konklusjon`, `Resultat` |
| Serologi MMR/B19 | `MOGENZ`, `MOGMIC`, `PAMSER`, `PAMMIC`, `MOMENZ`, `RUGENZ`, `RUGSER`, `B19GSER`, `B19MSER` | `Konklusjon`, `Result_num`, `Titer`, `S / Positiv CO %` |
| Serologi HEP_HIV | `HIAGB`, `HAIFV`, `HCVB` | `Konklusjon`, `Result_num`, `S/CO prosent`, `Resultat_num` |
| NGS/WGS typing og QC | `NGS`, `NGS_PREP`, `SC2_NGS`, `INF_WGS`, `RSV_WGS`, `MPX_WGS` | `Genotype fra skript`, `Clade`, `Dekning % av genomet`, `Gj. snittlig dybde`, `NGS-status`, `Genetisk variant` |
| Dyrking | `VDYRKE`, `VDYRKA` | `Konklusjon`, `Funn`, `eMSIS status` |

---

## Fil 3: `VIRUS_POWERBI_unclassified_codes.tsv`

Vedlikeholdsfil, ikke til Dashboardet. Viser alle analysekoder brukt på virusprøver (de sju faggruppene over) som **ikke** ligger i noen av kategorilistene i `virus_dashboard.R`. Disse testene kommer ikke med i `Auth_*`/`NotAuth_*`-kolonnene, og er dermed usynlige i Dashboardet.

| Kolonne | Beskrivelse |
|---|---|
| `GROUP_NAME` | Faggruppe til **prøven** (ikke testen). |
| `ANALYSIS` | Analysekode. |
| `n_tests` | Antall tester (inkl. replikater og gjentak). |
| `n_samples` | Antall unike prøver. |
| `last_change` | Siste `CHANGED_ON` for koden. Skiller koder i bruk fra utgåtte koder. Tom hvis ingen av testene har dato. |

Merk:

- Lista er **ikke** en feilliste. Mange koder er administrative og skal bevisst ikke klassifiseres. Faggruppen avgjør per kode om den skal inn i en liste eller ignoreres.
- Fila er **ufiltrert** innenfor virusprøvene: den inkluderer barneprøver, fryseprøver, kansellerte prøver og tester med R/X eller "Ikke utført", slik at ingen koder blir oversett. Tallene er derfor høyere enn i Dashboardet.
- Den viser bare koder som mangler i listene, ikke koder som står i listene men aldri brukes (eller er feilstavet).
- Koder som bevisst ikke telles (Fil 5), er ikke med.

---

## Fil 4: `VIRUS_POWERBI_sample_codes.tsv`

Kobling mellom prøver og analysekoder. Gjør det mulig å gå fra en analysekode til prøvene som har den, og fra en prøve til alle analysekodene den har.

| Kolonne | Beskrivelse |
|---|---|
| `SAMPLE_NUMBER` | LIMS-nummer. Kobling til Fil 1. |
| `ANALYSIS` | Analysekode. |
| `analysis_category` | Samme verdier som i Fil 2 (`PCR`, `Serology`, `NGS_SEQ`, `NGS_PREP`, `Extraction`, `Culture`, `Seq_typing`), eller `Ukategorisert` for koder som ikke står i noen kategoriliste. |
| `n_tests` | Antall tester av koden på prøven. |
| `n_auth` | Hvor mange av dem som er teknisk godkjent (`X_TECH_REVIEW == "A"`). |

Merk:

- Bare prøver mottatt de siste fem årene (rullerende, etter `RECD_DATE`). Prøver uten mottaksdato er ikke med.
- Koder i Fil 5 er ikke med.
- Fila har ingen pasient-ID og ingen resultater. Resultater for en prøve hentes fra Fil 2 (tillatt fra #53). `PATIENT` fra Fil 1 skal ikke vises i visninger av enkeltprøver.
- Tester med `X_TECH_REVIEW` R eller X, og tester med resultat "Ikke utført", er foreløpig med i `n_tests`, som i Fil 1.

### Oppsett i Power BI

- Relasjon fra `VIRUS_POWERBI_lw_uttrekk` (1) til `VIRUS_POWERBI_sample_codes` (\*) på `SAMPLE_NUMBER`.
- Fra analysekode til prøver: et utsnitt på `ANALYSIS` i Fil 4. Relasjonen må da filtrere begge veier, eller et measure må håndtere det.
- Fra prøve til analysekoder: velg en prøve, og vis en tabell med `ANALYSIS`, `analysis_category`, `n_tests` og `n_auth`.
- Eksport av data fra dashboardet skal være blokkert.

---

## Fil 5: `VIRUS_POWERBI_excluded_codes.tsv`

Liste over analysekoder som bevisst ikke telles, for eksempel administrative koder og utgåtte koder. Lista er hardkodet i `virus_dashboard.R` og skrives ut hver natt, så fila alltid viser det skriptet faktisk gjør. Den er ikke koblet til prøver, og kan lastes i Power BI som en egen referansetabell.

| Kolonne | Beskrivelse |
|---|---|
| `ANALYSIS` | Analysekode. |
| `reason` | Hvorfor koden ikke telles: `Administrativ` eller `Ikke i bruk`. Uten æøå, så verdiene ser like ut uansett hvordan fila leses. |
| `rule` | Regelen som gjelder (`RG13`). |

Merk:

- Kodene i Fil 5 står ikke i noen kategori, telles ikke i `Auth_*`/`NotAuth_*`, og er ikke med i Fil 3.
- Hver analysekode står ett sted: i en kategori (telles), i Fil 5 (bevisst utelatt), eller i Fil 3 (ikke avklart ennå).

---

## Anbefalte default-filtre til Dashboard

### 1. Ekskluder barneprøver (duplikater)

`child_sample == "NO"`

Barneprøver er avledede prøver opprettet i LIMS (f.eks. alikvot, ekstraksjonsrør). Ved å beholde kun `child_sample == "NO"` telles hver reelle pasientprøve bare én gang.

### 2. Ekskluder kansellerte og avviste prøver

Prøver som har `X` (Cancelled) eller `R` (Rejected) i `SAMPLE.STATUS` finnes ikke i LIMS (kan være feilregistrering). Bør ikke vises med mindre man spesifikt ønsker dette. **NB:** `C` betyr *Complete* og skal **ikke** ekskluderes.

### 2b. Ekskluder fryseprøver

`TEMPLATE != "STORAGE"`

Fryseprøver er ekstrakter som får eget LIMS-nummer (f.eks. de fleste influensaprøver). Tas de med, ser det ut som det har kommet inn omtrent dobbelt så mange prøver.

### 3. Telle mottatte prøver

Alle rader som passerer filter 1, 2 og 2b ovenfor regnes som mottatte prøver. Dato-feltet `RECD_DATE` brukes for tidsserie/tidsfiltrering.

### 4. Telle analyserte prøver

Bruk `Auth_*`-kolonnene som ja/nei-indikator: en prøve regnes som analysert dersom kolonnen **ikke** er tom.

| Ønsket telling | Kolonne |
|---|---|
| Sekvensert | `Auth_NGS_SEQ` ikke tom |
| Biblioteksprep utført | `Auth_NGS_PREP` ikke tom |
| PCR utført | `Auth_PCR` ikke tom |
| Serologi utført | `Auth_SEROLOGY` ikke tom |
| Dyrking utført | `Auth_CULTURE` ikke tom |
| Ekstraksjon utført | `Auth_EXTRACTION` ikke tom |
| Sanger-sekvensert / genotypet / resistenstestet | `Auth_SEQ_TYPING` ikke tom |

---

## Oppsett i Power BI

### Koble filene

1. Last inn begge filer som separate tabeller i Power BI Desktop (hjem → Hent data → Tekst/CSV).
2. Gå til **Modellvisning**.
3. Dra `SAMPLE_NUMBER` fra `VIRUS_POWERBI_lw_uttrekk` til `SAMPLE_NUMBER` i `VIRUS_POWERBI_results`.
4. I relasjons-dialogen som åpnes: sett **Kardinalitet** til **En til mange (1:\*)** — der `VIRUS_POWERBI_lw_uttrekk` er «Fra tabell» (1-siden) og `VIRUS_POWERBI_results` er «Til tabell» (\*-siden). Velg **ikke** «Mange til en (\*:1)», da dette gir feilmelding om duplikate verdier i resultatfilen.

### Anbefalte measures og visninger

**Telle positive PCR (eksempel influensa A triplex):**
```
Positive InfA triplex =
CALCULATE(
    COUNTROWS('VIRUS_POWERBI_results'),
    'VIRUS_POWERBI_results'[ANALYSIS] = "INFA_TRICDC",
    'VIRUS_POWERBI_results'[NAME] = "Resultat",
    'VIRUS_POWERBI_results'[value] = "Positiv"
)
```

**Ct-verdi distribusjon:** Lag et punktdiagram med `value` (filtrert på `NAME = "ct. INFA"`) på Y-aksen og `RECD_DATE` fra prøvefilen på X-aksen.

**Serologititer over tid:** Bruk `Result_num` fra `MOGENZ` eller `RUGENZ` som Y-akse og `SAMPLED_DATE` fra prøvefilen som X-akse. Filtrer på `NAME = "Titer"` eller `NAME = "Result_num"`.

**Andel sekvensert per faggruppe:** Lag et stablet stolpediagram med `GROUP_NAME` (fra prøvefilen) på X-aksen og to measures: én som teller prøver med `Auth_NGS_SEQ` ikke tom, og én som teller totalt mottatte prøver.

**Genotype-fordeling:** Filtrer resultatfilen på `ANALYSIS = "NGS"` og `NAME = "Genotype fra skript"`. Bruk `value` i et sektordiagram eller matrisvisualisering.

### Tips

- Filtrer alltid resultatfilen på `ANALYSIS` og `NAME` samtidig — en prøve kan ha resultater fra mange ulike analyser.
- For tidsserie på resultater, bruk `ENTERED_ON` eller `CHANGED_ON` fra resultatfilen, eller koble til `RECD_DATE`/`SAMPLED_DATE` fra prøvefilen via relasjonen.
- `NotAuth_*`-kolonnene i prøvefilen kan brukes til å identifisere prøver som er påbegynt men ikke ferdig godkjent — nyttig for å følge opp prøver som "henger".

