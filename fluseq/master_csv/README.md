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
message. `true` enables merging using the defaults below or explicit overrides;
`false` explicitly disables updates. Validation runs always skip updates.

For now, place `NGS_PREP_INF_report.csv` in the same directory as `master.csv`.
Metadata defaults to that directory for both mounted files and SMB transfers.
No separate metadata location needs to be configured.

For mounted files:

```bash
export FLUSEQ_MASTER_UPDATE=true
export FLUSEQ_MASTER_CSV='/mnt/n/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv'
```

The mount path is an example and must match the server's mounts. For the
existing `smbclient` setup, enable the shared-directory defaults:

```bash
export FLUSEQ_MASTER_UPDATE=true
```

The master defaults to share `//pos1-fhi-svm01.fhi.no/styrt`, based on the existing
wrappers, and directory
`Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF`.
Metadata inherits the configured master share and directory. When the separate
export location is available, set `FLUSEQ_METADATA_CSV` for a mounted file, or
both `FLUSEQ_METADATA_SMB_SHARE` and `FLUSEQ_METADATA_SMB_DIR` for SMB (for example,
directory `Prod/FromSecure/LW_Datauttrekk` on the confirmed share). Explicit
metadata settings take precedence over the shared-directory default; unset any
old metadata path/share/directory overrides to use that default. Either CSV may
independently use a mounted path or SMB.

| Environment variable | Default / purpose |
| --- | --- |
| `FLUSEQ_MASTER_UPDATE` | `auto`, `true`, or `false` |
| `FLUSEQ_MASTER_CSV` | Mounted master path; overrides master SMB settings |
| `FLUSEQ_METADATA_CSV` | Defaults beside the mounted master unless a metadata SMB share is set; an explicit path overrides metadata SMB settings |
| `FLUSEQ_MASTER_SMB_SHARE` | `//pos1-fhi-svm01.fhi.no/styrt` |
| `FLUSEQ_MASTER_SMB_DIR` | Master directory above |
| `FLUSEQ_MASTER_SMB_NAME` | `master.csv` |
| `FLUSEQ_METADATA_SMB_SHARE` | Same share as the master unless overridden |
| `FLUSEQ_METADATA_SMB_DIR` | Same directory as the master unless overridden |
| `FLUSEQ_METADATA_SMB_NAME` | `NGS_PREP_INF_report.csv`; also used beside a mounted master |
| `FLUSEQ_MASTER_SMB_AUTH` | `/home/ngs/.smbcreds` |
| `FLUSEQ_METADATA_SMB_AUTH` | Same as master auth unless overridden |
| `FLUSEQ_MASTER_NONEMPTY_REPORT` | `false`; set `true` to preserve old values for empty report cells |
| `FLUSEQ_MASTER_TOOLS` | Wrapper directory's `master_csv` subdirectory |
| `FLUSEQ_QC_COVERAGE_THRESHOLD` | `80`; coverage percentage used by the wrapper's HTML QC report |

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

Deploy the entire `master_csv/` directory along with the wrappers. It now also
contains `bin/report_qc_html.py`, `bin/qc_metrics.py` and
`bin/templates/report_qc.html`. If `FLUSEQ_MASTER_TOOLS` points elsewhere, that
directory must contain these reporting files as well. The HTML renderer extends
the initial renderer in `nf-core-fluseq`; this bundled version is run after the
master merge so the qPCR comparison includes newly imported metadata.

## HTML QC after merging

The wrappers pass `--qc-output /path/to/<RUN>_qc.html` to `update_master_csv.py`.
After a successful merge, the helper generates an offline HTML report and a
companion JSON from the current run CSV and the updated master. For SMB, it uses
the same verified candidate that was uploaded; a no-change retry still rebuilds
the report. With master updates disabled, a report is generated without qPCR
comparison. Validation continues to skip master writes.

Only identifiers and qPCR result fields from matched master rows enter the
report. Current coverage, mixed sites, indels, noise and final calls always come
from the current run CSV, so older measurements retained in the master cannot
make a failed current measurement appear successful. FASTQ matches `Sample` to
`NGS_LW_ID`; FASTA matches `OriginalName` to `Key`. Duplicate join identifiers are
rejected rather than matched arbitrarily.

`Påvist` in a subtype-specific PCR result field is positive (case-insensitive,
trimmed). H1, H3 and H5 compare the H component of a called subtype; B/Victoria
and B/Yamagata compare lineage. Missing, negative-only, multiple-positive and
unrecognised qPCR results have separate statuses. They are not counted as a
subtype mismatch. A missing sequencing call is also shown separately.

Success means a recognised final `Sekvens_Resultat`, independent of other QC
flags. All current-report sample rows enter the denominator, including no calls;
no controls are automatically excluded. Segment outcomes are coverage ≥80%,
coverage <80%, or missing/invalid. The metric is the existing consensus non-N
percentage, not mean sequencing depth or full-reference breadth; missing values
are never treated as passes. Mixed-site counts >4 and IRMA noise >0.09 prompt
review. HA1/HA2 and M1/M2 duplicate segment counts are not summed. The source
`NGS_QC_Sum`, including its older mixed-site rule, remains visible and unchanged.

The optional `--qc-smb-share`, `--qc-smb-dir` and `--qc-smb-auth` arguments upload
and verify the HTML and JSON. The wrappers send them to the run's shared
`reporthuman` directory (or the validation report directory). A report/upload
failure exits non-zero and retains local report files. The master merge may
already have completed; retrying the same merge/report is safe.

To rebuild a report without a master write, use the standalone renderer:

```bash
python3 master_csv/bin/report_qc_html.py /path/to/run.csv \
  --master /path/to/master.csv --outdir /path/to/reporthuman
```

Add `--workflow fasta` when appropriate. The standalone renderer accepts
`--coverage-threshold`, `--mixed-threshold` and `--noise-threshold`. Its optional
`--qpcr-column` explicitly selects a column containing subtype labels instead of
the default assay result fields. Changing a reporting threshold never changes
the source CSV or the master.

## Writes and recovery

If a merge reports `NGS_LW_ID maps to multiple master Keys`, it stopped before
replacing the master. The same sequencing ID points to different `Key` values in
the master, different `RekvNr` values in the metadata, or conflicting values
across the two files. The check covers the whole inputs, including older samples
outside the current report. It deliberately does not choose which record to keep.

With the same exported location settings, audit the identifiers without any
master/metadata changes or remote writes:

```bash
FLUSEQ_MASTER_UPDATE=true python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/update_master_csv.py \
  --workflow fastq --check-identifiers \
  --report /home/ngs/out_fluseq/INF109/reporthuman/INF109.csv \
  --identifier-report /home/ngs/INF109_identifier_conflicts.csv
```

The diagnostic CSV lists each conflicting sequencing ID, its source (`master`
or `metadata`), key, record number and whether it is involved in the supplied
run report. Record numbering starts at 2 after the header and excludes blank
records; quoted multiline cells count as one record. Only identifiers are
exported, with owner-only file permissions. Standard output shows counts rather
than identifiers. Exit code 2 means conflicts were found; 0 means this check
found none. Other merge validations can still fail independently.

Resolve the source identifiers against the lab records before retrying just the
merge using the command above under Wrapper configuration. Existing analysis
and uploaded results can be reused. Older rows whose key happens to equal their
sequencing ID are not automatically treated as provisional: only rows carrying
`Master_Key_Source=Sample` are eligible for the documented provisional rekeying.

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

From the wrapper checkout, test metadata location defaults and overrides with
synthetic CSVs and mocked SMB transfers:

```bash
pytest -q tests/test_master_csv_configuration.py tests/test_master_csv_identifiers.py tests/test_qc_report.py
```

Live shared-drive access and the real LabWare/master exports still require a
server-side acceptance run with the metadata file beside the master.
