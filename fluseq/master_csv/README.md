# Master CSV merge

`bin/merge_master_csv.py` merges a completed human FASTQ or FASTA report and the
LabWare export into an existing master CSV. It requires Python 3.8 or newer and
uses only the standard library. `bin/update_master_csv.py` is the wrapper entry
point and supports mounted files and `smbclient` transfers. Its `--profile avian`
mode also archives completed avian FASTA reports; Excel metadata requires the
optional dependencies described below.

The merge is a wrapper post-processing step, after Nextflow and the existing
result uploads succeed. It is outside Nextflow's cache: each invocation reads the
current master. The wrappers pass only `reporthuman/<run-id>.csv`, not a wildcard
of CSVs from previous runs. They also pass `reporthuman/<run-id>.fasta` to update
the master FASTA archive. Validation runs (`-v`) skip both master updates.

## Identifiers and mappings

The three XML files in `assets/master_csv/` are copies of the supplied import
templates. The merge decodes their Base64 field names and applies their direct
field mappings. Unsupported parsing/default rules fail explicitly.

| Input | Identifier rule |
| --- | --- |
| Existing master | `Prove_LW_ID` identifies one row and must be non-empty and unique; `Key` remains an ordinary data column |
| LabWare metadata | `Prove_LW_ID` supplies the specimen index; the XML still maps `RekvNr` to the legacy `Key` data column |
| FASTQ report | `Sample` becomes `NGS_LW_ID`; join the sequencing ID to metadata or the existing master to find `Prove_LW_ID` |
| FASTA report | Resolve `OriginalName` against exact `Prove_LW_ID`, legacy `Key`, or previously stored `OriginalName`/`SampleID`; sequencing identifiers can also identify the row |

No identifier is converted to a number, split, or approximately matched. Leading
zeros remain intact. Samples without matching metadata are still included, with
their report values and blank metadata-only fields for new rows. Previously
stored metadata on existing rows is preserved. The summary counts samples with
no matching metadata row as `without_metadata`.

When `Prove_LW_ID` is missing, use the sequencing ID as its provisional value and
record `Master_Index_Source=Sequence_ID`. The sequencing ID is the first usable
value in `NGS_LW_ID`, `Sequence_ID`, `SequenceID`, or `SampleID`, in that order.
In FASTQ reports this is normally `Sample`, mapped to `NGS_LW_ID`; an unmatched
FASTA report normally supplies `SampleID`. An unresolved FASTA record with only
`OriginalName` needs a sequencing ID before it can be inserted. Missing IDs include
blank cells and `NA`, `N/A`, `NaN`, `None`, `NULL`, or `-`, ignoring case.

Existing rows with missing `Prove_LW_ID` are filled using unambiguous metadata
matches (sequencing ID, then legacy identifiers) or the sequencing fallback.
When metadata supplies the actual specimen ID for a marked fallback, the same
row is reindexed and marked `Master_Index_Source=Prove_LW_ID`. Missing metadata
never downgrades a known index. These index repairs can include rows outside the
current report. A legacy row without any sequencing ID also retains the metadata
sequencing ID when it is used as the fallback; other fields remain untouched.
The summary's `reindexed` count reports repairs to existing master indexes. A row with neither a usable
specimen ID nor a sequencing fallback stops the merge before writing.

The old `Master_Key_Source` field is preserved as legacy provenance. Both it and
`Master_Index_Source` are reserved and must not appear in metadata/report inputs.

If a provisional key would collide with an unrelated existing key, or its later
specimen ID resolves to another existing row, the merge stops for resolution rather
than overwriting or combining ambiguous records. Duplicate `Prove_LW_ID` values,
ambiguous sequencing IDs, and conflicting source columns that map to the same
destination stop the merge before master replacement.

Only samples present in the current report are added or have their metadata and
results updated. Metadata-only rows do not create master entries. Apart from the
index and known text repairs described here, samples outside the report retain their values. For a sample
in the report, precedence is:

1. Existing master values.
2. Non-empty values from matching metadata.
3. Values from columns present in the new analysis report, including empty cells.

Report columns absent from the new report retain their existing values. This
allows FASTA updates to preserve FASTQ-specific measurements. The literal text
`NA`, `None`, or `0` in data cells is retained and can replace an old value; it is
not interpreted as a blank, except for identifier validation. The resolved
`Prove_LW_ID` is protected from blank/missing report or metadata cells. To preserve
old analysis values for empty report cells as well, pass `--nonempty-report`, or set
`FLUSEQ_MASTER_NONEMPTY_REPORT=true` for wrappers.

The first 193 columns follow the exact requested order in
`assets/master_csv/columns.txt`. XML destinations are matched to their canonical
spellings without case sensitivity. In particular, `Pasient_Kjonn` and
`PASIENT_KJONN` map to the requested `Pasient_Kjnn`, and `Prove_Maanad` /
`PROVE_MANAD` map to the requested `Prove_M nad`.

Mapped fields use their master names. Unmapped and XML `__None__` fields are
retained with their original names, including future metadata/report columns.
The metadata export's original `Key` is retained as `Metadata_Key` because its
XML maps `RekvNr` to the legacy `Key` column. Both `Prove_Sesong` and `Sesong` map to
`Prove_Sesong`; differing non-empty values are rejected rather than guessed.
Both report spellings `Coverage-M` and `Coverage-MP` map to `NGS_Coverage_M`.
No biological interpretation is performed, and no mappings beyond the supplied
templates, these spelling aliases, and the identifier rules above are inferred.

On each master merge, known damaged text is repaired in all master rows, including
rows outside the current run: `Tr ndelag`, `M re g Romsdal`, and ` stfold` in
`Pasient_Fylke_Name` become `Trøndelag`, `Møre og Romsdal`, and `Østfold`;
`P vist` and `Ikke p vist` in `PCR_*_Res` become `Påvist` and `Ikke påvist`.
These fields also receive NFC Unicode normalization and reversible UTF-8/Windows-1252
mojibake repair. Unrecognised damaged text and other fields are left unchanged.
The summary's `text_repaired` counts rows repaired. Existing shared masters are
updated by the next successful enabled merge, with the usual backup; a preview
can be made first as described below.

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
header `Prove_LW_ID` (the legacy `Key` header is also accepted); missing files are
rejected to avoid creating a new database after a download/path error.

## One-time historical backfill in R

`bin/backfill_master_once.R` combines an existing master, `NGS_PREP_INF_report.csv`,
and a historical CSV whose columns already use the master names (for example,
`NGS_Coverage_HA`, rather than raw pipeline column `Coverage-HA`). It uses base R
only and can run in RStudio on Windows or with `Rscript`.

The existing master supplies **the exact output header and column order**,
including the later metadata and pipeline columns. It can contain existing rows
or just its header. Required header columns are `Key`, `Prove_LW_ID`, and
`Master_Index_Source`. All three input files remain unchanged; output must be a
new filename in an existing directory.

In RStudio, source the script and supply your actual file paths:

```r
source("C:/path/to/backfill_master_once.R", encoding = "UTF-8")

backfill_master(
  master   = "N:/path/to/INF/master.csv",
  metadata = "N:/path/to/INF/NGS_PREP_INF_report.csv",
  results  = "C:/path/to/historical_results.csv",
  output   = "C:/path/to/master.backfill.csv"
)
```

Or use the command line:

```bash
Rscript master_csv/bin/backfill_master_once.R \
  --master /path/to/master.csv \
  --metadata /path/to/NGS_PREP_INF_report.csv \
  --results /path/to/historical_results.csv \
  --output /path/to/master.backfill.csv
```

The one-time import follows these rules:

- Keep identifiers, dates, numeric-looking fields and all other cells as text.
  Preserve leading zeros and column names containing spaces.
- Match exact `Prove_LW_ID`, using sequencing IDs and legacy `Key` matches when
  the specimen ID is unavailable. Map metadata `RekvNr` to `Key` and metadata
  `Key` to `Metadata_Key`, applying the existing metadata spelling aliases.
- Use sequencing IDs as marked provisional indexes only when no specimen match
  is available. Repair existing missing/provisional indexes using metadata.
- For new rows, combine nonblank metadata with nonblank historical results;
  historical values take precedence where both supply a value. No new row is
  created for a sample found only in metadata.
- **By default, preserve populated existing master cells and fill only gaps.**
  This prevents an older partial export from replacing newer results. For the
  usual nonempty-import precedence (existing master, metadata, then historical
  results), explicitly use `overwrite_existing = TRUE` in R or
  `--overwrite-existing` on the command line. Blank inputs never erase values.
- Write unavailable fields as empty cells. Do not manufacture `NA`: literal
  `NA`, `None` and `0` in nonidentifier fields are retained as data, as in the
  normal merge. Identifier placeholders are handled by the existing rules.
- Stop on duplicate specimen indexes, conflicting identifiers, conflicting
  mapped columns, or input columns absent from the master header. Extend a copy
  of the master header if necessary; columns are never silently dropped.
- Apply the known county/PCR text repairs. Output is semicolon-separated UTF-8
  with BOM and CSV quoting. UTF-8, Windows-1252 and BOM-marked UTF-16 inputs are
  detected automatically; `encoding` / `--encoding` can override this for all
  inputs.

To retain reviewed historical records that have only a name in `Key`, enable
`allow_name_fallback = TRUE` in `backfill_master()` or `--allow-name-fallback`
on the command line. After the usual metadata/identifier matching, an otherwise
unresolved name-only row is retained using its exact name as `SequenceID` and
the provisional `Prove_LW_ID`, marked `Master_Index_Source=Sequence_ID`.
`Key` stays unchanged and `NGS_LW_ID` stays blank. For example,
`B/TOKYO/EIS13-175/2025` is preserved in full, with no generated or shortened name.
The master header must include `SequenceID` (the supplied full master header
already does). This uses the existing sequencing-fallback rules, so future
Python imports can preserve the row and resolve its index if matching metadata
later supplies a specimen ID. The R importer can also repair existing name-only
master rows when this option is enabled; metadata-only records are still not
created. Duplicate names, ambiguous matches and collisions with another
record's sequencing ID remain errors. Rows with no usable identifier or name
still fail. The option is off by default.

To choose one historical result when several records resolve to the same
`Prove_LW_ID`, use `duplicate_results = "first"` in R or
`--duplicate-results first` on the command line. This retains the first complete
record in the historical CSV for each resolved ID and skips later ones. Use
`"last"` to retain the last record instead; neither policy infers which result
is newest or combines fields across duplicate historical records. Selection
happens after metadata matching and name fallback, including for named records
such as `B/TOKYO/EIS13-175/2025`. The source CSV is unchanged, and the summary
reports how many duplicate records were skipped. Duplicate checks on the
existing master and metadata remain strict. The default `"error"` policy stops
and reports the CSV record numbers of the first duplicate group.

The script reports row counts, unmatched historical rows, and the count of
differing populated cells preserved (or overwritten with the explicit option).
The output is a **complete replacement candidate**, including existing rows,
not an append-only batch. Review it and back up the current master before
replacing that file; do not append the preview to the existing master. No FASTA
archive or shared database is updated by the script. Tests use synthetic data;
your actual exports still need to be checked by running the preview.

If an input fails the CSV field-count check, use the same sourced R script to
inspect its structure without printing cell contents:

```r
diagnose_csv("backlog.csv")
```

This reports the detected separator, expected field count, and a table of
inconsistent record-ending physical lines. Quoted multiline fields and empty
physical lines are accounted for. Inspect extra/missing separators and quoting
at those locations in a copy of the export; the importer does not pad or discard
malformed records. An unterminated quoted field is rejected explicitly.

## Wrapper configuration

The updated `ngs_scripts/fluseq/fluseq_wrapper.sh` and
`ngs_scripts/fluseq/fluseq_fasta_wrapper.sh` use a bundled copy under
`ngs_scripts/fluseq/master_csv/`. `FLUSEQ_MASTER_TOOLS` can instead point to a
pipeline checkout containing `bin/` and `assets/master_csv/`.

Both human wrappers default to `FLUSEQ_MASTER_UPDATE=true`, enabling CSV and
FASTA updates using the defaults below or explicit overrides. Add `-M` to the
wrapper command or set `FLUSEQ_MASTER_UPDATE=false` to skip both updates.
Validation runs always skip updates. `FLUSEQ_MASTER_UPDATE=auto` enables updates
only when a master/metadata location is configured. The standalone update tool
defaults to `auto` when the variable is unset.

For now, place `NGS_PREP_INF_report.csv` in the same directory as `master.csv`.
Metadata defaults to that directory for both mounted files and SMB transfers.
No separate metadata location needs to be configured.

For mounted files:

```bash
export FLUSEQ_MASTER_CSV='/mnt/n/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/master.csv'
```

The mount path is an example and must match the server's mounts. For the
existing `smbclient` setup, the wrappers use the shared-directory defaults.

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
| `FLUSEQ_MASTER_UPDATE` | `true` in wrappers, `auto` for the standalone tool; accepts `auto`, `true`, or `false` |
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
`bin/templates/report_qc.html`, `bin/diagnose_master_ids.py` and
`bin/merge_master_fasta.py`. If `FLUSEQ_MASTER_TOOLS` points elsewhere, that
directory must contain these reporting files as well. The HTML renderer extends
the initial renderer in `nf-core-fluseq`; this bundled version is run after the
master merge so the qPCR comparison includes newly imported metadata.

## Avian FASTA wrapper

`avianseq_fasta_wrapper.sh` enables both archive updates by default, after the
existing result uploads. It passes `--profile avian --workflow fasta` and the
completed `reporthuman/<RUN>.csv` and `reporthuman/<RUN>.fasta` to the same updater
as the human wrappers. Existing backup, locking, identifier-conflict checks, and
verified SMB uploads apply. It retains `$HOME/out_fluseq/<RUN>` for retries and
later metadata imports. A failed merge stops cleanup.

The default destination is:

```text
N:\Virologi\NGS\1-NGS-Analyser\2-Utvikling\Seksjons for Influensa og andre luftveisvirus - NGS analysis database\data\INF-AVIAN
```

The SMB share is `//pos1-fhi-svm01.fhi.no/styrt`; the directory is the human
default with `INF` replaced by `INF-AVIAN`. Output files are `master.csv` and
`master.fasta`. The directory and `master.csv` must already exist; a header-only
CSV containing `Prove_LW_ID` is supported. A missing FASTA is created on the
first nonempty update.

Avian configuration uses **`AVIANSEQ_`**, independently of inherited `FLUSEQ_`
variables. All master/metadata settings in the table above have an equivalent
`AVIANSEQ_` name, with these differences:

| Setting | Avian behavior |
| --- | --- |
| `AVIANSEQ_MASTER_UPDATE` | `true` in the wrapper, `auto` for standalone invocations |
| `AVIANSEQ_MASTER_SMB_DIR` | Defaults to the `INF-AVIAN` directory above |
| `AVIANSEQ_METADATA_CSV` | Explicit local/mounted metadata path; accepts CSV, XLS or XLSX despite the historical variable suffix |
| `AVIANSEQ_METADATA_SMB_NAME` | Explicit filename; otherwise discover `metadata.csv`, `metadata.xls`, or `metadata.xlsx` beside the master or in the configured metadata SMB location |
| `AVIANSEQ_METADATA_SHEET` | Worksheet name; required when an Excel workbook contains multiple worksheets |
| `AVIANSEQ_MASTER_TOOLS` | Wrapper directory's `master_csv` subdirectory |

Discovery requires exactly one matching file. Missing files and multiple matches
fail rather than selecting an arbitrary export. An explicit metadata filename or
path disables discovery. Network/access failures are errors, not missing files.
The avian profile never defaults to `NGS_PREP_INF_report.csv`.

While metadata is unavailable, use `-M` / `--skip-master` or
`AVIANSEQ_MASTER_UPDATE=false` to run without either master update. Validation
runs always skip both. Configuration preflight checks mounted paths before
analysis; SMB metadata availability is checked at merge time, just as for the
human wrapper. Once metadata is available, retry from the retained report files:

```bash
AVIANSEQ_MASTER_UPDATE=true \
python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/update_master_csv.py \
  --profile avian --workflow fasta \
  --report /home/ngs/out_fluseq/RUNNAME/reporthuman/RUNNAME.csv \
  --fasta /home/ngs/out_fluseq/RUNNAME/reporthuman/RUNNAME.fasta
```

The existing identifier contract is provisional until the actual metadata export
can be checked: use `Prove_LW_ID` for specimen IDs and/or a recognized sequencing
ID column (`NGS_LW_ID`, `Sequence_ID`, `SequenceID`, `SampleID`). Report
`OriginalName` / `SampleID` must match the identifiers under the rules above.
Unknown metadata and report columns are retained. No new avian column aliases
are guessed. Replaying a report after metadata arrives enriches its existing
rows; it does not import unrelated metadata-only samples.

CSV imports need no extra packages. For Excel, install the optional requirements
in the Python environment used both for preflight and for the merge:

```bash
python3 -m pip install -r /home/ngs/ngs_scripts/fluseq/master_csv/requirements-excel.txt
```

XLS uses [xlrd](https://xlrd.readthedocs.io/en/stable/api.html); XLSX uses
[openpyxl](https://openpyxl.readthedocs.io/en/3.1/api/openpyxl.reader.excel.html).
Excel headers must occupy the first row. Store identifier columns as **text** to
preserve leading zeros; numeric identifier cells are rejected. Other numeric
cells become text and date/time cells use ISO formatting. Supply values-only
exports: XLSX formulas and Excel error cells are rejected; XLS reads cached
formula results. Multiple worksheets require explicit selection. Neither reader
modifies the source workbook.

Local tests use synthetic data. Production acceptance still requires the actual
metadata schema, confirmation of the completed avian report paths/identifiers,
and an ngs4 run with access to the destination share. These changes do not deploy
the tools or create files on the N: drive.

## Master FASTA

The optional `--fasta /path/to/<RUN>.fasta` argument merges that exact run file
into `master.fasta` beside the configured master CSV. Both human wrappers pass
this argument automatically. For a mounted CSV, the FASTA uses the same parent
directory. For SMB, it uses the same share, directory and authentication as the
master CSV, regardless of the metadata location. No additional configuration is
required. Master-update mode and validation skips apply to both archives.

Matching uses the full FASTA record ID before the first whitespace, with exact
case-sensitive comparison. For example, `SAMPLE|01-HA-H3N2` and
`SAMPLE|02-NA-H3N2` are separate records. The latest incoming record replaces an
existing matching ID, including its header description. New IDs are appended;
existing IDs retain their position, and records absent from this run remain.
Identical sequence content under different IDs does not collapse different
samples. Header IDs are not translated to CSV `Prove_LW_ID`, `Key`, or `OriginalName`, and a
changed ID is a new record.

Multiline records, UTF-8 BOM and CRLF line endings are supported. Blank lines
and sequence whitespace are ignored. Identical duplicate records within a file
are collapsed, while conflicting duplicate IDs are rejected. Incoming data is
validated before the CSV update starts. A missing run FASTA is an error; an
empty run FASTA is a no-op and never empties or creates a master archive.

The first non-empty update creates a missing `master.fasta`. For SMB, only an
explicit `NT_STATUS_OBJECT_NAME_NOT_FOUND` allows creation. Missing directories,
access errors and network failures abort without treating the archive as empty.
An existing empty FASTA is also a valid starting point.

An exclusive `master.fasta.lock` directory serializes participating writers.
Changed existing archives receive a unique `master.fasta.bak.<timestamp>.<id>`
backup. Mounted replacements use `os.replace`; first creation uses an exclusive
hard link to a complete temporary file so another initializer cannot be
overwritten. SMB verifies backup and candidate uploads, checks that the old
master has not changed, then performs a server-side rename and verifies the
result. First creation uses rename without replacement. Identical retries leave
the original file and its formatting untouched and create no extra backup.

CSV and FASTA are separate file updates: the CSV may already have completed if
the FASTA or subsequent QC/report upload fails. Retry the same command to finish
the remaining work; both merges are idempotent. FASTA merge counts appear in the
update summary under `fasta` (`added`, `updated`, `unchanged`, `total`, `written`).

To update both archives from an existing completed run:

```bash
FLUSEQ_MASTER_UPDATE=true \
python3 /home/ngs/ngs_scripts/fluseq/master_csv/bin/update_master_csv.py \
  --workflow fastq \
  --report /home/ngs/out_fluseq/INF109/reporthuman/INF109.csv \
  --fasta /home/ngs/out_fluseq/INF109/reporthuman/INF109.fasta
```

Use `--workflow fasta` for a FASTA report. Omitting `--fasta` updates only the CSV
as before. To merge only FASTA records using local/mounted files:

```bash
python3 master_csv/bin/merge_master_fasta.py \
  --master /path/to/master.fasta --fasta /path/to/reporthuman/INF109.fasta
```

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
the sequencing ID (normally `NGS_LW_ID`). FASTA uses the exact identifier rules
above, including legacy `Key` names. The detail view shows the matched
`Prove_LW_ID`. Ambiguous join identifiers are rejected rather than matched
arbitrarily. Standalone QC can still read older masters without the new index.

`Påvist` or the observed export form `P vist` in a subtype-specific PCR result
field is positive. `Ikke påvist` and `Ikke p vist` are negative. Comparison
ignores case and extra whitespace and preserves the original result in the
report's qPCR evidence. H1, H3 and H5 compare the H component of a called subtype; B/Victoria
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

If a merge reports that a sequencing ID maps to multiple `Prove_LW_ID` values,
it stopped before replacing the master. The same sequencing ID points to different
specimen indexes in the master or metadata, or conflicting values
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
or `metadata`), effective `Prove_LW_ID`, index provenance, legacy `Key`, record
number and whether it is involved in the supplied
run report. Record numbering starts at 2 after the header and excludes blank
records; quoted multiline cells count as one record. Only identifiers are
exported, with owner-only file permissions. Standard output shows counts rather
than identifiers. Exit code 2 means conflicts were found; 0 means this check
found none. Other merge validations can still fail independently.

Resolve the source identifiers against the lab records before retrying just the
merge using the command above under Wrapper configuration. Existing analysis
and uploaded results can be reused. An existing non-empty `Prove_LW_ID` that happens
to equal its sequencing ID is not automatically treated as provisional: it needs
`Master_Index_Source=Sequence_ID` for automatic replacement. Rows with a missing
index are migrated using the rules above.

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
pytest -q tests/test_master_csv_configuration.py tests/test_master_csv_identifiers.py tests/test_master_fasta.py tests/test_qc_report.py
```

Live shared-drive access and the real LabWare/master exports still require a
server-side acceptance run with the metadata file beside the master.
