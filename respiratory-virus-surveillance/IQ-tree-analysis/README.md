# Viral Phylogeny Workflow with IQ-TREE and TreeTime

This repository contains a simple, reproducible Linux workflow for viral tip-dated phylogenetics from:

- one multiple FASTA file
- one metadata table

The workflow is general for viral sequence data and is not hardcoded to influenza. It is also suitable for influenza segment-specific FASTA files, such as HA-only or NA-only analyses, as long as the FASTA headers and metadata identifiers match exactly.

The entrypoint is [`scripts/run_phylo.sh`](/home/rasmuskopperud.riis/Coding/CODEX-projects/IQ-tree_tree_time/scripts/run_phylo.sh).

## Folder layout

The workflow assumes a project structure like:

```text
project_root/
├── data/
│   ├── sequences.fasta
│   └── metadata.tsv
├── results/
├── scripts/
└── envs/
```

Only relative paths are used. Run commands from the project root.

## What the workflow does

`scripts/run_phylo.sh` performs these steps:

1. Validate FASTA readability, headers, duplicate names, and basic sequence content.
2. Parse the metadata with a modular `--metadata-format` switch.
3. Detect likely identifier and sampling-date columns.
4. Skip samples without a usable sampling date and record them in a report.
5. Derive a minimal TreeTime dates file from the richer metadata.
6. Confirm the FASTA headers and metadata identifiers match exactly.
7. Filter the FASTA to sequences that still have usable dates.
8. Run MAFFT to produce the aligned FASTA used downstream.
9. Run IQ-TREE maximum-likelihood inference with ModelFinder, SH-aLRT, and ultrafast bootstrap.
10. Run `treetime clock` with configurable rerooting or outgroup handling.
11. Run full `treetime` timetree inference.
12. Enrich the TreeTime Auspice JSON with retained metadata fields when available.

Outputs are written under `results/` in these subfolders:

- `results/iqtree`
- `results/derived_metadata`
- `results/clock`
- `results/timetree`
- `results/qc`

## Installation

Use `mamba` or `conda` on Linux.

```bash
mamba env create -f envs/environment.yml
conda activate viral-phylo-iqtree-treetime
```

If you prefer `conda`:

```bash
conda env create -f envs/environment.yml
conda activate viral-phylo-iqtree-treetime
```

Required tools:

- `iqtree` or `iqtree3`
- `treetime`
- `mafft`
- `python3` for metadata/date parsing and FASTA validation

## Test data

An anonymized H3N2 HA fixture is available under `test-data/`. It uses sequence
and metadata values derived from the local `FASTA/` and `META/` inputs, but the
sample identifiers have been replaced with synthetic `test_h3n2_*` IDs.

To test the full pipeline with this fixture:

```bash
bash scripts/run_phylo.sh \
  --fasta test-data/sequences.fasta \
  --metadata test-data/metadata.csv \
  --metadata-format default \
  --outdir results/test-data \
  --clock-root least-squares \
  --display-columns auto \
  --seq-len 1700
```

## Example command

```bash
bash scripts/run_phylo.sh \
  --fasta data/sequences.fasta \
  --metadata data/metadata.tsv \
  --metadata-format default \
  --outdir results \
  --clock-root least-squares \
  --display-columns auto \
  --seq-len 1700
```

The script still accepts `--force-align` for backward compatibility, but alignment is now always performed before IQ-TREE:

```bash
bash scripts/run_phylo.sh \
  --fasta data/sequences.fasta \
  --metadata data/metadata.tsv \
  --metadata-format default \
  --outdir results \
  --force-align
```

To root the clock analysis on a specific outgroup:

```bash
bash scripts/run_phylo.sh \
  --fasta data/sequences.fasta \
  --metadata data/metadata.tsv \
  --outdir results \
  --outgroup tip_A,tip_B
```

To keep the existing tree root instead of letting TreeTime reroot:

```bash
bash scripts/run_phylo.sh \
  --fasta data/sequences.fasta \
  --metadata data/metadata.tsv \
  --outdir results \
  --clock-root keep
```

To optionally exclude metadata rows where `NGS_Report` is `NO`:

```bash
bash scripts/run_phylo.sh \
  --fasta data/sequences.fasta \
  --metadata data/metadata.tsv \
  --outdir results \
  --exclude-ngs-report-no
```

## Expected FASTA format

The input FASTA should contain one identifier per sequence header, for example:

```fasta
>sample_A
ATGG...
>sample_B
ATGG...
```

Important behavior:

- Headers are matched exactly against the chosen metadata identifier column.
- Headers containing whitespace are rejected.
- Duplicate FASTA identifiers are rejected.
- If exact matching fails, the workflow supports one conservative fallback:
  - FASTA headers of the form `prefix|metadata_id` are reconciled automatically when the suffix after the final `|` matches the selected metadata identifier column exactly and unambiguously
- The workflow records whether the input appears aligned in `results/qc/fasta_summary.tsv`
- The workflow always runs MAFFT on the date-qualified input sequences so downstream steps always use a fresh aligned FASTA

The alignment heuristic is still documented in `results/qc/fasta_summary.tsv`, but it is now informational rather than controlling execution.

## Expected metadata format for `--metadata-format default`

The default parser accepts a delimited text file with a header row. It supports:

- tab-delimited
- semicolon-delimited
- comma-delimited

The metadata may contain many extra columns. The workflow preserves the original file unchanged and derives a minimal TreeTime-ready dates file from it.

Common metadata fields that may be present include:

- `country`
- `county`
- `region`
- `host`
- `subtype`
- `segment`
- `lab`
- `lineage`
- `clade`
- `collection_date`
- `submission_date`

The workflow can also derive visualization metadata for retained samples and add it to the Auspice JSON. By default it tries to detect common fields such as:

- country
- county
- region
- age
- age group
- host
- segment
- lab
- lineage
- clade
- HA subclade (`NC_HA_Subclade`)

You can override this with `--display-columns`, either disabling augmentation with `none` or requesting explicit metadata header names.

### Identifier column detection

The default parser looks for these identifier-style column names in priority order:

- `sample_id`
- `sequence_name`
- `strain`
- `sample`
- `name`
- `taxon`
- `id`
- `accession`
- `key`

If no exact match is found, the parser tries a very small fuzzy fallback for obvious `*_id`-style headers. If detection is still uncertain, the workflow fails loudly and reports:

- the columns it found
- the identifier/date names it expected
- guidance to rename headers or extend the parser

The selected columns are recorded in `results/derived_metadata/parser_summary.tsv` and also printed during the run.

### Date column detection

The default parser looks for these date-style column names in priority order:

- `collection_date`
- `specimen_date`
- `isolation_date`
- `sample_date`
- `sampling_date`
- `collection_dato`
- `prove_tatt`
- `date`

If no exact match is found, the parser tries a narrow fuzzy fallback for obvious date-like headers such as `*date`, `*dato`, or `prove_tatt`.

## How TreeTime dates are derived

TreeTime only needs sample name and sampling date. The workflow generates:

- `results/derived_metadata/dates_for_treetime.tsv`
- `results/derived_metadata/dates_with_audit.tsv`
- `results/derived_metadata/skipped_samples_missing_dates.tsv`
- `results/derived_metadata/retained_visualization_metadata.tsv`
- `results/derived_metadata/visualization_fields.tsv`

`dates_for_treetime.tsv` contains only:

- `name`
- `date`

The workflow normalizes supported date formats to decimal years before calling TreeTime:

- `YYYY-MM-DD`: converted to an exact decimal year
- `YYYY-MM`: converted to the midpoint of that month
- `YYYY`: converted to the midpoint of that year
- decimal year: passed through after validation

This midpoint behavior is a deliberate version 1 choice so partial dates are handled consistently and TreeTime always receives a numeric date column.

Rows without a usable date are skipped rather than causing the workflow to stop. They are:

- reported in the terminal during the run
- written to `results/derived_metadata/skipped_samples_missing_dates.tsv`
- excluded from the filtered FASTA, alignment, IQ-TREE, and TreeTime

Rows with malformed non-empty dates still cause the workflow to fail loudly, because that is a metadata quality problem rather than a simple missing-value case.

If `--exclude-ngs-report-no` is enabled, rows with `NGS_Report=NO` are also excluded before downstream analysis. This filter is off by default.

## Sequence length handling for TreeTime clock

The script accepts an optional `--seq-len` argument. If it is omitted, the workflow infers sequence length from the aligned FASTA and uses that value for `treetime clock`.

For segment-specific analyses, such as influenza HA or NA, providing `--seq-len` explicitly can be useful when you want strict control over the length used in the clock model.

## IQ-TREE behavior

IQ-TREE is detected as either `iqtree` or `iqtree3`.

The workflow currently runs:

```bash
iqtree -s aligned.fasta -m MFP -alrt 1000 -B 1000 -nt AUTO -pre results/iqtree/viral_phylogeny -redo
```

Notes:

- `-m MFP` enables ModelFinder-style model selection
- `-alrt 1000` adds SH-aLRT support
- `-B 1000` adds ultrafast bootstrap support
- `-nt AUTO` lets IQ-TREE choose CPU usage automatically

The code is intentionally laid out so partition files, codon models, or partitioned analyses can be added later without rewriting the workflow.

## TreeTime behavior

The workflow runs TreeTime in two steps:

1. `treetime clock`
2. full `treetime` timetree inference

Clock rooting can be controlled with:

- `--clock-root least-squares`
- `--clock-root min_dev`
- `--clock-root oldest`
- `--clock-root keep`
- `--clock-root sample_name`
- `--outgroup sample_A,sample_B`

If neither option is provided, the workflow uses TreeTime's default least-squares rerooting.

Clock-analysis outputs are preserved under `results/clock`. The workflow also writes:

- `results/clock/clock_summary.tsv`
- `results/clock/clock_warnings.txt`

The warning logic is intentionally simple. It flags:

- negative estimated substitution rate
- low root-to-tip `R^2` below `0.1`
- missing parseable rate or `R^2` from TreeTime outputs

The clock step’s rerooted tree is used for timetree inference when it can be found. If not, the script falls back to the original IQ-TREE tree and records a warning.

## Auspice enrichment

If TreeTime writes `results/timetree/auspice_tree.json`, the workflow enriches it with retained metadata fields for terminal nodes.

The workflow keeps:

- the enriched JSON at `results/timetree/auspice_tree.json`
- a raw backup at `results/timetree/auspice_tree.treetime_raw.json`
- an augmentation report at `results/timetree/auspice_metadata_report.tsv`

This lets you color tips in Auspice by fields such as geography, age, host, HA subclade, or lab when those metadata columns are present and retained.

For some metadata sources, Norwegian geography values may already be stored with mangled ASCII placeholders such as `Tr ndelag` or `stfold`. The workflow applies a small repair map for known county/region values so these display correctly in visualization outputs.

## QC and preprocessing

Version 1 includes a QC/preprocessing stage as a documented placeholder. Current behavior focuses on validation rather than filtering:

- FASTA validation
- metadata validation
- skipping of undated samples with reporting
- identifier matching
- FASTA filtering to date-qualified sequences
- alignment status logging

Files reserved for future extension:

- `results/qc/qc_notes.txt`
- `results/qc/masking_rules.placeholder.txt`
- `results/downstream_hooks.txt`

These are the intended places to add:

- low-quality sequence filtering
- trimming of problematic sequence ends
- virus-specific masking rules
- ancestral reconstruction or homoplasy analyses

## Common failure modes

Typical reasons the workflow will stop:

- FASTA file missing, unreadable, or empty
- metadata file missing, unreadable, or empty
- FASTA headers contain whitespace
- duplicate FASTA identifiers
- duplicate metadata identifiers
- identifier/date columns cannot be identified confidently
- unsupported date format in metadata
- too few sequences remain after excluding samples without usable dates
- FASTA headers and metadata identifiers do not match exactly
- `mafft` is not installed
- `iqtree` or `iqtree3` is not installed
- `treetime` is not installed
- a requested `--display-columns` header is not present in the metadata

When matching fails, the script reports examples of:

- identifiers present in FASTA but not metadata
- identifiers present in metadata but not FASTA

## Extending the workflow later

Version 1 is intentionally conservative. The script is structured so you can add:

- new metadata parsers behind `--metadata-format`
- virus-specific QC and masking
- partitioned or codon-aware IQ-TREE runs
- richer metadata reuse for annotation and visualization
- downstream ancestral sequence or recurrent mutation analyses
