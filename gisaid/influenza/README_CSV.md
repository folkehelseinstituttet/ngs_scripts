# Influenza GISAID scripts for master.csv

The original SQL-based `influenza_gisaid.R` is unchanged. The new scripts use
`master.csv` by default from
`N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF/`.
Pass a different master path where shown below. Paths containing spaces must be
quoted in PowerShell.

## Prepare a submission

Install Node.js 18+ and R packages `readr`, `dplyr`, `tidyr`, `tibble`, `purrr`,
`stringr`, `magrittr` and `lubridate` (an existing `tidyverse` installation supplies
the relevant packages), then run:

```powershell
Rscript .\influenza\influenza_gisaid_csv.R "RUNID"
# Optional alternative master path:
Rscript .\influenza\influenza_gisaid_csv.R "RUNID" "C:\path\to\master.csv"
# Optional lab lookup and output directory; existing defaults are retained:
Rscript .\influenza\influenza_gisaid_csv.R "RUNID" "C:\data\INF\master.csv" "C:\data\Innsender_GISAID.csv" "C:\submission-review"
```

The standard code location is `N:/Virologi/NGS/tmp/ngs_scripts`. Store the complete
checkout there, keeping the folder name `ngs_scripts`. In the R/RStudio console:

```r
gisaid_args <- c("RUNID")
source("N:/Virologi/NGS/tmp/ngs_scripts/gisaid/influenza/influenza_gisaid_csv.R")
# Optional paths use the same order as the command-line arguments:
# gisaid_args <- c("RUNID", "C:/data/INF/master.csv", "C:/data/Innsender_GISAID.csv", "C:/submission-review")
```

The full `source()` path locates the shared helpers even when the working directory
is elsewhere. When running selected lines instead, the script also checks
`N:/Virologi/NGS/tmp/ngs_scripts/gisaid/shared` automatically, so no working-directory
or helper-path setting is needed for the standard installation. Source-relative
and repository working-directory detection still support other checkouts. An
explicit `GISAID_SHARED_DIR` overrides detection and must be valid. For another layout, set
`Sys.setenv(GISAID_SHARED_DIR = "C:/path/to/ngs_scripts/gisaid/shared")` before
running the code. Keep all shared files together. These launch methods still use
the Node.js approval reader described below.

Only samples with a **current, conflict-free Approved decision in Sequence
Review** are eligible. The exporter reads `config.json` and `reviews/` beside
the selected master. Missing approval storage fails; unreviewed, outdated,
conflicting, rejected and follow-up decisions are excluded. There is no bypass.
Current approved manual overrides are applied before the existing metadata and
QC filters. A CSV `NGS_QC_Assessment` value alone does not establish approval.
See the [shared approval rules](../shared/README.md), including legacy IDs and
the `GISAID_NODE` executable override. Master and reviews remain read-only.

The script reads FASTA files (`.fasta`, `.fa`, `.fna` or `.fas`) in the same
folder as the master. The first `|`-delimited header field must match the master
`NGS_LW_ID`; the second identifies the segment, for example
`>2820073-INFA|01-HA-H1N1`. The script uses the corresponding master `Key` in
the submission. Eligible rows with an empty or whitespace-only `Key` are skipped
and counted in the console output; duplicate nonempty keys still cause an error.
If every eligible row lacks a key, the script stops without a submission. `M` is
converted to `MP`. Matching duplicate sample/segment
records cause an error. The script
filters the run, keeps the existing subtype/result and GISAID-comment exclusions,
and applies the existing `NGS_QC_Sum` rules to both the metadata
and the output FASTA. The metadata and FASTA are written to the original
`10-GISAID` output directory, using the original week-based filenames. Running
again in the same week overwrites those output files. The existing `Innsender_GISAID.csv` lookup remains necessary.
Known damaged county names `Tr ndelag`, `M re g Romsdal`, and ` stfold` are
also repaired in the submission CSV, including when reading an older master.
Approval/master inputs are checked again before output. Regenerate after any
later result or review changes. The legacy SQL-based exporter does not implement
this gate; use `influenza_gisaid_csv.R` for the approved master-based workflow.

## Import accession IDs

Install R packages `readxl` and `readr`. Download influenza A and B using
GISAID's **Isolate as XLS (virus metadata only)** export, then pass either or
both files to the importer in one command:

```powershell
Rscript .\influenza\import_gisaid_epi_csv.R "C:\path\to\influenza_A.xls" "C:\path\to\influenza_B.xls"
# Optional alternative master path:
Rscript .\influenza\import_gisaid_epi_csv.R --master "C:\path\to\master.csv" "C:\path\to\influenza_A.xls" "C:\path\to\influenza_B.xls"
```

The importer matches `Submitting_Sample_Id` exactly to master `Key`, writes
isolate ID and name and extracts segment accessions from the pipe-delimited
export fields. Export rows with a blank `Submitting_Sample_Id` and IDs not found
in the master are skipped and reported in the console; matching IDs can still be
imported. The `MP` segment maps to `GISAID_M_ID`. Blank export values leave
existing values untouched. Duplicate master keys, conflicting values and
malformed segment identifiers stop the import before replacement.
Identical imports do not rewrite the master. A successful update creates a
backup beside the master and uses the same `master.csv.lock` directory as the
FluSeq master updater. If the lock is held, the importer waits up to 30 seconds
by default; set `GISAID_LOCK_WAIT_SECONDS` to change this (or to `0` to fail
immediately). Normal completion and errors release the importer's lock. An
interrupted process may leave it behind; the importer never removes an existing
lock automatically because another computer may be using it. Other programs that do not use the lock must not edit the
master concurrently. Windows replacement requires the shared filesystem to
support `System.IO.File.Replace`; an error does not fall back to deleting the
master. If interrupted, check the master and backup before retrying and remove
a stale lock only after confirming no writer is active.
