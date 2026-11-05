# SC2 GISAID exporter from master.csv

`sc2_gisaid_csv.R` is the R-only master-based exporter. It creates a submission
CSV, matching FASTA and audit manifest, without changing master/review files or
submitting to GISAID. The existing database-based `sc2_gisaid.R` remains a legacy
script; use this new entry point for the approval-filtered workflow.

Requires R and the `jsonlite` and `digest` R packages. Node.js and Python are
not required for this exporter. Install missing packages in the R console with
`install.packages(c("jsonlite", "digest"))`. Deploy the complete `ngs_scripts`
checkout. See the [approval rules and dataset layout](../shared/README.md).

The existing `sc2_gisaid_csv.py` remains available for existing callers and
requires Python 3.10+ and Node.js 18+. Both implementations apply the same
approval, selection and validation rules and produce compatible audit manifests.

## Run

Store the complete checkout at `N:/Virologi/NGS/tmp/ngs_scripts`. SC2 finds its
shared code relative to the script, independent of the current working directory.
The default master, lab and output locations below are already configured.

```powershell
Rscript "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/sars-cov-2/sc2_gisaid_csv.R" RUNID GISAID_USERNAME
```

In RStudio, set the same arguments before sourcing the full path:

```r
gisaid_args <- c("RUNID", "GISAID_USERNAME")
source("N:/Virologi/NGS/tmp/ngs_scripts/gisaid/sars-cov-2/sc2_gisaid_csv.R", encoding = "UTF-8")
```

Optional flags use the same order as on the command line. Source-relative lookup,
repository working directories, the standard N-drive checkout and an explicit
`GISAID_SHARED_DIR` are supported, as for influenza. R uses the shared
`approval.R` and `sars-cov-2/sc2_export.R` files; keep them with the entry script.

For mounted/custom paths and a new local output prefix:

```bash
Rscript gisaid/sars-cov-2/sc2_gisaid_csv.R RUNID GISAID_USERNAME \
  --master '/mounted/NGS analysis database/data/SC2/master.csv' \
  --lab-lookup '/mounted/Innsender_GISAID.csv' \
  --output-dir '/local/submission-review' --prefix 'SC2_RUNID' \
  --assembly-method 'Verified assembly method for this run'
```

The assembly method records the software used to generate the consensus sequence;
it does not run assembly. It defaults to `ARTIC 1.6.2`, matching the ARTIC version
declared by the current SC2 pipeline checkout. For historical runs or externally
assembled FASTAs, use `--assembly-method "Actual software and version"` to record
their original method. The Python alternative uses the same default and override.
The technology defaults to the legacy `Oxford Nanopore - GridION`; override
`--sequencing-technology` for other runs. `--authors` overrides the legacy author
list. Check these values against the run before preparing a submission.

Defaults:

- Master: `N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2/master.csv`.
- FASTA: `master.fasta` beside the master; `--fasta` selects another explicit archive.
- Lab lookup: `N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender_GISAID.csv`.
- Output: `N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon`.
- Prefix: `GISAID SUBMISSION - <week>-<year>`, matching the legacy naming scheme.
- Assembly method: `ARTIC 1.6.2`; override for historical or external assemblies.

Existing output files are never overwritten. Choose a new `--prefix` or directory
for a new export. The manifest is written last; use a submission only after a
successful exit with all three files present. Ordinary write failures remove
files created by that attempt. Abrupt termination can leave incomplete files;
use a new prefix after checking them. Publication of the three files is not atomic.

## Selection and metadata

The following requirements are cumulative:

1. A current, conflict-free `Approved` decision in the solution.
2. Exact `NGS_Run_ID` match, using current approved overrides where present.
3. Empty `GISAID_Kommentar`, preserving the existing comment exclusion.
4. Finite `NC_Coverage` in the fraction range 0.75–1 inclusive, preserving the
   legacy minimum of 75%; decimal-comma fractions are accepted. Missing/invalid
   values and percentages supplied as fractions are excluded.
5. Nonblank `Key`; blank keys are skipped and counted as in INF. Duplicate
   eligible keys fail rather than combining specimens.

No additional blanket `NGS_QC_Sum` exclusion is introduced for SC2. Existing
assessment and review remain distinct from these export requirements. An empty
eligible set fails without writing output. `NGS_QC_Assessment=Approved` in a CSV
does not replace a solution review event.

The legacy SC2 `covv_*` column order, host/passaging fields, date/location format,
sampling-strategy rules, author/submitting-lab defaults and name construction are
preserved. Isolate names use `hCoV-19/Norway/<Key without first four digits>/<year>`
for numeric keys with at least five digits; other keys retain the full key.
Leading zeroes remain text. Collection dates must be valid ISO dates, county
must be available and resulting virus names must be unique. Known county text
damage is repaired in the output using the same county replacements as master merges.
Gender accepts `Pasient_Kjnn` or `Pasient_Kjonn`. The CSV `fn` names the actual
output FASTA, replacing the old `tmp` placeholder.

The CSV lab lookup matches exact text codes from `Prove_Innsender_ID` to
`Innsender_nr`, preserving leading zeroes. It requires `Innsender_nr` and
`Innsender_navn`. Addresses can be supplied as `Innsender_adresse` or `Lab_address`;
conflicting address columns and duplicate lab codes fail. Missing matching lab
names fail. Missing addresses remain blank and are counted as
`missing_lab_address`; fill/check these before submission. No embedded hospital
address list is used as an implicit fallback.

## FASTA matching and audit

FASTA uses the first whitespace-delimited header token. Exact original master
aliases `NGS_LW_ID`, `OriginalName`, `SampleID`, `Key` and `Prove_LW_ID` are
supported; no substring, suffix-stripping or sequence-content matching is used.
Every eligible sample must match exactly one record. Duplicate records, multiple
matching aliases, missing records or an ID shared with another master sample
(even an unapproved one) fail. Supply an unambiguous archive when historical IDs
for the same specimen coexist. Unselected records are not exported.

The CSV virus name and FASTA header always agree. The manifest records selected
review IDs/fingerprints, original FASTA IDs, source checksums, output checksums,
and approval/filter counts. It contains sample identifiers and should stay with
the protected submission files. The exporter rechecks approval/master inputs,
FASTA and the lab lookup before writing. An exported snapshot does not reserve
approvals against future edits; regenerate after changes.

## Import returned accession IDs

`import_gisaid_accessions.py` updates only `GISAID_Isolate_ID` and
`GISAID_Isolate_Name` in the SC2 master. It needs Python only, without Node or R.
Use a mounted drive or UNC path; this standalone importer does not invoke
`smbclient`. The default master is the same SC2 N-drive path as the exporter.

```powershell
python "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/sars-cov-2/import_gisaid_accessions.py" --dry-run "C:/Downloads/gisaid_metadata.tsv"
python "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/sars-cov-2/import_gisaid_accessions.py" "C:/Downloads/gisaid_metadata.tsv"
```

Pass multiple returned TSV/CSV files in one invocation if needed. Standard
`Virus name` and `Accession ID` columns are accepted, as are `covv_virus_name` /
`covv_accession_id`, `Isolate_Name` / `Isolate_Id`, and the master GISAID column
names. An optional `Submitting_Sample_Id` matches the exact master `Key`.
Conflicting duplicate column aliases fail. Excel exports should first be saved
as TSV/CSV, preserving identifiers as text.

Names are matched exactly to stored `GISAID_Isolate_Name` or names generated from
the master `Key` and `Prove_Tatt` using this exporter's naming rule. No year/season
prefixes are guessed and identifiers are not padded or truncated on import.
For names based on approved manual overrides or older metadata, supply the
original export manifest:

```powershell
python .\gisaid\sars-cov-2\import_gisaid_accessions.py --master "N:/path/data/SC2/master.csv" --manifest "C:/submission/SC2_RUNID.manifest.json" "C:/Downloads/gisaid_metadata.tsv"
```

The manifest links each exact submitted name to its original FASTA ID through
the current master aliases. It is a mapping artifact, not a grant of approval.
It must not contradict another current name/identifier match. Missing/unmatched
sample identifiers are skipped and counted. Matched accession values must use
`EPI_ISL_<digits>`. Blank returned values preserve existing values. Duplicate
nonempty master keys, ambiguous name matches, duplicate accession ownership,
contradictory identifiers, or conflicting existing/returned values stop the
whole import before replacement. Identical duplicate returned rows are harmless.

`--dry-run` reads and reports proposed changes without locks or writes. An actual
update uses the same exclusive `master.csv.lock` directory as the pipeline
updater and fails immediately if it already exists. It never removes another
writer's lock. It validates a staged CSV, creates and verifies an original-byte
backup, checks for concurrent changes, replaces the master, and verifies the
result. The parent filesystem must support replacement; failure does not fall
back to deleting the master. Repeated identical imports make no write or backup.
Owned locks and temporary candidates are removed on ordinary completion/errors.
Interruption can leave a stale lock; confirm no writer is active before removing
it. A failed final readback can occur after replacement; inspect master and backup
before retrying instead of automatically restoring old data.

Imports do not edit FASTA, lab metadata or review history. They record returned
IDs even when an approval has since become outdated. Under the solution's current
hash policy, adding accession fields changes the reviewed row and can itself
make prior approval outdated. There is no automatic reapproval.

Production-share access, the deployed solution's configuration, lab-address
availability and representative submission acceptance still need deployment
validation. See the [deployment checks](../../sarsseq/DEPLOYMENT.md).
