# Reference names and EPI identifiers

The human FASTQ wrapper checks every record in each `.fasta` file against the
seasonal `reference_table.csv` before starting Nextflow. Both the strain name
and the EPI identifier must match. The header format is:

```text
>A/Example/1/2025|EPI_ISL_123456_HA1
```

Keep the segment suffix last. Existing aliases such as `_NS` in `NS1.fasta`
and `_SIGPEP` in `SigPep.fasta` are accepted. The pipeline's mutation-reference
formatter removes that suffix and preserves `A/Example/1/2025|EPI_ISL_123456`.
Reference names using underscores instead of slashes are accepted by validation.

The semicolon-delimited table must contain these columns:

```text
Subtype;Reference;Type;GISAID_EPI
H1N1;A/Example/1/2025;human;EPI_ISL_123456
```

UTF-8 BOMs, Windows line endings, and leading/trailing whitespace (including
nonbreaking spaces) are accepted. Duplicate subtype/type rows, missing or
invalid EPI IDs, mismatched names, incorrect segment suffixes, missing subtype
directories, and empty reference files cause validation to fail.

## Check a bundle without starting a run

After extracting a reference ZIP, pass the directory containing `human/`:

```bash
bash fluseq_wrapper.sh --check-references /path/to/references /path/to/reference_table.csv
```

This mode requires only Bash and Python 3 (standard library). It runs before
conda activation and does not download files, access SMB, update Git, or run
Nextflow. No run, season, or year arguments are needed. A successful check
returns exit status 0; a validation failure returns 1.

Vaccine bundles can be checked explicitly:

```bash
bash fluseq_wrapper.sh --check-references /path/to/references /path/to/reference_table.csv human_vaccine
```

Automatic vaccine validation remains disabled in the routine wrapper because
the supplied September 2026 archive contains an empty `human_vaccine/` folder.
Enable that call once a complete EPI-annotated vaccine bundle is available.

Deploy the updated human references and wrapper together: the new check rejects
legacy headers without EPI identifiers. The `references_with_epis.zip` archive
retains the top-level `references/` directory and the original layout. Restore
`references/human/` into the existing human reference location. The EPI IDs come
from the supplied table; the update changes headers only. The accompanying
`references_epi_audit.tsv` records old/new headers and SHA-256 hashes of unchanged
sequence bytes. The supplied ZIP and table are retained untouched.

Validation establishes agreement between headers and the table. It does not
verify sequences against GISAID or establish that every expected segment is
present.

## Regression tests

From the directory containing the wrapper:

```bash
python3 -m pytest -q tests/test_reference_validation.py
bash -n fluseq_wrapper.sh
```

The tests use invented short records and only the offline checking mode.
