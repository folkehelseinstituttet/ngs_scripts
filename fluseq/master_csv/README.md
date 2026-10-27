# Master CSV merge

`bin/merge_master_csv.py` merges a completed human FASTQ or FASTA report and the
LabWare export into an existing master CSV. It requires Python 3.8 or newer and
uses only the standard library. `bin/update_master_csv.py` is the wrapper entry
point and supports mounted files and `smbclient` transfers.

The merge is a wrapper post-processing step, after Nextflow and the existing
result uploads succeed. It is outside Nextflow's cache: each invocation reads the
current master. The wrappers pass only `reporthuman/<run-id>.csv`, not a wildcard
of CSVs from previous runs. Validation runs (`-v`) skip master updates.

## Identifiers and mappings

The three XML files in `assets/master_csv/` are copies of the supplied import
templates. The merge decodes their Base64 field names and applies their direct
field mappings. Unsupported parsing/default rules fail explicitly.

| Input | Identifier rule |
| --- | --- |
| Existing master | `Key` identifies one row |
| LabWare metadata | `RekvNr` becomes master `Key`, as specified by `LABWAREDIRECT.xml` |
| FASTQ report | `Sample` becomes `NGS_LW_ID`; join this to metadata or existing master `NGS_LW_ID` to obtain `Key`; unmatched samples use `Sample` as a provisional `Key` |
| FASTA report | `OriginalName` becomes master `Key`; `SampleID` is retained as an extra field |

No identifier is converted to a number, split, or approximately matched. Leading
zeros remain intact. Samples without matching metadata are still included, with
their report values and blank metadata-only fields for new rows. Previously
stored metadata on existing rows is preserved. The summary counts samples with
no matching metadata row as `without_metadata`. A FASTA record supplies its key
through `OriginalName`. An unmatched FASTQ record uses `Sample` as both its
provisional `Key` and `NGS_LW_ID`, with an additional `Master_Key_Source=Sample`
field recording this choice. When metadata becomes available for that sequencing
ID in a later report merge, the same row is updated to its `RekvNr` key and
`Master_Key_Source=RekvNr`; existing values are preserved according to the update
rules below. Unrelated samples are not re-keyed. `Master_Key_Source` is reserved
for this provenance and must not appear in metadata or report inputs.

If a provisional key would collide with an unrelated existing key, or its later
`RekvNr` resolves to another existing row, the merge stops for resolution rather
than overwriting or combining ambiguous records. Duplicate keys, ambiguous
sequencing IDs, and conflicting source columns that map to the same destination
stop the merge before master replacement.

Only samples present in the current report are added or updated. Metadata-only
rows do not create master entries, and existing samples outside the report retain
their values. For a sample in the report, precedence is:

1. Existing master values.
2. Non-empty values from matching metadata.
3. Values from columns present in the new analysis report, including empty cells.

Report columns absent from the new report retain their existing values. This
allows FASTA updates to preserve FASTQ-specific measurements. The literal text
`NA`, `None`, or `0` in data cells is retained and can replace an old value; it is
not interpreted as a blank. To preserve old analysis values for empty report
cells as well, pass `--nonempty-report`, or set
`FLUSEQ_MASTER_NONEMPTY_REPORT=true` for wrappers.

The first 193 columns follow the exact requested order in
`assets/master_csv/columns.txt`. XML destinations are matched to their canonical
spellings without case sensitivity. In particular, `Pasient_Kjonn` and
`PASIENT_KJONN` map to the requested `Pasient_Kjnn`, and `Prove_Maanad` /
`PROVE_MANAD` map to the requested `Prove_M nad`.

Mapped fields use their master names. Unmapped and XML `__None__` fields are
retained with their original names, including future metadata/report columns.
The metadata export's original `Key` is retained as `Metadata_Key` because its
XML uses `RekvNr` as the master key. Both `Prove_Sesong` and `Sesong` map to
`Prove_Sesong`; differing non-empty values are rejected rather than guessed.
Both report spellings `Coverage-M` and `Coverage-MP` map to `NGS_Coverage_M`.
No biological interpretation is performed, and no mappings beyond the supplied
templates and these spelling aliases are inferred.

## Preview and manual updates

Use local or mounted paths. CSV input can use semicolons, commas, or tabs.
Automatic decoding handles UTF-8 (with or without BOM), UTF-16 with BOM, and
Windows-1252. `--encoding` overrides decoding when necessary. Output is
semicolon-separated UTF-8 with BOM and proper CSV quoting.

```bash
python3 bin/merge_master_csv.py \
  --workflow fastq \
  --report /path/to/reporthuman/INF077.csv \
  --metadata /path/to/NGS_PREP_INF_report.csv \
  --master /path/to/master.csv \
  --output /path/to/master.preview.csv
```

The preview leaves the master unchanged and requires a new output filename.
Omit `--output` to update the master with a timestamped backup. Use
`--workflow fasta` for the FASTA report. A first master may contain only the
header `Key`; missing files are rejected to avoid creating a new database after
a download/path error.

## Wrapper configuration

The updated `ngs_scripts/fluseq/fluseq_wrapper.sh` and
`ngs_scripts/fluseq/fluseq_fasta_wrapper.sh` use a bundled copy under
`ngs_scripts/fluseq/master_csv/`. `FLUSEQ_MASTER_TOOLS` can instead point to a
pipeline checkout containing `bin/` and `assets/master_csv/`.

The default `FLUSEQ_MASTER_UPDATE=auto` enables merging when a master/metadata
location is configured. With no configuration, the wrapper prints a clear skip
message. `true` requires configuration and fails if it is missing; `false`
explicitly disables updates. Validation runs always skip updates.

For mounted files:

```bash
export FLUSEQ_MASTER_UPDATE=true
export FLUSEQ_MASTER_CSV='/mnt/n/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv'
export FLUSEQ_METADATA_CSV='/confirmed/mount/Prod/FromSecure/LW_Datauttrekk/NGS_PREP_INF_report.csv'
```

Those mount paths are examples and must match the server's mounts. For the
existing `smbclient` setup, configure the metadata share once its actual UNC
location is known:

```bash
export FLUSEQ_MASTER_UPDATE=true
export FLUSEQ_METADATA_SMB_SHARE='//confirmed-server/confirmed-share'
export FLUSEQ_METADATA_SMB_DIR='Prod/FromSecure/LW_Datauttrekk'
```

The master defaults to share `//pos1-fhi-svm01.fhi.no/styrt`, based on the existing
wrappers, and directory
`Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF`.
The metadata share is deliberately not inferred from the Windows drive letter.
Either CSV may independently use a mounted path or SMB.

| Environment variable | Default / purpose |
| --- | --- |
| `FLUSEQ_MASTER_UPDATE` | `auto`, `true`, or `false` |
| `FLUSEQ_MASTER_CSV` | Mounted master path; overrides master SMB settings |
| `FLUSEQ_METADATA_CSV` | Mounted metadata path; overrides metadata SMB settings |
| `FLUSEQ_MASTER_SMB_SHARE` | `//pos1-fhi-svm01.fhi.no/styrt` |
| `FLUSEQ_MASTER_SMB_DIR` | Master directory above |
| `FLUSEQ_MASTER_SMB_NAME` | `master.csv` |
| `FLUSEQ_METADATA_SMB_SHARE` | Must be supplied for metadata over SMB |
| `FLUSEQ_METADATA_SMB_DIR` | `Prod/FromSecure/LW_Datauttrekk` |
| `FLUSEQ_METADATA_SMB_NAME` | `NGS_PREP_INF_report.csv` |
| `FLUSEQ_MASTER_SMB_AUTH` | `/home/ngs/.smbcreds` |
| `FLUSEQ_METADATA_SMB_AUTH` | Same as master auth unless overridden |
| `FLUSEQ_MASTER_NONEMPTY_REPORT` | `false`; set `true` to preserve old values for empty report cells |
| `FLUSEQ_MASTER_TOOLS` | Wrapper directory's `master_csv` subdirectory |

Export these settings in the server's existing launch environment. The early
`--check-config` hook checks local paths/settings before analysis; remote access
is checked during the actual merge. Failed merges return a non-zero status and
prevent the wrapper from reporting completion. Already generated reports remain
available for retry. To retry only the merge with the same exported settings:

```bash
python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/update_master_csv.py \
  --workflow fastq \
  --report /home/ngs/out_fluseq/INF077/reporthuman/INF077.csv
```

When maintaining the helper from this pipeline checkout, refresh its standalone
bundle along with the wrapper changes:

```bash
bundle=/path/to/ngs_scripts/fluseq/master_csv
mkdir -p "$bundle/bin" "$bundle/assets/master_csv"
cp bin/merge_master_csv.py bin/update_master_csv.py "$bundle/bin/"
cp assets/master_csv/* "$bundle/assets/master_csv/"
cp docs/master_csv.md "$bundle/README.md"
```

## Writes and recovery

An exclusive `master.csv.lock` directory serializes participating writers across
hosts. The helper reads the latest master under this lock, validates the inputs,
creates a candidate, and makes a uniquely named `master.csv.bak.<timestamp>.<id>`
backup before replacing the master. Local/mounted replacement uses `os.replace`.
SMB uploads both backup and candidate to new names, verifies them by downloading
and comparing SHA-256 hashes, checks that the master has not changed, then uses
server-side `rename ... -f` and verifies the result. The SMB server must support
rename with replacement. There is no delete-then-upload fallback.

Repeated identical merges do not add duplicate rows or rewrite an identical
master. Backups are retained; no automatic retention/deletion policy is applied.
Temporary downloads are kept in a private directory and removed on normal exit.
Failed SMB writes may leave uniquely named `.tmp.*` or `.bak.*` files on the share.

The lock coordinates this helper, not unrelated spreadsheet users or other
importers. Other writers should use the same lock or run at separate times.
Concurrent edits detected by the hash check abort the merge. After a process is
killed, check that no merge is still active before removing a stale lock
directory. If a network disconnect occurs during replacement, inspect the master
and its verified backup before retrying; a retry is safe once identifiers and
access are valid.

Tests use synthetic CSVs and simulated SMB failures:

```bash
pytest -q tests/test_master_csv.py
```

Live shared-drive access and the real LabWare/master exports still require a
server-side acceptance run after the metadata share is confirmed.
