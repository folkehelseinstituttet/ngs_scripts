# Running the avian FASTA workflow on ngs4

## Start the workflow

1. Export a FASTA file containing the avian sequences—all eight segments, if
   available—to its own folder under:

   ```text
   N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\12-Export\2026
   ```

2. Log in to ngs4 and change to the `ngs` user.

   Log in to ngs4:

   ```bash
   az ssh arc --subscription "FILL IN" --resource-group "FILL IN" --name "up-ngs-4"
   ```

   Change user to `ngs`:

   ```bash
   sudo -u ngs /bin/bash
   ```

   Navigate to `$HOME`:

   ```bash
   cd "$HOME"
   ```

3. Start the wrapper script:

   ```bash
   bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh \
     -r RUNNAME \
     -a avian \
     -s SesXXXX \
     -y YEAR
   ```

   Arguments:

   - `RUNNAME`: Name of the folder containing the FASTA file on the `N:` drive.
   - `XXXX`: Season number, for example `2526`.
   - `YEAR`: Folder on the `N:` drive where results will be saved, for example
     `2026` or `2025`.

   Example:

   ```bash
   bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh \
     -r 20260915TEST \
     -a avian \
     -s Ses2526 \
     -y 2026
   ```

## What the workflow does

The workflow analyses existing consensus sequences in FASTA format. It
organises records by sample, assesses sequence completeness, generates
classifications and annotations, and combines results into reports. It does not
assemble consensus sequences from raw reads.

## Software requirements

The current wrapper depends on:

- Bash and `flock`
- Conda, with an environment named `NEXTFLOW`
- Nextflow and Docker
- Git, Python 3, and Perl
- `smbclient` and access to the configured network share
- Locally available helper scripts and reference resources

> **Current status:** Shell checks passed, but the complete workflow remains
> unverified. Version pinning, shared-reference isolation, and upload recovery
> remain unresolved. Validation mode uploads report CSVs; it is not a dry run.

## What each module does

### Sample organisation

| Module | Purpose |
| --- | --- |
| `EMIT_FASTA_RECORD` | Writes individual sequence records with internal identifiers. |
| `WRITE_ID_MAP` | Records the relationship between internal identifiers and original sample names. |
| `REHEADER_TO_UID` | Standardises selected sequence headers using internal identifiers. |
| `FASTA_CONFIGURATIONFASTA` | Prepares sequence formats for the different analysis tools. |
| `REFERENCE_PROVENANCE` | Records reference-file checksums for traceability. |

### Quality and classification

| Module | Purpose |
| --- | --- |
| `SEGMENTIFENTIFIER` | Identifies influenza genome segments. |
| `SUBTYPEFINDER` | Produces subtype assignments and supporting status information. |
| `COVERAGE` | Assesses consensus-sequence completeness; this differs from sequencing read depth. |
| `GENOTYPING` | Produces reference-based genotype assignments. |
| `NEXTCLADE` | Produces clade assignments and sequence-analysis summaries. |
| `REASSORTMENT` | Summarises evidence about differences in segment ancestry. |
| `GENIN2` | Produces an additional genotype assessment. |

### Biological annotations

| Module | Purpose |
| --- | --- |
| `AMINOACIDTRANSLATION` | Produces protein-sequence representations. |
| `MUTATION` | Produces annotations from comparisons with reference sequences. |
| `TABLELOOKUP` | Adds reference annotations concerning antiviral resistance. |
| `TABLELOOKUP_MAMMALIAN` | Adds reference annotations concerning mammalian adaptation. |
| `FLUMUT` | Produces influenza marker annotations and associated literature information. |

### Reporting

| Module | Purpose |
| --- | --- |
| `FLUMUT_CONVERSION` | Converts FluMut output into the pipeline's reporting format. |
| `SLIM_GENIN2_REPORT` | Selects GENIN2 columns used in combined reporting. |
| `SURVEILLANCE_SUMMARY` | Combines quality, classification, and annotation evidence into structured summaries. |
| `REPORTAVIANFASTA` | Builds the combined avian FASTA CSV report. |

For detailed column descriptions, see the
[avian FASTA report column dictionary](https://github.com/RasmusKoRiis/nf-core-fluseq/blob/infrastructure/docs/avian_fasta_report_columns.md).
