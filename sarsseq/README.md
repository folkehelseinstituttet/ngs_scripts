
Run the wrapper with: bash /home/ngs/ngs_scripts/sarsseq/sarsseq_wrapper.sh -r TEST_SAR -a sars -p V5.4.2 -s Ses2425 -y 2025

For the complete updated workflow and first installation test, follow the
[deployment and acceptance guide](DEPLOYMENT.md). It lists runtime requirements,
read-only checks, test-copy updates, approval-based exports and accession imports.

### Inspect CSV schemas

`master_csv/inspect_schemas.py` prints column names and case-insensitive column
overlaps for the supplied CSV files. It does not print or write data rows. It
accepts semicolon-, comma- and tab-delimited files in UTF-8, UTF-16 or CP1252:

```bash
python3 sarsseq/master_csv/inspect_schemas.py \
  --report /path/to/run-report.csv \
  --metadata /path/to/metadata.csv \
  --master /path/to/master.csv
```

Each argument is optional, so a master that does not exist yet can be omitted.

### Preview a tabular master merge

`master_csv/preview_merge.py` produces a new local CSV for review. It does not
modify the master, upload files, or run sequence analysis. Keep this repository
intact because it uses the shared identifier utilities under `fluseq/master_csv`.
The default schema uses Influenza's metadata mappings and identifier/update
rules, with SARS-specific report mappings. `Prove_LW_ID` is the specimen index.
Metadata `RekvNr` becomes the legacy `Key`; metadata `Key` is preserved separately
as `Metadata_Key`. Both SARS report modes emit `Sample`: FASTQ matches sequencing
IDs, while FASTA also resolves exact specimen IDs and legacy names.
See the [schema and mapping contract](master_csv/README.md) for all mappings,
precedence, blank handling and validation rules. An optional JSON file overrides
selected mappings, for example:

```json
{"report": {"CustomRunName": "NGS_Run_ID"}}
```

```bash
python3 sarsseq/master_csv/preview_merge.py \
  --workflow fastq \
  --master /path/to/master.csv --metadata /path/to/metadata.csv \
  --report /path/to/report.csv \
  --output /path/to/new-preview.csv
```

The output must be a new file. Exact identifier conflicts stop the preview.
Use `--workflow fasta` for FASTA reports and `--nonempty-report` to preserve old
values for blank report cells. Default precedence is existing master, nonblank
metadata, then report values including blanks. Absent report columns are retained.
Only report samples receive metadata/report updates; unmatched existing rows
are retained, apart from identifier migration and known Norwegian text repairs
inherited from the shared merge utilities. All cell values remain text. The production updater below uses the
same schema and merge rules; the preview itself only writes a new local file.

### Update the production SC2 master CSV and FASTA

`master_csv/update_master.py` uses the SC2 schema with Influenza's locked file
transaction, backups and verified SMB uploads. It defaults to `master.csv` and
`NGS_PREP_SC2_report.csv` in the shared `NGS analysis database/data/SC2` directory.
Set `SARSSEQ_MASTER_CSV` for mounted access, or enable the SMB defaults:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --check-access
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --report /path/to/report/RUN_with_software_versions.csv \
  --fasta /path/to/report/RUN.fasta
```

The first command only reads the two CSVs; the second updates the CSV and FASTA.
Use `--workflow fasta` for FASTA reports. See
[production configuration and recovery](master_csv/README.md#production-csv-configuration)
for paths, overrides, checks and recovery.

Preview and production merges also apply Flu's Norwegian text repairs to county
names and `PCR_*_Res`, including existing master rows outside the run. Known
damage such as `Tr ndelag`, `M re g Romsdal`, ` stfold`, `P vist` and `Ikke p vist`
is repaired, together with reversible encoding damage in those fields. IDs, Ct
values and free text are unaffected. The summary reports `text_repaired`; changed
masters use the usual backup and lock protection. See the
[text repair rules](master_csv/README.md#norwegian-text-repairs).

Both wrappers now check master configuration before analysis and invoke the
updater after their result-upload steps. They use exactly this run's
`report/<RUN>_with_software_versions.csv`, falling back to `report/<RUN>.csv`.
They also merge exactly `report/<RUN>.fasta` into `master.fasta` beside the master
CSV, using Influenza's archive logic. Invalid incoming FASTA stops before either
write. Exact IDs are merged; conflicting duplicate records fail, and changed
archives receive verified backups. See the [archive rules](master_csv/README.md#master-fasta-archive).
The routine wrapper also supports FASTA matching with `--local-fasta` and honors
an explicit `--outdir`. An update failure stops completion and routine cleanup,
retaining results for a standalone retry.

Both wrappers enable master updates by default, following Influenza. Add `-M`
or set `SARSSEQ_MASTER_UPDATE=false` to skip them; `-M` overrides the environment.
Set `SARSSEQ_MASTER_CSV` for mounted access, or use the default SMB destination.
Explicit `SARSSEQ_MASTER_UPDATE=auto` enables updates only when a location is
configured. Validation skips updates, and routine offline mode skips both master
preflight and updates, even with a mounted master. `-t` only suppresses Teams;
combine it with `-M` when a test run should not update the master. The standalone
updater still defaults to `auto`. These controls cover both CSV and FASTA updates.
See [wrapper integration details](master_csv/README.md#wrapper-integration).

For offline FASTA analysis, use the routine wrapper with `-o --local-fasta`;
the dedicated FASTA wrapper requires online access. Offline FASTQ runs use an
explicit local directory or cached files under `$TMP_DIR/<RUN>` and default to
the samplesheet `$TMP_DIR/<RUN>.csv` (`--local-samplesheet` overrides it).

### GISAID export from the master

Use [sc2_gisaid_csv.py](../gisaid/sars-cov-2/sc2_gisaid_csv.py) to prepare the
separate submission CSV and matching FASTA. Both SC2 and INF master-based
exporters now require a current `Approved` decision from the solution, in addition
to their existing metadata/QC filters. They read the solution's `config.json`
and `reviews/` beside the master; a QC pass alone does not qualify. See
[SC2 setup, filters and usage](../gisaid/sars-cov-2/README_CSV.md). Export is local
and does not submit to GISAID or modify the master.

After submission, use the separate [SC2 accession importer](../gisaid/sars-cov-2/README_CSV.md#import-returned-accession-ids)
to update returned IDs with conflict checks, backup and lock cleanup. Start with
`--dry-run` against a copy during deployment testing.

### SARS QC HTML and JSON

The SARS QC report follows the Influenza report layout with SC2-specific
genome/CDS coverage, Nextclade QC, mixed-site counts, lineage/clade summaries,
qPCR detection/Ct evidence and an indel viewer. It includes sample filters,
filtered CSV exports, full JSON download, and print/PDF styling. Unsupported
Influenza metrics such as IRMA noise and segment reads are omitted.

```bash
python3 sarsseq/master_csv/sars_qc_report.py /path/to/report/RUN.csv \
  --workflow fastq --master /path/to/data/SC2/master.csv \
  --outdir /path/to/local-qc
```

Omit `--master` to generate without qPCR context. To generate after a master
update, add `--qc-output /path/to/local-qc/RUN_qc.html` to `update_master.py`.
All QC measurements come from the current report; the master supplies matched
identifiers and qPCR evidence only. Defaults are 80% genome/CDS coverage and
review above 3 genome mixed sites. Missing data stays unavailable.
See [QC rules and generation](master_csv/README.md#sars-qc-html-and-json).
Both wrappers automatically write `report/<RUN>_qc.html` and `<RUN>_qc.json`,
then upload and read back both files for checksum verification before completion
and routine cleanup. QC uses the existing result destination: `<RUN>/report` for
full uploads, or the analysis directory for CSV-only validation uploads. Failures
retain local results and block cleanup. Offline runs generate locally; `-M` and
validation still generate QC without master context. A current report CSV is
required in all modes.

Override assessment defaults with `SARSSEQ_QC_COVERAGE_THRESHOLD`,
`SARSSEQ_QC_CDS_THRESHOLD`, and `SARSSEQ_QC_MIXED_THRESHOLD`.
See [publishing and recovery](master_csv/README.md#automatic-qc-publishing-and-recovery)
for destinations, standalone retries and partial-upload handling.

Replace TEST with a run name (e.g. SAR002)

If running a verification of script add -v VER flag nad run with -p V4.1

## Run logs and cleanup

The routine wrapper writes `$HOME/sarsseq_<RUN>_wrapper.log`,
`sarsseq_<RUN>_wrapper_error.log`, `sarsseq_<RUN>_status.txt`, and
`sarsseq_<RUN>_nextflow.log`. Successful online runs archive verified logs to
`<RUN>/logs` on N: and clean this run's downloaded inputs, work and staged routine
results. Failed runs retain their logs; validation keeps full local results.
Offline runs keep logs, results and work locally. User-provided inputs and explicit
`--outdir` directories are retained.
See the [shared logging and cleanup policy](../resp-virus-toolkit/README.md#shared-wrapper-logging-and-cleanup)
for destinations, retries, failure handling and configuration.

Teams completion/failure notifications use `~/.teams_webhook_sars`. Add `-t`
(`--test`) to suppress notifications during testing; processing, uploads and
cleanup still run. Offline (`-o`) always suppresses Teams. Validation (`-v VER`)
sends notifications unless `-t` is also supplied.
See [Teams setup](../resp-virus-toolkit/README.md#teams-completion-and-failure-notifications).

### Primer-only QC wrapper

  Use the `sarsseq_primercheck.sh` helper when you only need primer mismatch statistics for consensus FASTA files stored on the N-drive. The script fetches the FASTA/
  BED/primer FASTA via `smbclient`, ensures an up-to-date `nf-core-sars` checkout, runs the primer-only workflow, then merges the resulting CSVs into the shared
  `insilisco_primer_experiments.csv`.

  Example:

  ```bash
  ngs_scripts/sarsseq/sarsseq_primercheck.sh \
      -f BA3.2.SAR022.fasta \
      -b IDTDNA_Midnight_120bp_v2.bed \
      -P IDTDNA_Midnight_120bp_v2.fasta \
      -n IDT_Midnight_v2 \
      -r IDT_Midnight_v2 \
      -o /mnt/tempdata/primercheck-test

  - -f is the multi-FASTA filename in N:\…\7-Export.
  - -b and -P are the primer BED and FASTA in N:\…\Primer-bed-files.
  - -n is a friendly primer set name stored in the outputs.
  - -r labels the run (embedded in Run_ID).
  - -o sets the local output directory.

  The wrapper automatically clones/pulls ~/nf-core-sars (override with -W /path/to/repo if needed) and uploads the merged insilisco_primer_experiments.csv back to N:\…\6-
  SARS-CoV-2_NGS_Dashboard_DB\Insilisco_primer_experiements.

## Primer checks

The routine wrapper enables primer-checker (PCR for influenza, PCR and NGS for
SARS/RSV). Use `-P` to override the PCR JSON file/directory and `-N` in SARS/RSV
to override the NGS primer-assets directory. The PCR defaults are defined near
the wrapper's argument parsing. `PRIMER_CHECK_ENABLED=false` disables the check.

CSV and HTML reports are written to `primer_check/`; `task_status.csv` identifies
any ignored failures. Online Docker tasks explicitly pull the latest published
CLI image. See the [deployment and input guide](https://github.com/RasmusKoRiis/primer-checker/blob/main/docs/PIPELINE_INTEGRATION.md)
before the first run.
