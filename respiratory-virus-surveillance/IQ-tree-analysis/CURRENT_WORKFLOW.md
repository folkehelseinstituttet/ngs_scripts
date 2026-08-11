# Current workflow inventory

This document records the current workflow, including the optional Nextclade
alignment/QC path and its per-CDS amino-acid IQ-TREE outputs. It describes
current inputs, processing steps, outputs, and the places in the code
responsible for each step.

## Entrypoints

There are two shell entrypoints:

1. [`scripts/run_phylo.sh`](scripts/run_phylo.sh) is the main phylogeny
   workflow. It validates and filters the inputs, runs MAFFT or Nextclade,
   builds the primary nucleotide IQ-TREE, runs TreeTime, and enriches
   TreeTime's Auspice JSON. Nextclade mode also builds supplementary per-CDS
   amino-acid IQ-TREEs.
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
+---> scripts/run_phylo.sh
        |
        +-- validate FASTA and parse metadata/dates
        +-- reconcile identifiers and remove sequences without retained dates
        +-- MAFFT alignment (default) OR Nextclade alignment plus QC filtering
        |     `qc/aligned_sequences.fasta` is the accepted nucleotide alignment
        +-- IQ-TREE nucleotide maximum-likelihood tree (primary backbone)
        +-- [Nextclade only] filter each CDS translation to the same accepted IDs
        |     and build one supplementary amino-acid IQ-TREE per CDS
        +-- TreeTime clock analysis using the IQ-TREE nucleotide tree and dates
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
`--display-columns`, `--aa-gene`/`--aa-frame`, `--exclude-ngs-report-no`, and
`--alignment-method mafft|nextclade` with the Nextclade dataset/reference
options. `--include-nextclade-failed` is an explicit opt-in to retain sequences
with non-good Nextclade QC status. Only the `default` metadata parser is
currently implemented.

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

Principal outputs under `OUTDIR` include the curated master tree folder:

```text
master/README.txt
master/manifest.tsv
master/nucleotide/nucleotide_iqtree.treefile
master/nucleotide/nucleotide_treetime_auspice.json
master/amino_acid/<CDS>/<CDS>_amino_acid_iqtree.treefile  # Nextclade mode

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
masking behavior. In Nextclade mode, Nextclade QC is the only sequence-status
filter unless `--include-nextclade-failed` is supplied; no additional virus-
specific trimming or site masking is currently implemented.

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

### 3. Nextclade alignment, QC, and amino-acid IQ-TREEs (optional)

Location: `run_nextclade_alignment` and `run_nextclade_amino_acid_iqtree` in
[`scripts/run_phylo.sh`](scripts/run_phylo.sh), with the amino-acid runner in
[`scripts/run_nextclade_amino_acid_iqtree.py`](scripts/run_nextclade_amino_acid_iqtree.py).

When `--alignment-method nextclade` is selected, Nextclade runs on the
date-qualified nucleotide FASTA. Its aligned nucleotide output is filtered by
QC unless `--include-nextclade-failed` is set, then copied to
`qc/aligned_sequences.fasta`. The matching dates are written to
`derived_metadata/dates_for_treetime.nextclade.tsv`.

Nextclade translations are read from `.nextclade_raw/`, sorted deterministically,
and filtered to the exact accepted nucleotide IDs. One IQ-TREE is built per CDS
under `amino_acid_iqtree/<CDS>/`; `amino_acid_tree_summary.tsv` records commands,
versions, paths, counts, lengths, and support mode. The nucleotide IQ-TREE remains
the primary backbone, and these amino-acid trees are not passed to TreeTime.

After the nucleotide and (when applicable) amino-acid analyses finish,
`publish_master_results` writes curated copies under `OUTDIR/master/`. The
master folder contains `nucleotide/nucleotide_iqtree.treefile`,
`nucleotide/nucleotide_treetime_auspice.json`, the accepted nucleotide
alignment and dates, plus per-CDS amino-acid IQ-TREEs and alignments under
`amino_acid/<CDS>/`. `manifest.tsv` maps each curated file to its detailed
source. AA IQ-TREEs do not currently have dated amino-acid Auspice outputs.

### 4. Nucleotide IQ-TREE analysis

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

### 5. TreeTime clock analysis

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

### 6. TreeTime timetree, nucleotide mutations, and initial Auspice JSON

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

### 7. Metadata enrichment of the Auspice JSON

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

### 8. Custom amino-acid branch-mutation annotation

Locations:

- caller: `add_aa_mutations_to_auspice` in
  [`scripts/run_phylo.sh`](scripts/run_phylo.sh)
- implementation:
  [`scripts/add_aa_mutations_to_auspice.py`](scripts/add_aa_mutations_to_auspice.py)

Inputs:

- the metadata-enriched `timetree/auspice_tree.json`
- `timetree/ancestral_sequences.fasta`
- `--aa-gene` (explicit opt-in; disabled by default)
- `--aa-frame` (one fixed frame, default `0`, used only with `--aa-gene`)

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

### 9. Amino-acid IQ-TREE analyses

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

### 10. Additional visualization exports

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

The inspection confirms these alignment and translation assumptions:

- Both nucleotide alignments are plain de novo MAFFT alignments.
- No reference genome or genome annotation is supplied to alignment.
- No codon-aware nucleotide alignment is performed.
- The standalone protein path chooses a frame independently per sequence after
  removing nucleotide gaps.
- When explicitly enabled, the Auspice amino-acid path assumes one global coding
  offset over a single-CDS TreeTime nucleotide alignment; it is disabled by
  default for whole-genome or multi-CDS alignments.
- The standalone protein alignment/tree does not feed IQ-TREE's nucleotide
  tree, TreeTime, or the Auspice amino-acid calls.
- Current sequence QC is validation- and metadata-focused; it does not identify
  biological frameshifts, partial coding regions, UTRs, or incompatible segment
  references.

The nucleotide IQ-TREE remains the primary backbone for both alignment modes;
Nextclade per-CDS amino-acid trees are supplementary and are not used by
TreeTime.
