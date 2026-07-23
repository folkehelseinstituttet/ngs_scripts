# Current workflow inventory

This document records the workflow as implemented before adding a Nextclade or
Nextalign path. It describes current inputs, processing steps, outputs, and the
places in the code responsible for each step. It does not propose or implement
behavior changes.

## Entrypoints

There are two shell entrypoints:

1. [`scripts/run_phylo.sh`](scripts/run_phylo.sh) is the main nucleotide
   phylogeny workflow. It validates and filters the inputs, runs MAFFT,
   IQ-TREE, and TreeTime, then enriches TreeTime's Auspice JSON.
2. [`scripts/run_alignments_and_phylo.sh`](scripts/run_alignments_and_phylo.sh)
   is a batch/single-file wrapper. It creates additional standalone nucleotide
   and amino-acid alignments, runs a separate amino-acid IQ-TREE analysis, and
   calls `run_phylo.sh` for the main nucleotide workflow.

The wrapper can process one FASTA or discover several FASTA files in a
directory. It selects a same-stem metadata file when possible, or accepts one
metadata file for every FASTA.

## Implemented data flow

```text
Input nucleotide FASTA + metadata
|
|  scripts/run_alignments_and_phylo.sh (optional wrapper)
|
+---> MAFFT on original nucleotides
|       `alignments/<sample>/<sample>.nucleotide.aligned.fasta`
|       (standalone output; not consumed by run_phylo.sh)
|
+---> choose one of reading frames 0, 1, or 2 independently per sequence
|       -> translate original, unaligned nucleotide sequence
|       -> MAFFT amino-acid alignment
|       -> separate amino-acid IQ-TREE analysis
|
`---> scripts/run_phylo.sh, receiving the original nucleotide FASTA
        |
        +-- validate FASTA and parse metadata/dates
        +-- reconcile identifiers and remove sequences without retained dates
        +-- MAFFT nucleotide alignment
        +-- IQ-TREE nucleotide maximum-likelihood tree
        +-- TreeTime clock analysis
        +-- TreeTime timetree, nucleotide reconstruction, and Auspice JSON
        +-- add retained metadata to Auspice tips
        `-- translate reconstructed branch states in one user-selected frame
            and add amino-acid mutations and labels to the Auspice JSON
```

The two nucleotide MAFFT calls are independent. The wrapper's standalone
nucleotide alignment is not passed to `run_phylo.sh`; the main phylogeny always
uses `qc/aligned_sequences.fasta`, created by running MAFFT on the date-filtered
FASTA inside `run_phylo.sh`.

## Inputs

### Main workflow: `run_phylo.sh`

Required runtime inputs are:

| Input | Option | Current handling |
| --- | --- | --- |
| Nucleotide FASTA | `--fasta PATH` | Headers must be non-empty, unique, and whitespace-free. Sequence content and lengths are checked. |
| Metadata table | `--metadata PATH` | Tab-, comma-, or semicolon-delimited text; the identifier and sampling-date columns are detected from known names. |
| Output directory | `--outdir PATH` | Contains the QC, IQ-TREE, TreeTime, and visualization products. |

Important optional inputs include `--seq-len`, `--clock-root` or `--outgroup`,
`--display-columns`, `--aa-gene`, `--aa-frame`, and
`--exclude-ngs-report-no`. Only the `default` metadata parser is currently
implemented.

The workflow requires at least two sequences after metadata/date filtering.
FASTA identifiers must match retained metadata identifiers exactly. A
conservative `prefix|metadata_id` suffix reconciliation is also supported.

### Wrapper: `run_alignments_and_phylo.sh`

The wrapper accepts either `--fasta` or `--fasta-dir`, and either `--metadata`
or `--metadata-dir`. It passes the original nucleotide FASTA and selected
metadata file to `run_phylo.sh`. It also accepts MAFFT and IQ-TREE executable
options and switches for skipping its standalone outputs, the amino-acid tree,
or the main phylogeny.

## Stage inventory

### 1. FASTA validation, metadata parsing, and filtering

Location: [`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Relevant shell functions and embedded Python blocks:

- `validate_fasta_and_collect_stats`
- `derive_dates_from_metadata`
- `reconcile_fasta_and_metadata_ids`
- `filter_fasta_by_dates`
- `export_retained_visualization_metadata`

Processing:

1. Validate FASTA records and collect length statistics.
2. Detect metadata identifier and date columns.
3. Normalize full, month-only, year-only, or decimal-year dates.
4. Skip samples with missing/unusable dates; optionally skip
   `NGS_Report=NO`.
5. Reconcile FASTA and metadata identifiers.
6. Write a new nucleotide FASTA containing only date-qualified sequences.
7. Retain selected metadata fields for later visualization.

Principal outputs under `OUTDIR`:

```text
qc/fasta_names.txt
qc/fasta_summary.tsv
qc/id_match_report.tsv
qc/sequences_with_dates.fasta
qc/sequence_filter_report.tsv
derived_metadata/dates_for_treetime.raw.tsv
derived_metadata/dates_for_treetime.tsv
derived_metadata/dates_with_audit.raw.tsv
derived_metadata/dates_with_audit.tsv
derived_metadata/parser_summary.tsv
derived_metadata/skipped_samples_missing_dates.tsv
derived_metadata/retained_visualization_metadata.tsv
derived_metadata/visualization_fields.tsv
```

The current `qc/qc_notes.txt` and
`qc/masking_rules.placeholder.txt` files explicitly reserve future QC and
masking behavior. No virus-specific sequence-quality filtering, trimming, or
site masking is currently implemented.

### 2. Nucleotide MAFFT alignment used by the phylogeny

Location: `run_mafft_alignment` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Input:

```text
qc/sequences_with_dates.fasta
```

Command shape:

```bash
mafft --auto qc/sequences_with_dates.fasta > qc/aligned_sequences.fasta
```

Output:

```text
qc/aligned_sequences.fasta
```

MAFFT is always run, even when the input FASTA appears aligned. This output is
the aligned nucleotide FASTA consumed by both nucleotide IQ-TREE and TreeTime.

### 3. Nucleotide IQ-TREE analysis

Location: `run_iqtree` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Input:

```text
qc/aligned_sequences.fasta
```

Command shape:

```bash
iqtree \
  -s qc/aligned_sequences.fasta \
  -m MFP \
  -alrt 1000 \
  -B 1000 \
  -nt AUTO \
  -pre iqtree/viral_phylogeny \
  -redo
```

The executable is auto-detected as `iqtree` or `iqtree3`. The selected
nucleotide substitution model is chosen by ModelFinder. The downstream primary
tree is:

```text
iqtree/viral_phylogeny.treefile
```

IQ-TREE also produces its normal log, report, checkpoint, consensus tree,
distance, model, split, and intermediate files under `iqtree/`. The exact
command is recorded in `iqtree/run_notes.txt`.

### 4. TreeTime clock analysis

Location: `run_treetime_clock`, `summarize_clock_outputs`, and
`choose_treetime_input_tree` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Inputs:

- `iqtree/viral_phylogeny.treefile`
- `derived_metadata/dates_for_treetime.tsv`
- an explicit `--seq-len`, or the inferred nucleotide alignment length
- the selected rerooting/outgroup arguments

Command shape:

```bash
treetime clock \
  --tree iqtree/viral_phylogeny.treefile \
  --dates derived_metadata/dates_for_treetime.tsv \
  --sequence-length <length> \
  <rooting arguments> \
  --outdir clock/
```

Principal outputs:

```text
clock/rerooted.newick
clock/root_to_tip_regression.pdf
clock/rtt.csv
clock/molecular_clock.txt
clock/outliers.tsv
clock/clock.stdout.log
clock/clock_summary.tsv
clock/clock_warnings.txt
```

The rerooted tree is preferred for the full timetree step. If it cannot be
found, the IQ-TREE tree is used instead.

### 5. TreeTime timetree, nucleotide mutations, and initial Auspice JSON

Location: `run_treetime_timetree` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Inputs:

- the rerooted clock tree, or the IQ-TREE tree as fallback
- `qc/aligned_sequences.fasta`
- `derived_metadata/dates_for_treetime.tsv`
- the selected rerooting/outgroup arguments

Command shape:

```bash
treetime \
  --tree <tree> \
  --aln qc/aligned_sequences.fasta \
  --dates derived_metadata/dates_for_treetime.tsv \
  <rooting arguments> \
  --outdir timetree/
```

Observed key outputs are:

```text
timetree/ancestral_sequences.fasta
timetree/branch_mutations.txt
timetree/auspice_tree.json
timetree/dates.tsv
timetree/divergence_tree.nexus
timetree/timetree.nexus
timetree/timetree.pdf
timetree/molecular_clock.txt
timetree/sequence_evolution_model.txt
timetree/outliers.tsv
timetree/timetree.stdout.log
```

TreeTime performs ancestral nucleotide reconstruction and supplies the
nucleotide branch mutations in the initial Auspice JSON. The workflow does not
run a separate custom nucleotide-mutation annotator.

### 6. Metadata enrichment of the Auspice JSON

Location: `export_retained_visualization_metadata` and
`augment_auspice_json_with_metadata` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh)

Inputs:

- `timetree/auspice_tree.json` from TreeTime
- `derived_metadata/retained_visualization_metadata.tsv`
- `derived_metadata/visualization_fields.tsv`

Behavior:

- Adds selected values to terminal-node `node_attrs`.
- Adds corresponding entries to `meta.colorings`.
- Adds categorical fields to `meta.filters`.
- Leaves internal nodes without this terminal sample metadata.

Outputs:

```text
timetree/auspice_tree.json                 # enriched in place
timetree/auspice_tree.treetime_raw.json    # backup before enrichment
timetree/auspice_metadata_report.tsv
```

The raw backup is created only when visualization fields are selected and the
JSON is actually augmented.

### 7. Custom amino-acid branch-mutation annotation

Locations:

- caller: `add_aa_mutations_to_auspice` in
  [`scripts/run_phylo.sh`](scripts/run_phylo.sh)
- implementation:
  [`scripts/add_aa_mutations_to_auspice.py`](scripts/add_aa_mutations_to_auspice.py)

Inputs:

- the metadata-enriched `timetree/auspice_tree.json`
- `timetree/ancestral_sequences.fasta`
- `--aa-gene` (default `HA`)
- `--aa-frame` (one fixed frame, default `0`)

Behavior:

1. Find the root nucleotide sequence in TreeTime's ancestral FASTA.
2. Walk the Auspice tree from root to tips.
3. Reconstruct each child sequence by applying the branch's TreeTime
   nucleotide mutations to its parent sequence.
4. Translate corresponding parent and child codons in the single selected
   frame.
5. Add non-ambiguous amino-acid changes to
   `branch_attrs.mutations.<gene>`.
6. Add a human-readable branch label under `branch_attrs.labels.aa`.
7. Add a simple CDS record to `meta.genome_annotations` if the gene is absent.

Outputs:

```text
timetree/auspice_tree.json                 # updated in place again
timetree/amino_acid_branch_mutations.tsv
```

Calls involving `X`, stop codons, malformed nucleotide mutation strings, or
out-of-range positions are omitted or counted in the report. This annotator
does not use a reference sequence, a feature annotation, or codon-aware
alignment. Its `--aa-frame` is one global frame for the run.

### 8. Standalone wrapper alignments and amino-acid IQ-TREE

Location: `write_translated_fasta`, `run_alignment_outputs`, and
`run_amino_acid_iqtree` in
[`scripts/run_alignments_and_phylo.sh`](scripts/run_alignments_and_phylo.sh)

For each input FASTA, the wrapper writes:

```text
alignments/<sample>/<sample>.nucleotide.aligned.fasta
alignments/<sample>/<sample>.amino_acid.aligned.fasta
amino_acid_iqtree/<sample>/<sample>.amino_acid.treefile
amino_acid_iqtree/<sample>/<sample>.amino_acid.*
```

Unless `--keep-temp` is used, the intermediate
`<sample>.amino_acid.unaligned.fasta` is deleted.

The translation logic:

1. Removes nucleotide gaps and several non-base placeholder characters.
2. Translates frames 0, 1, and 2 independently for each sequence.
3. Chooses the frame by minimizing, in order, internal stops, failure to start
   with methionine, ambiguous amino acids, total stops, and frame number.
4. Removes one terminal stop.
5. Aligns the independently translated proteins with MAFFT.

The amino-acid IQ-TREE command uses the same high-level settings as the
nucleotide tree (`-m MFP -alrt 1000 -B 1000 -nt AUTO`), but IQ-TREE selects an
amino-acid model because its input is protein sequence data.

This best-frame-per-sequence translation is used only for the separate
amino-acid alignment and amino-acid IQ-TREE tree. It is not reused by the
custom Auspice amino-acid mutation annotator, which instead uses TreeTime's
reconstructed nucleotide states and the one global `--aa-frame` value.

### 9. Additional visualization exports

After the main tree is complete, `run_phylo.sh` also calls:

- [`scripts/export_itol_annotations.py`](scripts/export_itol_annotations.py),
  which writes an iTOL tree and metadata color strips under `itol/`.
- [`scripts/export_microreact.py`](scripts/export_microreact.py), which writes
  a Newick tree and metadata CSV under `microreact/`.

Both use the nucleotide IQ-TREE tree rather than the dated TreeTime tree.

## Output layout when using the wrapper

For a sample named `H3N2`, the wrapper organizes results as:

```text
OUTDIR/
├── run_alignments_and_phylo_summary.tsv
├── alignments/H3N2/
│   ├── H3N2.nucleotide.aligned.fasta
│   `-- H3N2.amino_acid.aligned.fasta
├── amino_acid_iqtree/H3N2/
│   `-- H3N2.amino_acid.*
`-- phylo/H3N2/
    ├── qc/
    ├── derived_metadata/
    ├── iqtree/
    ├── clock/
    ├── timetree/
    ├── itol/
    `-- microreact/
```

The wrapper summary records the source FASTA, selected metadata, and each of
these result directories.

## Current alignment and translation assumptions

The inspection confirms the assumptions that motivate the planned Nextclade
work:

- Both nucleotide alignments are plain de novo MAFFT alignments.
- No reference genome or genome annotation is supplied to alignment.
- No codon-aware nucleotide alignment is performed.
- The standalone protein path chooses a frame independently per sequence after
  removing nucleotide gaps.
- The Auspice amino-acid path assumes one global coding offset over the entire
  TreeTime nucleotide alignment.
- The standalone protein alignment/tree does not feed IQ-TREE's nucleotide
  tree, TreeTime, or the Auspice amino-acid calls.
- Current sequence QC is validation- and metadata-focused; it does not identify
  biological frameshifts, partial coding regions, UTRs, or incompatible segment
  references.

These are observations about the existing implementation only; no workflow
behavior was changed while producing this inventory.
