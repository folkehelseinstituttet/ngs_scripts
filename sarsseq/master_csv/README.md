# SARS master schema and mappings

The implementation covers tasks 1–12, including the accession importer,
end-to-end tests and local deployment checks. The local preview defines the SARS schema,
`update_master.py` updates a mounted or SMB-hosted SC2 master CSV and FASTA archive, and both
wrappers invoke it after their result-upload steps with Influenza's update
controls. Both wrappers generate SARS HTML/JSON QC and verify publication before
completion and cleanup; offline runs generate locally. The renderer also supports
standalone generation. Known damaged Norwegian text is repaired using Influenza's
shared function during master merges. The metadata
schema and merge policy follow Influenza, as confirmed by the user. Live server
access and representative production CSV validation still need a deployment
check; no production master was read or changed during this work. Follow
[deployment and acceptance checks](../DEPLOYMENT.md) when updating the installed
checkout. Site acceptance is explicitly separate from the completed local tests.

## Sources and column inventory

- Metadata: the same columns as `NGS_PREP_INF_report.csv`. The shared exporter,
  [`INFL-NGS-UTTREKK.R`](../../lims_uttrekk/Scripts/INFL-NGS-UTTREKK.R), builds INF,
  SC2 and RSV reports with the same final column selection.
- Metadata mappings: loaded directly from Influenza's
  [`LABWAREDIRECT.xml`](../../fluseq/master_csv/assets/master_csv/LABWAREDIRECT.xml),
  including its `Key` → `Metadata_Key` adjustment. There is no separate SARS copy
  to drift from the Influenza mapping.
- SARS reports: inspected local `nf-core-sars` checkout at revision
  `085060e9e40e13bf6fbfa7503d5630084089ad59`, specifically `bin/report.py`,
  `bin/report-fasta.py`, `bin/csv_conversion_nextclade.py`,
  `modules/local/report/main.nf`, and `modules/local/report-fasta/main.nf`.
  Both modes emit `Sample`. Reports have a variable set of analysis columns.
- Initial master order: [columns.txt](assets/columns.txt), based on the header of
  the local legacy `documentation_BN/SC2BN` export (128 columns), replacing
  `NGS_Sekvens_ID` with `NGS_LW_ID` and adding `Metadata_Key`. This is a legacy
  schema reference, not a snapshot of the production `data/SC2/master.csv`.
  Extra master, metadata and report columns are appended without dropping data.

The configured production destinations are
`…/NGS analysis database/data/SC2/master.csv`,
`…/NGS analysis database/data/SC2/NGS_PREP_SC2_report.csv`, and
`…/NGS analysis database/data/SC2/master.fasta`. All three locations are now
used by the production updater. The preview still requires
explicit local paths and has no network or production-write behavior.

## Metadata and identifiers

| Source | Master field / matching rule |
| --- | --- |
| Metadata `Prove_LW_ID` | Unique specimen index; one master row per specimen |
| Metadata `NGS_LW_ID` | Sequencing identifier used to resolve the specimen |
| Metadata `RekvNr` | Legacy master `Key` |
| Metadata `Key` | `Metadata_Key`; preserved separately from `RekvNr` |
| Metadata `Pasient_Kjonn` | `Pasient_Kjnn`, matching Influenza |
| Metadata `Prove_Maanad` | `Prove_M nad`, matching Influenza |
| Metadata `Sesong`, `Prove_Sesong` | `Prove_Sesong`; conflicting nonblank values fail |
| Other metadata | Shared XML mapping; unmapped columns retain their names |
| Legacy master `NGS_Sekvens_ID` | `NGS_LW_ID` |
| FASTQ report `Sample` | `NGS_LW_ID`; exact sequencing-ID lookup |
| FASTA report `Sample` | `SampleID` and, unless explicitly supplied, `OriginalName` |

FASTA matching uses Influenza's shared `fasta_match`: exact `OriginalName` or
`SampleID` against specimen IDs, legacy `Key`, and stored FASTA aliases, together
with sequencing-ID lookup. Different resolved specimens are an error. A SARS
FASTA `Sample` can therefore contain a sequencing ID, specimen ID, legacy key,
or previously stored alias. An explicit `OriginalName` is retained and checked.

All IDs remain strings with leading zeros preserved. Matching is case-sensitive
after trimming outer whitespace; IDs are never split or approximately matched.
Blank, `NA`, `N/A`, `NaN`, `None`, `NULL`, and `-` are missing identifiers
(case-insensitive for these sentinel values only).

The shared sequencing-ID priority is `NGS_LW_ID`, `Sequence_ID`, `SequenceID`,
then `SampleID`. If there is no exact match or supplied specimen ID, the
sequencing ID becomes a provisional `Prove_LW_ID` with
`Master_Index_Source=Sequence_ID`. A later metadata match migrates that row to
the actual specimen ID, marking `Master_Index_Source=Prove_LW_ID`. Missing
metadata cannot downgrade an established specimen index.

Missing legacy master indexes are recovered using the same shared metadata
lookup and fallback rules as Influenza. Index migration may affect rows outside
the current report. Duplicate specimen indexes, a sequencing ID assigned to
multiple specimens, ambiguous aliases, conflicting supplied IDs, and fallback
collisions fail before the preview output is created. `Master_Index_Source` and
`Master_Key_Source` are reserved master provenance columns, including in
header-only metadata/report inputs.

## SARS report mappings

These are field renamings only; all values are preserved as text. The executable
mapping is in [schema.py](schema.py).

| Report column | Master column |
| --- | --- |
| `RunID` | `NGS_Run_ID` |
| `Date` | `NGS_Script_dato` |
| `Instrument ID` | `NGS_Instrument ID` |
| `Primer` | `NGS_Primer_vers` |
| `clade` | `NC_Clade` |
| `Nextclade_pango` | `NC_Pangolin_Short` |
| `partiallyAliased` | `NC_Pangolin_Long` |
| `coverage` | `NC_Coverage` |
| `NC_Genome_MixedSites` | `NC_MixedSItes` (legacy spelling retained) |
| `NC_Genome_QC` | `NC_Genome_Quality` |
| `NC_Genome_frameShifts` | `NC_Genome_Frameshift` |
| `Spike_mAbs_inhibitors`, `Spike_Fold` | `DR_Spike_mAbs`, `DR_Spike_mAbs_fold` |
| `3CLpro_inhibitors`, `3CLpro_Fold` | `DR_3CLpro_Mut`, `DR_3CLpro_fold` |
| `RdRp_inhibitors`, `RdRp_Fold` | `DR_RdRP_Mut`, `DR_RdRp_Fold` |
| `<gene>_aaSubstitutions` | `Mut_<gene>` |
| `S_aaSubstitutions_1` … `_4` | `Mut_S_1` … `_4` |
| `ORF1a_aaSubstitutions_1` … `_4` | `Mut_ORF1a_1` … `_4` |
| `<gene>_aaDeletions`, `<gene>_aaInsertions` | `NC_<gene>_Deletions`, `NC_<gene>_Insertions` |
| `GISAID_Comment`, `GISAID_Kommentar` | `GISAID_Kommentar`; differing nonblank values fail |

Gene mappings cover the report's E, M, N, ORF1a, ORF1b, ORF3a, ORF6, ORF7a,
ORF7b, ORF8, ORF9b and S columns. Complete and numbered substitution columns
remain separate; they are not combined. New/unmapped columns are preserved.

`NGS_QC_Sum`, `DR_Res_*`, `NGS_Script_vers`, `Release Version`, `QC`,
`QC_overall_pct`, `QC_cds_*`, `cdsCoverage`, `clade_nextstrain`, `clade_who`,
`Barcode`, `PCR-PlatePosition`, and `KonsCt` retain their names. Collision-suffixed
pipeline columns such as `coverage_stats` remain separate from `coverage`.
The tool/version string and release label also remain separate. SARS does not
inherit Influenza-specific analysis columns such as `NGS_Coverage_HA`.

Use exactly one final report per preview: `<RUN>.csv` or
`<RUN>_with_software_versions.csv`. The latter includes `NGS_Script_vers`.
Do not concatenate the primary, without-versions, and with-versions reports:
they represent the same samples. FASTA reports may omit FASTQ run measurements.

## Update precedence

Only samples in the report receive metadata/report updates. Metadata-only
specimens do not create master entries. Identifier migration and the known text
repairs below can also affect existing rows outside the run. For each report
specimen, apply:

1. Existing master values.
2. Matching metadata values that are not whitespace-only.
3. Values from columns present in the report, including empty cells.

Columns absent from the report retain their previous values. Thus a FASTA update
preserves FASTQ-specific measurements it does not supply. `--nonempty-report`
preserves prior values when report cells are blank, matching Influenza's option.
The resolved `Prove_LW_ID` always survives blank source cells. Literal `NA`,
`None`, `NaN`, and `0` in ordinary data cells are values, not blanks; even metadata
sentinels can replace older values under the shared policy.

Existing GISAID accessions and manual fields survive if absent from the inputs;
there is no special field ownership beyond these precedence rules. An incoming
column with the same name follows the same rules. Accession-import conflict
handling is implemented in the [SC2 accession importer](../../gisaid/sars-cov-2/README_CSV.md#import-returned-accession-ids).

### Norwegian text repairs

Preview and production merges use Influenza's shared `repair_metadata_text`
function after applying metadata/report precedence. It repairs all resulting
master rows, including existing rows outside the current report:

| Field | Known damaged value | Repaired value |
| --- | --- | --- |
| `Pasient_Fylke_Name` | `Tr ndelag` | `Trøndelag` |
| `Pasient_Fylke_Name` | `M re g Romsdal` | `Møre og Romsdal` |
| `Pasient_Fylke_Name` | ` stfold` | `Østfold` |
| `PCR_*_Res` | `P vist` | `Påvist` |
| `PCR_*_Res` | `Ikke p vist` | `Ikke påvist` |

Field matching ignores case. Known damaged values are matched ignoring case and
extra whitespace. Only these county/result fields also receive NFC Unicode
normalization and reversible UTF-8-as-Windows-1252 repair, for example
`MÃ¸re og Romsdal` and `PÃ¥vist`. Correct text is preserved. Unrecognised wording
such as `Mulig p vist` is not converted into a positive result. Unknown damage
is not guessed; IDs, Ct values, notes and other fields are unchanged by this pass.
This is text repair, not geographic remapping or reinterpretation of qPCR results.

The JSON summary's `text_repaired` counts rows changed by this pass, once per row,
separately from report-row `added`/`updated`/`unchanged` counts. Repeated damaged
metadata can cause a nonzero repair count on a retry even when the final master
is identical and `written` is false. Unchanged output creates no new backup.

The preview writes only its new output file. Enabled mounted/SMB updates apply
repairs within the existing locked, backed-up transaction; source reports and
metadata exports are not rewritten. Master repairs are skipped when updates are
disabled, during validation, and offline. QC generated after an enabled update
uses the repaired master values. Standalone QC renders the supplied master as-is
without repairing or writing it. No production master was modified during
implementation; existing stored damage is repaired on the next successful enabled
merge.

## Local validation

```bash
python3 sarsseq/master_csv/preview_merge.py \
  --workflow fastq \
  --master /path/to/master.csv \
  --metadata /path/to/NGS_PREP_SC2_report.csv \
  --report /path/to/report/RUN_with_software_versions.csv \
  --output /path/to/new-preview.csv

pytest -q sarsseq/tests
```

Use `--workflow fasta` for FASTA reports. The master must exist and may contain
only the `Prove_LW_ID` header. A header-only metadata file is supported when its
header contains a specimen or sequencing-ID column. The report must be nonempty.
An optional `--mapping` JSON overrides selected default mappings by input source;
conflicting nonblank fields mapped to the same destination fail.

CSV input accepts UTF-8, UTF-16 BOM or CP1252 and semicolon, comma or tab
delimiters. Output is a new UTF-8 BOM, semicolon-delimited CSV. Input files and
existing output files cannot be overwritten. Tests use synthetic records and
compare metadata mapping and update precedence directly with Influenza.

## Production CSV configuration

The standalone entry point is [update_master.py](update_master.py). Deploy the
complete `ngs_scripts` checkout: SARS imports the shared transaction functions
and metadata mappings under `fluseq/master_csv`. The shared functions accept
SARS configuration and a SARS table merger; Influenza's defaults are unchanged.
SARS reads only `SARSSEQ_*` settings, so existing `FLUSEQ_*` variables do not
redirect its updates.

The default SMB share is `//pos1-fhi-svm01.fhi.no/styrt`. Its default directory is:

```text
Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2
```

| Environment variable | Default / purpose |
| --- | --- |
| `SARSSEQ_MASTER_UPDATE` | `true` in both wrappers, `auto` for the standalone updater; `true` enables the default SMB destination, `false` skips updates |
| `SARSSEQ_MASTER_CSV` | Existing mounted master CSV; takes precedence over master SMB settings |
| `SARSSEQ_METADATA_CSV` | Explicit mounted metadata CSV; otherwise defaults beside a mounted master unless a metadata SMB share is set |
| `SARSSEQ_MASTER_SMB_SHARE` | Share above |
| `SARSSEQ_MASTER_SMB_DIR` | SC2 directory above |
| `SARSSEQ_MASTER_SMB_NAME` | `master.csv` |
| `SARSSEQ_METADATA_SMB_SHARE` | Inherits the master share |
| `SARSSEQ_METADATA_SMB_DIR` | Inherits the master directory |
| `SARSSEQ_METADATA_SMB_NAME` | `NGS_PREP_SC2_report.csv`; also used beside a mounted master |
| `SARSSEQ_MASTER_SMB_AUTH` | `/home/ngs/.smbcreds` |
| `SARSSEQ_METADATA_SMB_AUTH` | Inherits the master authentication file |
| `SARSSEQ_MASTER_NONEMPTY_REPORT` | `false`; `true` preserves old values for blank report cells |
| `SARSSEQ_MASTER_TOOLS` | Wrappers default to their adjacent `master_csv` directory; an override must contain `update_master.py` and its SARS dependencies |

`auto` enables updates when a master path/share/directory, metadata path, or
metadata share is explicitly configured. Both wrappers default an unset or empty
setting to `true`, exactly as Influenza does. `-M` forces `false` regardless of
the inherited environment. Explicit `true`, `false` and `auto` values are
case-insensitive; other values fail preflight, including on validation runs,
matching Influenza's configuration validation. `--validation VER` skips
standalone updates; wrapper validation runs pass their validation flag through.
The routine wrapper skips master preflight and updates entirely in offline mode.

| Run / setting | Master CSV and FASTA behavior |
| --- | --- |
| Routine online, setting unset or empty | Enabled; configured locations or the default SC2 SMB location |
| `SARSSEQ_MASTER_UPDATE=true` | Enabled |
| `-M` or `SARSSEQ_MASTER_UPDATE=false` | Skip; analysis and ordinary result uploads still run |
| Explicit `SARSSEQ_MASTER_UPDATE=auto` | Enabled only with a configured location; otherwise skip |
| Validation (`-v VER`) | Skip regardless of a valid update mode |
| Routine wrapper offline (`-o`) | Skip all master access, including mounted files |
| Routine wrapper test (`-t` / `--test`) | Suppress Teams only; master mode is unchanged |

An enabled update with unavailable master/metadata paths or credentials is a
failure, never a silent skip. Use `-M` for an intentional run without master
updates. `SARSSEQ_MASTER_NONEMPTY_REPORT` keeps Influenza's `false` default and
accepts only `true`/`false` when updates are enabled.

For SMB, install `smbclient` and make the authentication file available to the
account running the updater. Credential contents are never printed. The shared
directory must already exist. The account needs read access to both CSVs and
permission to create files/directories, upload, rename with replacement, and
remove its lock directory beside the master. Configure an actual mount path
instead of relying on drive-letter or mount-name assumptions.

For a mounted directory (adjust `/mnt/N` to the server's mount):

```bash
export SARSSEQ_MASTER_CSV='/mnt/N/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2/master.csv'
python3 sarsseq/master_csv/update_master.py --workflow fastq --check-config
python3 sarsseq/master_csv/update_master.py --workflow fastq --check-access
python3 sarsseq/master_csv/update_master.py --workflow fastq \
  --report /path/to/report/RUN_with_software_versions.csv
```

For the default SMB location, with no mounted-path overrides:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --check-config
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --check-access
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --report /path/to/report/RUN_with_software_versions.csv
```

Use `--workflow fasta` for FASTA reports. Each input can independently use a
mounted path or SMB. For a mounted master and remote metadata, explicitly set
`SARSSEQ_METADATA_SMB_SHARE` and, if needed, `SARSSEQ_METADATA_SMB_DIR`. An
explicit `SARSSEQ_METADATA_CSV` takes precedence over those SMB settings.

`--check-config` verifies local file paths and, where needed, the SMB executable
and credential-file existence. It does not connect to the server.
`--check-access` reads and parses both CSVs, reporting only row/column counts;
it does not create locks, upload, or replace shared files. It verifies read
access and CSV syntax, not write permissions or full merge validity. A local
preview validates the merge; an isolated server acceptance run must verify
write/rename permissions before production deployment.

## Backups, locking and verification

Both transports use the same transaction implementation as Influenza:

1. Acquire an exclusive `master.csv.lock` directory before reading the master.
2. Validate and merge the latest master, metadata and the selected run report.
3. If the serialized output is unchanged, return `written=false` without a
   backup or replacement.
4. For changes, create a unique `master.csv.bak.<UTC timestamp>.<UUID>` backup
   and verify it against the original bytes before replacing the master.
5. Check that the master has not changed during preparation. Abort on a detected
   external edit instead of overwriting it.
6. Replace the master and release this invocation's lock on success or failure.

Mounted updates write/fsync a temporary CSV in the master directory, preserve
file permissions, and replace with `os.replace`. SMB uploads the backup and a
uniquely named candidate, downloads both to verify their SHA-256 hashes, then
uses server-side `rename ... -f`. It downloads the resulting master and verifies
its hash as well. There is no delete-then-upload fallback. SMB exit errors,
`NT_STATUS_*`/`DOS_STATUS_*` errors (even with exit code zero), timeouts and
verification mismatches fail the command.

Missing or inaccessible master/metadata files are errors; the updater never
creates an empty database to conceal a missing download. For first setup,
deliberately create a master containing the `Prove_LW_ID` header. A master and
metadata resolving to the same local file or configured SMB path are rejected.
When mixing mounted and SMB access, ensure they do not refer to the same file
through different access paths; that equivalence cannot be inferred locally.

Backups are retained without automatic deletion. Normal local temporary files
are cleaned up on exit. Failed SMB uploads can leave `.tmp.*` or `.bak.*` files;
a failed verification means the affected upload must not be trusted. A failure
after server-side replacement may leave the new master in place: inspect it and
its verified backup before retrying, rather than blindly restoring old data.
Repeated successful updates with the same inputs are idempotent.

An existing lock is never removed by an invocation that failed to acquire it.
Abrupt termination or failed SMB lock removal can leave a stale lock; verify
that no writer is active before removing it. Spreadsheet users and unrelated
writers must respect the lock or use separate maintenance windows. Hash checks
detect intervening changes but cannot make an unrelated writer participate in
the transaction.

The updater supports CSV/FASTA updates and verified QC publication. The separate
[SC2 GISAID exporter](../../gisaid/sars-cov-2/README_CSV.md) now reads the master,
CSV lab lookup and matching FASTA records. Both SC2 and INF master-based exporters
require current approval in the solution before their existing metadata/QC
filters. The separate accession importer adds returned names/IDs using the same
master lock directory, verified backups and conflict checks.
Tests cover mounted updates and simulated SMB success/failure paths, including
backup/candidate corruption, concurrent edits, failed rename/final verification,
lock cleanup and idempotent retries. The development environment has no mounted
SC2 files or `/home/ngs/.smbcreds`; live production access has not been verified.

## Wrapper integration

Both [sarsseq_wrapper.sh](../sarsseq_wrapper.sh) and
[sarsseq_fasta_wrapper.sh](../sarsseq_fasta_wrapper.sh) source
[wrapper_integration.sh](wrapper_integration.sh). Before downloads or analysis,
they run the updater's `--check-config` preflight. A configuration error stops
the wrapper at that point. This check does not connect to SMB.

After the existing result-upload commands succeed, they select exactly one CSV
from the current run's `report` directory:

1. `<RUN>_with_software_versions.csv`, if present.
2. Otherwise `<RUN>.csv`.

An invalid versioned report fails the merge; it does not silently fall back to
the primary report. Unrelated CSVs and the duplicate without-versions export are
never included. Missing both exact reports fails QC even when master updates
are skipped.
Both wrappers also pass exactly `report/<RUN>.fasta` to the archive merger;
they do not glob FASTA files or select the separate IUPAC export.
The routine wrapper uses its resolved `RUN_OUT`, including an explicit
`--outdir`; the dedicated FASTA wrapper uses `LOCAL_UPLOAD_RUN` after staging.

The routine wrapper passes `--workflow fastq` normally and `--workflow fasta`
with `--local-fasta`. The dedicated FASTA wrapper always passes `fasta`.
Both pass `--validation`, so validation never updates the master. The routine
offline branch generates local QC before exiting, skips uploads/master access,
and retains local results.

Both wrappers use the shared SMB defaults unless locations are overridden.
Alternatively set `SARSSEQ_MASTER_CSV` to an existing mounted master. `-M` or
explicit `false` disables updates; explicit, unconfigured `auto` reports a skip.
These controls also apply to preflight. The standalone updater retains its
unconfigured `auto` skip. Skipped updates do not require master/metadata files or
master credentials. Wrapper QC still needs the current report CSV and, online,
result-share credentials. A standalone skipped update without `--qc-output`
does not require a report.

The dedicated FASTA wrapper has no offline option; offline FASTA analysis uses
`sarsseq_wrapper.sh -o --local-fasta /path/to/input.fasta`. Offline FASTQ runs
use `--local-fastq-dir` or cached input under `$TMP_DIR/<RUN>` without attempting
an SMB download. Their default samplesheet follows the configured cache root
as `$TMP_DIR/<RUN>.csv`; `--local-samplesheet` overrides it. Offline preflight
still checks the existing local analysis requirements and fails on missing
inputs/resources. It never enables master updates as a fallback.

The updater's nonzero exit stops the wrapper. In the routine wrapper this is
before `wrapper_logs_complete`, so success notification and cleanup are not
reached; logs and staged results are retained by the existing failure path. The
dedicated FASTA wrapper retains its staged results and exits before its final
`Done` message. Already uploaded run files are not rolled back if the subsequent
master update fails. Retry the standalone updater against the retained exact
report and FASTA to avoid rerunning analysis.

Integration tests execute the real wrappers through preflight and their real
post-upload shell sections with synthetic CSVs and stubbed uploads/lifecycle
calls. They cover both report variants, all three workflow entry paths, errors,
skip behavior, explicit output paths, and ordering before completion/cleanup.
The mode tests reproduce Influenza's wrapper test matrix and compare the shared
configuration decisions directly for both workflows, including validation and
invalid settings. Offline tests cover master-access bypass and cached input use.
No sequence analysis or production upload is performed by these tests.

## Master FASTA archive

`--fasta /path/to/report/<RUN>.fasta` merges the completed run into `master.fasta`
beside the configured master CSV. Both SARS wrappers pass this argument. The
archive always uses the master's directory/share/authentication, independently
of the metadata location. Omitting `--fasta` from the standalone updater retains
CSV-only behavior. `-M`, environment modes, validation and routine offline skips
apply to both master updates.

SARS calls the same [FASTA merger](../../fluseq/master_csv/bin/merge_master_fasta.py)
as Influenza. Record matching uses the exact, case-sensitive FASTA ID before
the first whitespace. No specimen-ID translation, suffix removal or sequence
content deduplication is performed. Incoming records replace existing records
with the same ID, including header descriptions; new IDs are appended. Other
records and their ordering remain intact. Different IDs with identical sequence
content remain separate records.

Identical duplicate records within an input file are collapsed. Duplicates with
different sequences or header descriptions fail. A changed incoming record can
replace the same ID in the existing archive; conflicting duplicates *within*
either file cannot be resolved by choosing an arbitrary row. Input supports
UTF-8 BOM, CRLF, multiline records and sequence whitespace. Missing headers,
empty records, sequence-before-header, malformed text and conflicting duplicate
IDs are rejected. Validation follows Influenza's generic FASTA text rules; it
does not apply SARS-specific sequence-quality or biological criteria.

The incoming FASTA is parsed and held in memory before any CSV update. A missing
or malformed run FASTA therefore prevents both writes. An empty run FASTA is a
no-op for the archive: it neither creates nor erases `master.fasta`; the CSV can
still update. An incoming file resolving to the mounted master FASTA is rejected.

The first nonempty run creates a missing archive, provided its directory exists.
For SMB, only `NT_STATUS_OBJECT_NAME_NOT_FOUND` permits initialization; missing
directories, access denials and connection failures abort. An existing empty
archive is also accepted. The archive is read and validated under an exclusive
`master.fasta.lock` directory. Existing locks are never removed by another
invocation; owned locks are released on normal success or error.

Changed existing archives receive a uniquely named
`master.fasta.bak.<UTC timestamp>.<UUID>` backup. Mounted updates verify the
original/backup hashes and use atomic replacement while preserving permissions;
first creation uses an exclusive hard link, so a concurrent initializer cannot
be overwritten. SMB verifies backup and candidate uploads by SHA-256 readback,
checks the original for intervening edits, and verifies the final archive after
server-side rename. First creation uses rename without replacement. Identical
retries preserve the original file formatting and create no additional backup.

CSV and FASTA updates are separate transactions. The CSV can succeed before an
archive-lock, existing-archive validation, upload or replacement failure. Such
failures stop wrapper completion and cleanup. Correct the failure and retry the
same report/FASTA: the CSV becomes a no-op and the archive update can finish.
There is no automatic rollback across the two files. Failed final verification
may occur after replacement; inspect the current archive and verified backup
before retrying. Stale-lock and failed-upload recovery follow the CSV guidance
above, using the archive's own lock and backup filenames.

To update both archives with the configured locations:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq \
  --report /path/to/report/RUN_with_software_versions.csv \
  --fasta /path/to/report/RUN.fasta
```

Use `--workflow fasta` for a FASTA-workflow report. The JSON summary includes a
`fasta` object with added, updated, unchanged, duplicate-collapse and write
counts/status. To update only an archive on a mounted filesystem, the shared
standalone merger is also available:

```bash
python3 fluseq/master_csv/bin/merge_master_fasta.py \
  --master /path/to/data/SC2/master.fasta --fasta /path/to/report/RUN.fasta
```

Tests exercise the SARS entry point and wrapper integration using synthetic
records, alongside Influenza's archive tests. They cover creation, replacement,
duplicate handling, malformed/empty inputs, exact IDs, backups, idempotence,
locks, corrupted transfers, concurrent writers and retries after partial success.
Live SMB deployment acceptance remains outstanding.

## SARS QC HTML and JSON

[sars_qc_report.py](sars_qc_report.py) generates a self-contained HTML report and
companion JSON using the Python standard library. Its styling and review flow
follow the Influenza report: summary cards, finding buttons, a coverage overview,
sample review/detail views, indel viewer, search/filter/sort controls, filtered
CSV exports, full JSON download, and print/PDF styling. The HTML requires no
network requests. Data remains readable without JavaScript; interactive controls
and downloads require it.

| Influenza report feature | SARS counterpart |
| --- | --- |
| Subtype-call yield | Reported lineage-assignment availability, separate from QC |
| Eight-segment coverage | Genome and 12 CDS regions; main sample table shows Genome, S, ORF1a and ORF1b |
| Per-segment Nextclade QC/mixed sites | Genome-level Nextclade QC and mixed-site count |
| Subtype qPCR concordance | SC2 detection results and Ct evidence; no lineage-match claim |
| Indel/frameshift viewer | Existing SARS gene events and genome frameshift fields |
| IRMA noise/read flow, reassortment, Influenza characterisation | Omitted; absent Influenza-only parameters do not create SARS QC flags |

The renderer reads the completed run report. Coverage, mixed sites, QC summaries,
lineage, clade and event data always come from that report, even if an older
master contains better values. The optional master supplies only exact matched
identifiers and SC2 qPCR result/Ct fields. Patient fields, unrelated master rows,
and historical QC are not copied into either output.

### Assessment and missing values

- Default genome and CDS coverage screens are ≥80%. Genome `coverage`,
  `NC_Coverage`, `coverage_stats`, `cdsCoverage`, and `QC_cds_*` have fraction
  units (0–1), converted to percent for display. `QC_overall_pct` is explicitly
  percent (0–100). Units are not guessed from the numeric value. A raw `coverage`
  value of `80` is invalid, while `QC_overall_pct=1` means 1%.
- Genome coverage precedence is `coverage`, `NC_Coverage`, `QC_overall_pct`,
  then `coverage_stats`. For CDS coverage, an explicit `QC_cds_<gene>` column
  precedes the gene's `cdsCoverage` entry. The first present field wins even if
  its cell is blank/invalid. Conflicting valid copies are flagged and retain
  their evidence; a secondary value cannot conceal a missing primary value.
- CDS regions are S, ORF1a, ORF1b, E, M, N, ORF3a, ORF6, ORF7a, ORF7b, ORF8 and
  ORF9b. Semicolon- or comma-separated `gene:fraction` lists are accepted;
  semicolon-separated lists can use decimal commas. Conflicting duplicate gene
  entries are unavailable and flagged. Zero is measured low coverage, not missing.
- Genome mixed sites require a finite, nonnegative integer. Review is triggered
  strictly above 3, following the SARS pipeline's existing threshold. Copies
  (`NC_Genome_MixedSites`, legacy `NC_MixedSItes`,
  `qc.mixedSites.totalMixedSites`) are never summed. First-present precedence,
  invalid values and conflicts are retained in the evidence.
- `NGS_QC_Sum` is preserved. An explicitly empty cell is a known no-flag summary;
  a missing column or `NA`-like value is unavailable. The report's assessment is
  separate from the source summary. It flags low coverage across the full range,
  including zero, even though the upstream CDS summary flags only 10–80%.
- Other review reasons include non-good/missing Nextclade QC, reported QC notes,
  missing mixed-site measurements, reported indels, unavailable indel
  measurements, missing lineage assignments, conflicting/unrecognised qPCR
  results, and reported GISAID comments. Unavailable metrics are never treated
  as zero or passes. Entirely unavailable coverage with no core QC measurements is
  shown as `Unavailable`; an empty report is `Not assessable`.
- Indel/frameshift coordinates and reported drug-review codes are displayed
  without recalculation. No new sequence analysis or clinical susceptibility
  assessment is performed. A reported lineage is not a laboratory acceptance
  decision and may coexist with review flags.

Coverage counts use every source sample row, including rows without a lineage;
pass + low coverage + missing/invalid equals the total for each region. Medians
exclude unavailable values and retain zeros. Controls are not excluded because
control classifications and expected run counts are not supplied. Filtering
changes the displayed/exported rows, not run denominators. CSV export protects
cells that could be interpreted as spreadsheet formulas; HTML escapes source
text, and JSON preserves text without nonfinite numeric values.

### qPCR context and matching

FASTQ matches `Sample` through sequencing identifiers; FASTA also resolves exact
specimen IDs and stored legacy aliases, using the established SARS master rules.
Ambiguous master identifiers or contradictory supplied IDs fail generation.
Both current SARS modes emit `Sample`; legacy FASTA `OriginalName` input is also
supported. Identifiers remain text, preserving leading zeros.

Recognised result fields are `PCR_SC2_EXT_Res`, `PCR_SC2_TRI_Res`, and, if supplied,
`PCR_triplex_SC2_Res`. Their corresponding `_CT` fields are displayed separately.
`Påvist`/`P vist` are recognised as positive and `Ikke påvist`/`Ikke p vist` as
negative, ignoring case and extra whitespace, alongside the existing negative
labels used by Influenza. Original text is retained. Multiple positive SC2 assays
are not a conflict; a mixture of positive and negative results is displayed as
conflicting evidence. Missing, unrecognised and unmatched results remain distinct.
Ct-only metadata is labelled `Ct only`, never inferred positive. The report's
`KonsCt` is displayed separately from master qPCR Ct values. No Ct threshold or
lineage-concordance decision is applied.

### Generate or regenerate locally

Standalone generation does not write to either input:

```bash
python3 sarsseq/master_csv/sars_qc_report.py /path/to/report/RUN.csv \
  --workflow fastq --master /path/to/data/SC2/master.csv \
  --outdir /path/to/local-qc
```

This writes `RUN_qc.html` and `RUN_qc.json`. Use `--workflow fasta` for the FASTA
workflow, or omit `--master` for a report without master/qPCR context. The optional
`--coverage-threshold`, `--cds-threshold`, and `--mixed-threshold` affect only the
report assessment, never source data.

To generate QC after an enabled CSV/FASTA update:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --report /path/to/report/RUN_with_software_versions.csv \
  --fasta /path/to/report/RUN.fasta --qc-output /path/to/local-qc/RUN_qc.html
```

The updater uses the newly updated master, fetching a read-only snapshot when
it is on SMB. It regenerates QC even when the master update is an idempotent
no-op. Its optional threshold flags are `--qc-coverage-threshold`,
`--qc-cds-threshold`, and `--qc-mixed-threshold`.

With updates disabled or a validation flag supplied, `--qc-output` still produces
QC from the current run alone, without accessing a master or FASTA. Configuration
and access-check modes do not generate QC. Invalid threshold/report data and
output collisions are rejected before an enabled master update. A subsequent
render/write/readback failure returns nonzero and may occur after the master
transaction has succeeded; retry safely using the same inputs.

The JSON includes source filename/hash, master label/hash when supplied,
workflow/provenance, thresholds and assessment rules, availability notes, region
summaries and sample evidence. Outputs are prepared in memory and each file is
replaced via a temporary file; the HTML/JSON pair is not a single atomic transaction.

### Automatic QC publishing and recovery

Both wrappers generate `report/<RUN>_qc.html` and `report/<RUN>_qc.json` after
result uploads and enabled master updates. The selected input is the same exact
current-run CSV used by the master updater. The filenames remain `<RUN>_qc.*`
even when the input is `<RUN>_with_software_versions.csv`.

Like Influenza, publishing uses the result share and credentials, independently
of any master-location overrides. Full-run uploads publish QC into
`$SMB_DIR/<RUN>/report`; CSV-only validation uploads use `$SMB_DIR_ANALYSIS`.
The dedicated FASTA wrapper retains its existing full-run destination under
`8-FASTA-ANALYSIS`, including when `-v` skips master updates. The destination
directory must already exist from result upload/setup.

Each file is uploaded and downloaded again for SHA-256 comparison using the
same SMB implementation as Influenza. Nonzero exits, SMB error statuses even
with exit code zero, missing readbacks and checksum mismatches fail the run.
Only verification of both files permits success and the routine wrapper's
existing log archival/cleanup step. A generation or publication failure retains
local results and prevents routine cleanup; the dedicated FASTA wrapper exits
nonzero before its completion message and retains its staging directory.

`-M`, disabled/auto-skipped master updates, and validation still generate and
publish QC without master context. They need the current report CSV but do not
read master/metadata/FASTA inputs. Routine offline mode generates local QC only,
without master access or SMB publication, and retains results. A missing or
malformed report now fails QC even when master updates are skipped.

Wrapper assessment overrides are `SARSSEQ_QC_COVERAGE_THRESHOLD` (default 80),
`SARSSEQ_QC_CDS_THRESHOLD` (80), and `SARSSEQ_QC_MIXED_THRESHOLD` (3). They are
validated before an enabled master update. These settings affect QC assessment
only and do not change the underlying analysis.

For standalone generation and verified publication, including recovery after a
failed wrapper upload:

```bash
SARSSEQ_MASTER_UPDATE=true python3 sarsseq/master_csv/update_master.py \
  --workflow fastq --report /path/to/report/RUN_with_software_versions.csv \
  --fasta /path/to/report/RUN.fasta --qc-output /path/to/report/RUN_qc.html \
  --qc-smb-share '//pos1-fhi-svm01.fhi.no/styrt' \
  --qc-smb-dir 'path/to/existing/RUN/report' \
  --qc-smb-auth /home/ngs/.smbcreds
```

Use the same workflow, master settings and threshold overrides as the original
run. Repeating the unchanged input safely retries master updates and regenerates
QC with master context. Use `SARSSEQ_MASTER_UPDATE=false` for report-only
generation/publication, which omits master/qPCR context. Without the SMB flags,
`--qc-output` stays local. `--check-config` and `--check-access` never generate or
publish QC, including when publishing options are supplied.

Master updates and QC publication are separate operations. A publishing failure
does not undo a completed master update, and HTML/JSON publication is not atomic:
one remote file can have been replaced before the other fails. Retry both files
from the retained run before treating the remote report as complete. A standalone
retry does not itself perform wrapper cleanup. No Influenza wrapper, renderer or
publishing behavior was changed for this integration. Tests use synthetic data
and a simulated SMB endpoint; live production-share acceptance is performed
using the [deployment guide](../DEPLOYMENT.md).
