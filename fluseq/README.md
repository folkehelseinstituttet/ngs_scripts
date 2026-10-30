# fluseq: Quick Start Guide

---

## 1. Human influenza pipeline (FASTQ)

### Routine run

```bash
screen -S fluseq-RUN -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_wrapper.sh \
  -r INF075 \
  -a influensa \
  -s Ses2425 \
  -y 2025
```

Replace:
- `INF075` → your run name  
- `Ses2425` → season folder  
- `2025` → year folder  

---

### Validation run (VER)

```bash
screen -S fluseq-RUN-VER -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_wrapper.sh \
  -r INF075 \
  -a influensa \
  -s Ses2425 \
  -y 2025 \
  -v VER
```

---

## 2. Avian influenza pipeline (FASTQ)

Used for **avian influenza** runs (H5, H7, etc.).

### Routine avian run

```bash
screen -S fluseq-RUN-avian -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_avian_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025
```

Replace:
- `INF075` → your run name  
- `Ses2425` → season folder  
- `2025` → year folder  

---

## 3. Avian influenza pipeline (FASTA)

Used for **avian influenza** runs (H5, H7, etc.) with FASTA as input.
FASTA-seqeunces are retrived from N:\**\1-Rutine\2-Resultater\Influensa\12-Export, where -r references to the folder with FASTA-file. 

### Routine avian run

```bash
screen -S fluseq-INF077-avian -d -m bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025
```

---

## 4. Human influenza pipeline (FASTA)

Used for **human influenza** runs with FASTA as input.
FASTA-seqeunces are retrived from N:\**\1-Rutine\2-Resultater\Influensa\12-Export, where -r references to the folder with FASTA-file. 

### Routine avian run

```bash
screen -S fluseq-INF077-human -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_fasta_wrapper.sh \
  -r INF077 \
  -a influensa \
  -s Ses2425 \
  -y 2025
```

---

### Validation avian run

```bash
screen -S fluseq-RUN-avian-VER -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_avian_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025 \
  -v VER
```

---


## Interactive run QC report

Both human wrappers now create `<RUN>_qc.html` and `<RUN>_qc.json` after the
master CSV merge. The HTML is a single offline file: open it directly in a
browser, with no installation or web server. It includes:

- qPCR mismatches using the master's `PCR_H1_Res`, `PCR_H3_Res`, `PCR_H5_Res`,
  `PCR_Bvic_Res` and `PCR_Byam_Res`; `Påvist` is positive, ignoring case/spaces.
- Successful final subtype calls and no-call rates for every row in the run report.
- Per-segment pass, low-coverage failure and missing/invalid counts and percentages.
  The default coverage threshold is 80%, matching the existing pipeline.
- Mixed-site counts **greater than 4**, with the affected segments. Duplicate
  HA1/HA2 and M1/M2 segment counts are counted once.
- A searchable indel/frameshift viewer with segment and event-type filters.
- IRMA noise **greater than 0.09**, plus the existing QC and characterisation findings.
- Finding buttons, sample and qPCR filters, sortable samples, CSV exports and printing.

Enable the master merge to include up-to-date qPCR comparisons:

```bash
export FLUSEQ_MASTER_UPDATE=true
```

Place `NGS_PREP_INF_report.csv` beside the master as described in
[master_csv/README.md](master_csv/README.md). When merging is disabled or skipped
for validation, the QC report still contains run measurements and explicitly
marks the master comparison as unavailable.

The wrappers generate the files under
`/home/ngs/out_fluseq/<RUN>/reporthuman/` and upload and verify both files in the
run's `reporthuman` folder on the N: drive. The enriched HTML replaces the
pipeline's initial QC HTML there. The FASTQ wrapper can remove successful local
results during its normal cleanup; open the shared-drive copy. Validation runs
publish the files in their configured validation report directory.

To regenerate just the report from existing local/mounted files, without changing
the master or rerunning analysis:

```bash
python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/report_qc_html.py \
  /path/to/reporthuman/INF077.csv \
  --master /path/to/master.csv \
  --outdir /path/to/reporthuman
```

Add `--workflow fasta` for a FASTA report. Use `--coverage-threshold 90` to change
the reporting threshold; wrappers accept `FLUSEQ_QC_COVERAGE_THRESHOLD` instead.
These settings affect the HTML assessment only. The existing source QC summary
and subtype calls remain unchanged. See the HTML's assessment rules for metric
definitions, denominator choices and missing-data handling.

## Master FASTA archive

Both human wrappers merge the completed `reporthuman/<RUN>.fasta` into
`master.fasta` in the same directory as `master.csv`, after the CSV merge.
This uses the same mounted directory or SMB share and credentials.
`FLUSEQ_MASTER_UPDATE=true` enables both master updates; validation runs and
`FLUSEQ_MASTER_UPDATE=false` skip both.

Records match by their exact FASTA ID (the complete first whitespace-delimited
token after `>`), including any segment suffix. New IDs are appended; existing
IDs are replaced with the latest incoming header and sequence. Identical records
remain unchanged. Different sample/segment IDs are retained even when their
sequence strings are identical. Records missing from this run are retained.

The first non-empty run creates the master FASTA if it is absent. An existing
master receives a timestamped backup before replacement. Repeating the same
merge does not duplicate records or create unnecessary backups. Empty run FASTAs
leave the archive unchanged; malformed records or conflicting duplicate IDs
stop the merge. Identical duplicate records are collapsed.

After updating the server scripts, add FASTA records from an already completed
run without rerunning Nextflow:

```bash
FLUSEQ_MASTER_UPDATE=true \
python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/update_master_csv.py \
  --workflow fastq \
  --report /home/ngs/out_fluseq/INF109/reporthuman/INF109.csv \
  --fasta /home/ngs/out_fluseq/INF109/reporthuman/INF109.fasta
```

Use `--workflow fasta` for a FASTA workflow. Omitting `--fasta` keeps the existing
CSV-only retry behavior. See [master_csv/README.md](master_csv/README.md) for
locking, backup and recovery details.

## Reference validation

Both human influenza wrappers download `human` and `human_vaccine` references
and `reference_table.csv` from the season's `references` directory, then validate
both sets before starting the pipeline. Each reference FASTA header must use
`STRAIN|EPI_ISL_<digits>_<segment>` and match the table's `Reference` and
`GISAID_EPI` columns. Missing or mismatched EPI identifiers stop the run.

Check an existing local reference bundle without downloads or pipeline activity:

```bash
bash fluseq/fluseq_fasta_wrapper.sh --check-references \
  /path/to/sequence_references /path/to/reference_table.csv human
```

Use `human_vaccine` to check vaccine references. The same option is available in
`fluseq_wrapper.sh`. This checks headers and record structure, not sequence
identity or segment completeness.

## 3. Checking progress

List sessions:

```bash
screen -ls
```

Reconnect:

```bash
screen -r fluseq-INF075
```

Detach again with `Ctrl+A` then `D`.

## Primer checks

The routine wrapper enables primer-checker (PCR for influenza, PCR and NGS for
SARS/RSV). Use `-P` to override the PCR JSON file/directory and `-N` in SARS/RSV
to override the NGS primer-assets directory. The PCR defaults are defined near
the wrapper's argument parsing. `PRIMER_CHECK_ENABLED=false` disables the check.

CSV and HTML reports are written to `primer_check/`; `task_status.csv` identifies
any ignored failures. Online Docker tasks explicitly pull the latest published
CLI image. See the [deployment and input guide](https://github.com/RasmusKoRiis/primer-checker/blob/main/docs/PIPELINE_INTEGRATION.md)
before the first run.

## Run logs and cleanup

The routine wrapper writes `$HOME/fluseq_<RUN>_wrapper.log`,
`fluseq_<RUN>_wrapper_error.log`, `fluseq_<RUN>_status.txt`, and
`fluseq_<RUN>_nextflow.log`. Successful online runs archive verified logs to
`<RUN>/logs` on N: and clean this run's local inputs, work and staged routine
results. Failed runs retain their logs; validation keeps full local results.
See the [shared logging and cleanup policy](../resp-virus-toolkit/README.md#shared-wrapper-logging-and-cleanup)
for destinations, retries, failure handling and configuration.

Teams completion/failure notifications use `~/.teams_webhook_inf`. Add `-t` to
suppress notifications during testing; the pipeline, uploads and cleanup still
run. Validation (`-v VER`) sends notifications unless `-t` is also supplied.
See [Teams setup](../resp-virus-toolkit/README.md#teams-completion-and-failure-notifications).
