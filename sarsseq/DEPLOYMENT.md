# SC2 deployment and acceptance checks

On the submission workstation, store the complete checkout at
`N:/Virologi/NGS/tmp/ngs_scripts` (the folder name includes the final `s`).
The INF R script has that shared-helper location as a built-in fallback for
console selections. SC2 uses its own script location. Existing master/data
locations are already configured separately.

Deploy the complete `ngs_scripts` checkout, including `fluseq/master_csv`,
`sarsseq/master_csv`, `gisaid/shared` and both GISAID directories. The R script
locates shared files using its `source()` path or the documented shared-directory
override. Copying only a script is insufficient for these shared imports.

Implementation, synthetic integration tests and local deployment checks are
complete. Live N-drive access, Windows/SMB replacement behavior and acceptance
against the site's production reports must be checked on the deployment hosts.
No production data was read, submitted or changed during development.

## Requirements by operation

| Operation | Runtime requirements |
| --- | --- |
| SC2 preview, QC and accession import | Python 3.10+; standard library |
| SC2 master updates via SMB | Python plus existing `smbclient` and credentials |
| SARS wrappers | Existing Bash, Nextflow and pipeline environment; Python and SMB as above |
| SC2 submission export | Python 3.10+ and Node.js 18+ |
| INF submission export | R, Node.js 18+, `readr`, `dplyr`, `tidyr`, `tibble`, `purrr`, `stringr`, `magrittr`, `lubridate` |
| Automated tests | Python/pytest, Node.js; R and the listed packages for the full INF integration tests |

Node.js is used by the **submission approval filter**, including when the INF
exporter is launched from R. It is not required by SC2 master updates, QC or the
accession importer. `GISAID_NODE` can point to its executable. The exporter reads
current approvals from the solution's `config.json` and `reviews/` beside each
master. It never infers approval from a QC report or a master-cell label.

## Data layout and configuration

```text
NGS analysis database/data/
  SC2/
    master.csv
    NGS_PREP_SC2_report.csv
    master.fasta
    config.json                 # supplied by the review solution
    reviews/                    # existing immutable review history
  INF/
    master.csv
    master.fasta
    config.json
    reviews/
```

For mounted SC2 access, set `SARSSEQ_MASTER_CSV` to the full master filename.
Metadata defaults to `NGS_PREP_SC2_report.csv` beside it; set
`SARSSEQ_METADATA_CSV` when stored elsewhere. The shared FASTA archive is always
`master.fasta` beside the master CSV. SMB settings and credential paths are
listed in [master configuration](master_csv/README.md#production-csv-configuration).

Wrappers default to enabled master updates. `-M` disables CSV/FASTA master
updates but still generates and publishes QC. Validation skips master updates;
routine offline mode generates local QC and performs no master/SMB access.
`-t` suppresses Teams notifications only. Online result/QC publishing uses the
wrapper's result destination independently of the master override.

## Read-only checks first

From the repository root, check the included source-derived synthetic reports:

```bash
python3 sarsseq/master_csv/validate_deployment.py --workflow fastq \
  --report sarsseq/tests/fixtures/fastq_report.csv \
  --master sarsseq/tests/fixtures/master.csv --metadata sarsseq/tests/fixtures/metadata.csv \
  --fasta sarsseq/tests/fixtures/run.fasta

python3 sarsseq/master_csv/validate_deployment.py --workflow fasta \
  --report sarsseq/tests/fixtures/fasta_report.csv \
  --master sarsseq/tests/fixtures/master.csv --metadata sarsseq/tests/fixtures/metadata.csv \
  --fasta sarsseq/tests/fixtures/run.fasta
```

Repeat with representative completed FASTQ and FASTA reports, the deployed
master and metadata paths, and their run FASTA files. The tool parses inputs,
computes an in-memory merge and QC assessment, validates optional lab/approval
data, and checks Bash syntax when Bash is available. It creates no outputs,
locks, backups or remote uploads. Add `--lab /path/Innsender_GISAID.csv --reviews`
to include the lab table and current approval store. `--reviews` requires Node.
The output contains aggregate counts, not specimen records. Exit zero means the
format/configuration checks passed; it is not an approval decision. Deliberately
missing metrics in the synthetic fixtures produce review flags.

On the Linux pipeline host, the existing master preflight checks local setup;
the separate access check downloads/reads the two CSVs without modifying them:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py --workflow fastq --check-config
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py --workflow fastq --check-access
```

These commands do not verify write permission, result-share QC publishing or
server rename behavior. Exercise those operations against an isolated test
directory with the deployment account before enabling production runs.

## First controlled update and submission

1. Copy the deployed SC2 master, metadata, archive and matching review store to
   a protected test directory. Keep identifiers as text. Use a completed run
   report plus its FASTA; do not concatenate the duplicate report variants.
2. Point `SARSSEQ_MASTER_CSV` and, if needed, `SARSSEQ_METADATA_CSV` at these copies.
   Run `update_master.py --workflow fastq|fasta --report ... --fasta ...
   --qc-output .../RUN_qc.html`. Check IDs, metadata precedence, CSV/FASTA backups,
   qPCR context and absent SC2 metrics. Repeat the same input: master files should
   remain unchanged and no new master backups should appear.
3. For a test SMB destination, add `--qc-smb-share`, `--qc-smb-dir` and
   `--qc-smb-auth`. Confirm both HTML and JSON reach the intended directory and
   are verified. Test a denied/unavailable destination: exit must be nonzero,
   local outputs must remain, and the wrapper must not announce completion or
   clean its staged results. Use a separate test run ID for wrapper acceptance.
4. Review the current test master in the solution. Export with the
   [SC2 instructions](../gisaid/sars-cov-2/README_CSV.md) or
   [INF instructions](../gisaid/influenza/README_CSV.md). Confirm an unreviewed,
   rejected, conflicting or outdated row is excluded; an approved row must still
   satisfy the metadata/QC filters. Check lab addresses, authors and assembly
   method. Compare submission CSV identifiers with FASTA headers.
5. Test the accession importer with `--dry-run` against the copy, then import.
   Verify unmatched counts, conflict failures, backup contents and lock cleanup.
   Repeat the import to verify it does not rewrite the master. Accession fields
   participate in the solution's current fingerprint policy, so a changed master
   can make prior approvals outdated; review events are never edited by import.

Run all automated checks from the repository root:

```bash
pytest -q sarsseq/tests fluseq/tests gisaid/tests
```

R integration tests explicitly skip when their R packages are unavailable. To
run the full suite, install the documented dependencies and inspect the final
passed/skipped totals. Development installed R packages only in a temporary
library and ran the full suite with `R_LIBS_USER` set to that library.

## What has been exercised here

- Mounted CSV transactions and simulated SMB backup/upload/rename/readback
  failures, locking, concurrent edits, Unicode repair and repeat updates.
- Real wrapper preflight and completion sections for routine FASTQ, routine
  FASTA and the dedicated FASTA wrapper, with synthetic external uploads.
- Master FASTA merging, QC generation/filter/export behavior, verified
  publishing, failure retention and cleanup ordering.
- The full wrapper → master/archive → QC publication → solution approval →
  SC2 submission → accession import chain for all three entry paths.
- Real INF R exports and console/`source()` launch methods, approval history,
  metadata filters, per-segment exclusions, and SC2 export/import failures.

Actual Nextflow sequencing runs, Windows filesystem replacement, live SMB ACLs,
browser rendering on the deployment workstation, GISAID submission acceptance
and representative production reports remain site acceptance checks. Use the
same code revision on the pipeline and submission workstations.
