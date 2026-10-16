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
| `RG08` | Dashboardet viser tellinger, og enkeltprøver med prøvenummer og analysekoder | Vedtatt (endret i #41) | `P03`, `S16` / F4 og `P04` (2.2-dev, #42), eksport (#43) | Møte 2026-02-24, #41 |
| `RG09` | Bare analysekoder i kodelistene telles | Implementert 2.0. **Midlertidig**. F3 viser det som mangler fra 2.1-dev | `S06`, `S14` | Designvalg 2.0 |
| `RG10` | F2 har bare whitelistede resultatfelt | Implementert 2.0 | `S09`, `S10` | Designvalg 2.0 (#11) |
| `RG11` | Avviste tester i dashboardet? | **Åpen** | — | Møte 2026-03-20 |
| `RG12` | Delresultat-koder telles ikke som egne analyser | Foreslått i 2.1-dev (#37). Må bekreftes av faggruppen | `S06` | Gjennomgang av F3, 2026-10-15 |
| `RG13` | Administrative og utgåtte koder telles ikke, og listes i F5 | Implementert 2.2-dev (#40) | `S15`, `S14` | #40 |

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

## RG08 Hva dashboardet viser

Dashboardet viser aggregerte tall. I tillegg kan det vise **enkeltprøver med LIMS-prøvenummer og analysekoder**, for eksempel fra en analysekode til prøvene som har den, og fra en prøve til alle kodene den har (#42).

- **Aldri resultater for enkeltprøver.** F2 inneholder resultatverdier for å kunne telle (f.eks. positive), men de skal ikke vises enkeltvis.
- **`PATIENT` vises ikke** i visninger av enkeltprøver.
- **Alle faggrupper** er med.
- **De siste fem årene:** visninger av enkeltprøver dekker en rullerende periode på fem år, etter mottaksdato (`RECD_DATE`).
- **Eksport av underliggende data fra dashboardet er blokkert** (#43).

**Hvorfor:** dashboardet har allerede begrenset tilgang, og vedlikehold av kodelistene og oppfølging av prøver trenger å se hvilke prøver som har hvilke koder.

**Kan endres:** om noe må tas ut av visningen (f.eks. enkelte koder eller faggrupper), avgjøres senere.

**Kilde:** opprinnelig regel fra møte 2026-02-24 (bare tellinger), endret i #41.

## RG09 Bare analysekoder i kodelistene telles

En test kommer bare med i F1 og får bare `analysis_category` i F2 hvis koden står i en av listene i `S06`.

**Konsekvens:** nye eller manglende koder blir usynlige (f.eks. `INFBVY`, den eldre koden for samme analyse som `INFBVYPCR`; #23). Når en analyse får ny kode, må den gamle koden stå i listen så lenge historiske tall skal vises. F3 (`S14`, `E2.1-07`) viser hvilke koder som mangler, og må sjekkes når faggruppene tar i bruk nye analyser.

**Slik legges en kode inn:** bare når tilhørigheten er klar (variant eller søsken av en kode som står i en liste, eller et navn som sier hva det er). Ellers samles den i en avklaringssak (som #38) til faggruppen eller LIMS-forvaltningen har svart. Er koden administrativ eller utgått, legges den i utelatelseslista i stedet (`RG13`). En kode skal bare stå ett sted.

**Midlertidig:** bør erstattes av ANALYSIS-mastertabellen (`#26`).

## RG10 F2 har bare whitelistede resultatfelt

Bare `(ANALYSIS, NAME)`-par i `S09` kommer med i F2. Administrasjons- og arbeidsflytfelt (Autohandling, MSISLABDB, Rådatafil, Utført av osv.) er utelatt.

**Konsekvens:** nye resultattyper må legges til i whitelisten for å komme med.

## RG11 Avviste tester i dashboardet? (åpen)

Møtet 2026-03-20 nevnte at avviste tester (R) kanskje er relevante å vise. 2.1-dev fjerner dem (`RG06`).

**Hvis de skal vises:** ta `"R"` ut av `excluded_tests` (`S13`) og legg til `Rej_*`-bøtter i `S07`. Det gir nye kolonner i F1 og krever PBI-endring.

## RG12 Delresultat-koder telles ikke som egne analyser

Analysekoder som er delresultater av én analyse, legges ikke i noen kodeliste. Eksempel: de 15 `HCRES_NS*`-kodene, én per legemiddel, som alle hører til HCV-resistensanalysen (`HCRES`, som står i `seq_typing_codes`).

**Hvorfor:** i et ja/nei-flagg per prøve gjør de ingen skade, men enhver telling av tester blir omtrent 15 ganger for høy.

**Konsekvens:** kodene blir stående i F3 som uklassifiserte, med vilje. Kommer en ny analyse med delresultat-koder, må den vurderes på samme måte.

**Status:** foreslått i 2.1-dev (#37). Må bekreftes av faggruppen.

## RG13 Administrative og utgåtte koder telles ikke

Analysekoder som ikke er analyser (administrative koder, arbeidsflyt, kommentarfelt) eller som er utgått, legges i den hardkodede lista `excluded_codes` (`S15`). De telles ikke, tas ikke med i F3, og skrives til F5 med begrunnelse.

**Hvorfor:** uten en slik liste blir disse kodene liggende i F3 for alltid, og det finnes ingen oversikt over hva som bevisst er utelatt.

**Slik legges en kode inn:** bare eksakte koder, ingen mønstre, så ingen analyse utelates ved et uhell. En kode legges bare inn når det er avklart at den ikke er en analyse, eller at den er utgått (se #38).

**Konsekvens:** F3 blir mindre, og viser bare koder som ikke er avklart. Kodene er heller ikke med i F4 (#42). F1 og F2 endres ikke.

**Ikke med:** delresultat-koder som `HCRES_NS*` står i F3 etter `RG12`, ikke i lista. Koder som kan trengs til andre saker (`MOTTAK`, `AGENS`, `N_IKKEUS`), og `N_`-kodene som venter på svar i #38, er heller ikke med.

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
