# Dokumentasjon for LabWare-uttrekksfil: `VIRUS_POWERBI_lw_uttrekk.tsv`

Generert av `virus_dashboard.R` (v1.2).  
Filen er en tabseparert tabell der hver rad representerer én prøve fra LabWare.


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


## Beskrivelse av kolonner i uttrekksfilen

### Kolonner hentet direkte fra LabWare
| Kolonne | Beskrivelse |
|---|---|
| `ORIGINAL_SAMPLE` | Hvis dette nummeret er identisk med `SAMPLE_NUMBER`, regnes prøven **ikke** som en barneprøve. |
| `PARENT_SAMPLE` | Inneholder alltid nummeret "0". Ikke informativt for Dashboardet. |
| `TEMPLATE` | Hvis det står "STORAGE" her er dette en såkalt Fryseprøve. |
| `SAMPLE_NUMBER` | Det som vi ofte kaller "LabWare-nummer". Brukes som primærnøkkel gjennom hele skriptet. |
| `TEXT_ID` |  |
| `GROUP_NAME` | Faggruppe |
| `SAMPLED_DATE` | Prøvetakningsdato |
| `RECD_DATE` | Mottaksdato |
| `X_MEDICAL_REVIEW` | Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Canceled. N = Not reviewed. R = Rejected. NA = Missing information |
| `SAMPLE.STATUS` | Fra prøvetabellen (omdøpt fra `STATUS`). Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Cancelled. R = Rejected. C = Complete. P = In-progress. I = Incomplete. U = Unreceived |
| `X_AGENS` | Agens fra prøvetabellen. Skrevet inn ved prøvemottak. |
| `PATIENT` | Unik ID for pasient. Identisk nummer betyr samme pasient. |

### Kolonner avledet fra LabWare

| Kolonne | Betingelse | Beskrivelse |
|---|---|---|
| `child_sample`| `if_else(ORIGINAL_SAMPLE == SAMPLE_NUMBER, "NO", "YES")`| Angir om prøven er en barneprøve. Settes til `YES` dersom `ORIGINAL_SAMPLE` er forskjellig fra `SAMPLE_NUMBER`, det vil si at dette ikke er toppnivåprøven. |
| `Auth_NGS_PREP` | `ANALYSIS == "NGS_PREP"` **og** `X_TECH_REVIEW == "A"` | Inneholder batch-ID for biblioteksprep-batch (`NGS_PREP`) som er teknisk godkjent (`A`). |
| `NotAuth_NGS_PREP` | `ANALYSIS == "NGS_PREP"` **og** `X_TECH_REVIEW != "A"` | Inneholder batch-ID for biblioteksprep-batch som **ikke** er teknisk godkjent. |
| `Auth_NGS_SEQ` | `ANALYSIS` er `NGS`, `SC2_NGS` eller `MPX_WGS` **og** `X_TECH_REVIEW == "A"` | Inneholder batch-ID for BGS-batch (sekvensering) som er teknisk godkjent (`A`).  |
| `NotAuth_NGS_SEQ` | `ANALYSIS` er `NGS`, `SC2_NGS` eller `MPX_WGS` **og** `X_TECH_REVIEW != "A"` | Inneholder batch-ID for BGS-batch (sekvensering) som **ikke** er teknisk godkjent (`A`). |

> **Merk om godkjenning:** `X_TECH_REVIEW == "A"` betyr at analysen er godkjent i det tekniske gjennomgangssteget i LabWare. Analyser som fortsatt er ventende, avvist eller ikke ennå vurdert vil vises i `NotAuth_*`-kolonnene.



## Anbefalte default-filtre til Dashboard

### 1. Ekskluder barnprøver (duplikater)

`child_sample == "NO"`

Barnprøver er avledede prøver opprettet i LabWare (f.eks. alikvot, ekstraksjonsrør). Ved å beholde kun `child_sample == "NO"` telles hver reelle pasientprøve bare én gang.

### 2. Ekskluder kansellerte prøver

Prøver som har enten `C` eller `X` i `SAMPLE.STATUS` finnes ikke i LabWare (kan være feilregistrering). Bør ikke vises med mindre man spesifikt ønsker dette. 

### 3. Telle mottatte prøver

Alle rader som passerer filter 1 og 2 ovenfor regnes som mottatte prøver. Dato-feltet `RECD_DATE` brukes for tidsserie/tidsfiltrering.

### 4. Telle sekvenserte prøver

En prøve kan regnes som sekvensert dersom den har minst ett godkjent sekvenseringsbatch, det vil si at det **ikke** står `NA` (kan vises som tom av noen programmer) i kolonnen `Auth_NGS_SEQ`. 

Kun teknisk godkjente kjøringer (`X_TECH_REVIEW == "A"`) telles. Prøver som kun finnes i `NotAuth_NGS_SEQ` er ikke ferdig godkjent og bør holdes utenfor.

