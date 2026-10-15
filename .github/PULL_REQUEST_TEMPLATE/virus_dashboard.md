<!--
Virus Dashboard-mal. Brukes med ?template=virus_dashboard.md i PR-lenken.
Repoet er offentlig: bare aggregerte tall.
-->

## Endring

**Endringer:** `E<versjon>-##` (se `lims_uttrekk/virus_dashboard/CHANGELOG.md`)
**Saker:** closes #
**Steg / regler / filer:** `S##` / `RG##` / `F#`
**Faggrupper:** Alle / …

Kort beskrivelse av hva som er endret, og hvorfor.

## Konsekvens

**Forventet effekt:**

**Målt effekt** (lim inn tabellen fra `virus_dashboard_compare.R`):

**Krever endring i Power BI:** nei / ja: …

## Sjekkliste

- [ ] `CHANGELOG.md`: `E`-oppføring med konsekvensvurdering og målt effekt
- [ ] `STEPS.md` / `RULES.md` oppdatert hvis steg eller regler er endret, og nye steg har en `[S##]`-kommentar i koden
- [ ] `VIRUS_POWERBI_output_columns.md` oppdatert hvis kolonner er endret
- [ ] `ISSUES.md` oppdatert (status)
- [ ] Kjørt i Test-miljøet med samme R-versjon som serveren
- [ ] `virus_dashboard_compare.R` kjørt mot forrige versjon, og `Prøver bare i før/etter` er 0
- [ ] Egen sak for Power BI-siden hvis det trengs
- [ ] Versjon i skripthodet oppdatert
