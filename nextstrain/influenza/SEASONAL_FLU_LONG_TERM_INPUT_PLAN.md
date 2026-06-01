# Seasonal Flu Long-Term Input Plan

## Context

The current FHI seasonal influenza wrapper keeps using local FHI inputs:

- `metadata.xls` or `metadata.xlsx`
- `raw_sequences_ha.fasta`
- `raw_sequences_na.fasta`

The wrapper copies these files into the cloned `nextstrain/seasonal-flu` repository and uses `profiles/niph/prepare_data.smk` to convert them into the files expected by the main phylogenetic workflow:

- `data/{lineage}/metadata.tsv`
- `data/{lineage}/ha.fasta`
- `data/{lineage}/na.fasta`

Current upstream `nextstrain/seasonal-flu` has moved GISAID raw input handling into the `ingest/` workflow. That ingest workflow expects GISAID-style paired metadata and sequence files, specific naming conventions, and richer FASTA headers than the current FHI local files provide.

## Short-Term Fix In Place

The current wrapper should keep the existing local-input workflow and restore the missing converter:

- Copy `global/xls2csv.py` into the upstream checkout at `scripts/xls2csv.py`.
- Copy `global/nextstrain.yaml` over the upstream rule environment so Excel dependencies are available when Snakemake uses conda.
- Accept either `metadata.xlsx` or `metadata.xls` from each lineage input folder.
- Copy the selected metadata file into the seasonal-flu checkout as `metadata.xls`, because the existing FHI Snakemake rule expects that path and the converter detects the real Excel format from file content.

This is deliberately narrow. It fixes the broken wrapper without changing sequence naming, metadata fields, filtering, or build behavior.

## Why Not Move Directly To Upstream Ingest

The upstream ingest workflow is a better long-term pattern for raw GISAID downloads, but it is not a drop-in replacement for the current FHI workflow.

Known mismatches:

- Upstream ingest expects paired files named like `YYYY-MM-DD-N-metadata.xls` and `YYYY-MM-DD-N-sequences.fasta`.
- It expects combined sequence downloads with headers containing fields such as segment accession and lab names.
- The FHI FASTA files currently use strain-name headers, for example `A/Norway/08299/2025`.
- The example FHI metadata has the expected local columns, but accession values can be blank.
- The current FHI workflow already separates HA and NA FASTAs before Nextstrain sees them.

Moving directly to ingest would require reshaping FHI inputs or adding FHI-specific ingest rules.

## Recommended Long-Term Direction

Prefer a small FHI-owned input preparation layer over forcing the FHI files through GISAID ingest unchanged.

The target interface should be the same as upstream phylogenetic workflow inputs:

- `data/h1n1pdm/metadata.tsv`
- `data/h1n1pdm/ha.fasta`
- `data/h1n1pdm/na.fasta`
- `data/h3n2/metadata.tsv`
- `data/h3n2/ha.fasta`
- `data/h3n2/na.fasta`
- `data/vic/metadata.tsv`
- `data/vic/ha.fasta`
- `data/vic/na.fasta`

Once FHI can reliably produce those files, the custom `prepare_data.smk` rule can be removed or reduced to validation only.

## Proposed Migration Steps

1. Document the local FHI input contract.

   Required metadata columns:

   - `Isolate_Name`
   - `Isolate_Id`
   - `Passage_History`
   - `Location`
   - `Authors`
   - `Originating_Lab`
   - `Collection_Date`
   - `Submission_Date`

   Required sequence files:

   - `raw_sequences_ha.fasta`
   - `raw_sequences_na.fasta`

2. Create a dedicated FHI input preparation script.

   Suggested name:

   - `fhi/prepare_local_inputs.py`

   Responsibilities:

   - Read `.xls` and `.xlsx`.
   - Write `metadata.tsv` directly.
   - Rename metadata columns to Nextstrain names.
   - Split `Location` into `region`, `country`, `division`, and `location`.
   - Normalize strain names exactly as sequence names will be normalized.
   - Remove duplicate strains deterministically.
   - Validate that metadata strains and FASTA IDs overlap.
   - Emit clear errors when required columns or files are missing.

3. Replace the shell pipeline in `fhi/prepare_data.smk`.

   Instead of chaining `xls2csv.py`, `csvtk cut`, `csvtk rename`, `csvtk sep`, `csvtk sort`, and `csvtk uniq`, call the FHI preparation script once.

   This reduces dependency on fragile shell pipelines and makes errors easier to interpret.

4. Add lightweight fixture tests.

   Fixtures should include:

   - A small `.xlsx` metadata file.
   - A small `.xls` metadata file if old Excel format still appears.
   - Matching HA and NA FASTA files.
   - A row with blank accession.
   - A duplicate strain row.
   - A location with fewer than four ` / ` parts.

   Test outputs:

   - Metadata has required Nextstrain columns.
   - FASTA IDs and metadata strains match after normalization.
   - Duplicate handling is stable.

5. Decide whether to keep compatibility with upstream ingest.

   If FHI later starts downloading raw GISAID files directly, add an optional upstream-ingest path:

   - Keep raw GISAID files in `ingest/data/`.
   - Add FHI ingest config for `h1n1pdm`, `h3n2`, and `vic`.
   - Run `nextstrain build ingest --configfile ...`.
   - Copy `ingest/results/*` to top-level `data/`.

   If FHI continues producing local Excel plus per-segment FASTAs, keep the FHI preparation script as the primary path.

6. Pin or record the upstream seasonal-flu revision.

   The wrapper currently resets to `origin/master`, which can break when upstream changes rule names, script paths, or dependencies.

   Safer options:

   - Pin to a tested commit SHA.
   - Record the tested upstream commit in build output.
   - Add a monthly scheduled compatibility check against current `master`.

## Acceptance Criteria For Migration

The long-term input layer is ready when:

- The wrapper can run from fresh upstream `seasonal-flu` without copying legacy helper scripts.
- The FHI input conversion is tested outside a full Nextstrain build.
- Error messages identify bad input files before Snakemake starts the expensive build.
- The generated `metadata.tsv`, `ha.fasta`, and `na.fasta` match the main seasonal-flu workflow expectations.
- The wrapper behavior is documented for both `.xls` and `.xlsx` inputs.
