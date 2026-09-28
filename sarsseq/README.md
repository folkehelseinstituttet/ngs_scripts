
Run the wrapper with: bash /home/ngs/ngs_scripts/sarsseq/sarsseq_wrapper.sh -r TEST_SAR -a sars -p V5.4.2 -s Ses2425 -y 2025

Replace TEST with a run name (e.g. SAR002)

If running a verification of script add -v VER flag nad run with -p V4.1

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
