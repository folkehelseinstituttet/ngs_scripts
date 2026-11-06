# Sequence Review approval filter

The master-based INF and SC2 exporters require a **current Approved review** in
the Sequence Review solution, in addition to their existing metadata/QC filters.
An `NGS_QC_Assessment` cell or a passing QC report is not an approval. There is no
option to bypass this requirement.

For each master, the exporters read this existing dataset layout:

```text
data/INF/                    # or data/SC2/
  config.json
  master.csv
  master.fasta
  reviews/
    <review event>.json
```

`config.json` and `reviews/` must come from the solution, beside the master being
exported. They are never created or modified by the exporter. Both R submission
exporters use `approval.R` directly and require the R packages `jsonlite` and
`digest`; no Node.js or Python installation is needed:

```r
install.packages(c("jsonlite", "digest"))
```

This reader uses local/mounted/UNC filesystem access; it does not fetch via SMB
credentials, contact a server, or upload anything to GISAID. R errors include the
underlying cause, such as a missing `config.json` or unreadable `reviews/`.
Failures do not write a submission.

The archived [Python SC2 exporter](../sars-cov-2/archive/sc2_gisaid_csv.py)
uses the JavaScript reader and needs
Node.js 18+; `GISAID_NODE` can point to its executable. The R exporters do not use
that variable. Use `sc2_gisaid_csv.R` for the R-only SC2 workflow.

The reader uses the same configuration, identifier, fingerprint and review-history
rules as the solution. Only a single current history head with assessment exactly
`Approved` passes. Pending, outdated, conflicting, rejected and follow-up rows
are excluded. Approval is evaluated against the original full master row before
filtering, repairing text or applying overrides. Changes to reviewed contents
invalidate the old approval according to the solution's existing hash policy.
Dates/filenames are never used to pick a newer decision or resolve a conflict.
Configured composite identifiers and legacy identifier migration are supported.

Current approved manual overrides are applied before the exporter-specific
metadata filters. This includes an approved GISAID hold comment and manually
corrected metadata. Original identifiers are also retained separately for FASTA
matching and ambiguity checks against the full master. Missing/unreadable config
or history, malformed events, unknown policies, invalid identifiers and corrupt
history fail the export instead of treating all rows as approved.

The reader verifies that inputs did not change while loading. Both exporters
check the complete master/config/review snapshot token again before writing
submission files. This detects changes during preparation; it does not lock out
reviews after export. Regenerate a submission after any subsequent result or
review changes. The source reader retains the solution's limits: 32 MiB master,
50,000 rows, 1,000 columns, 20,000 review events and 256,000 bytes per event/config.

## Reader provenance

`sequence_review_core.cjs` is an unchanged copy of `client/review/core.js` from
the local `nextstrain_local` solution working tree inspected for this integration.
That source had uncommitted changes; it is identified by content, not a claim that
the file matches the repository's HEAD:

```text
SHA-256: fc07727236cf9798e84fe3730730aa98e663829fcdcdec95a38abe921a033e16
```

`approved_master.cjs` adds read-only filesystem loading, approved-row selection,
snapshot checks and machine-readable output. It remains the JavaScript reference
and the reader used by the archived Python SC2 exporter. No npm packages are required.

`approval.R` independently implements these read-only rules in R, including
JavaScript-compatible UTF-16 sorting, exact UTF-8 JSON row fingerprints, and the
same byte-based master/config/review snapshot token. It validates the ISO 8601
timestamps stored by Sequence Review. Tests compare both readers on synthetic
Unicode, quoted CSV, approval histories, composite keys, legacy migration and
invalid inputs. `read_approved_master(master, pathogen)` returns approved rows;
`assert_approved_master(master, pathogen, token)` rechecks before writing.
The R snapshot also includes `original_rows`, the full master before selection
or overrides. Nextstrain's R input scripts use it to retain all original FASTA
aliases and detect ambiguity with excluded samples. This field does not grant
approval to excluded rows. Both Nextstrain scripts use these same R approval
checks before their existing metadata filters and recheck before writing.

If the solution's review format/policy changes,
update both readers deliberately and rerun the approval/export tests.

```bash
pytest -q gisaid/tests
```

Tests require Python, Node.js (for the frozen reference/old Python exporter),
and R with the documented exporter packages. Node.js is a test dependency only
for the R workflows. Tests use synthetic rows, review events and short
placeholder FASTA records. They never submit sequences or read production data.

`sc2_metadata.py` contains the Python metadata helpers used by the accession
importer, deployment validator and archived Python exporter. These utilities
remain independent of the archived entry script. The routine R exporters do
not load this Python module.
