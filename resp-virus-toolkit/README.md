# resp-virus-toolkit

Utilities for routine analysis of respiratory virus data.

## Shared wrapper logging and cleanup

`wrapper_logging.sh` is sourced by the routine `fluseq`, `rsvseq`, and `sarsseq`
wrappers. Deploy it and `wrapper_cleanup.config` together with those wrappers;
keep their relative locations in the `ngs_scripts` checkout.

After argument parsing, each wrapper creates these files in `$HOME` (normally
`/home/ngs` on the server). Set `WRAPPER_LOG_DIR` to use another directory.

| File | Contents |
| --- | --- |
| `<workflow>_<RUN>_wrapper.log` | Wrapper and child-command stdout/stderr |
| `<workflow>_<RUN>_wrapper_error.log` | Timestamped progress, errors and exit status |
| `<workflow>_<RUN>_status.txt` | Timestamped progress and exit status |
| `<workflow>_<RUN>_nextflow.log` | Nextflow diagnostics, including pull/run/cleanup |

`<workflow>` is `fluseq`, `rsvseq`, or `sarsseq`. Logging starts before conda
initialization, downloads and repository updates. Help and influenza's standalone
`--check-references` mode do not create run logs. Argument-parsing errors happen
before logging starts. Missing run names use `unknown-<PID>` for validation logs.

Output remains visible in the terminal or `screen` session. For example:

```bash
tail -f "$HOME/fluseq_INF077_status.txt"
tail -f "$HOME/fluseq_INF077_wrapper.log"
```

Retries append to wrapper/status history and retain Nextflow's numbered rotated
logs. A per-workflow/run lock prevents simultaneous wrappers from mixing the same
log files. The empty `<workflow>_<RUN>.lock` file is intentionally retained; its
lock is released automatically on exit.

### Archive destinations

Routine runs upload logs to `<existing result destination>/<RUN>/logs` on N:.
Validation runs (`-v`) upload them to `<validation destination>/<RUN>/logs`,
alongside the existing CSV upload behaviour. Numbered Nextflow logs and associated
`nf-<id>-reports.tsv` manifests are included. Manifest IDs are taken from this
run's current/rotated Nextflow logs; unrelated runs' manifests are left alone.
Seqera monitoring is optional and is not enabled by the logging helper.

SARS offline runs (`-o`) write copies to `<local output>/logs` and keep the
original logs, local results, input and work files. Explicit SARS `--outdir`
directories and user-provided input files are also retained.

### Cleanup policy used by all three wrappers

1. Complete pipeline processing and all required result/CSV/database uploads.
   Upload command failures, including reported SMB errors with a zero process
   exit status, prevent cleanup.
2. Flush console logging, upload a log snapshot, download each uploaded log and
   compare its bytes. A failed or incomplete archive prevents cleanup.
3. For successful online runs, clean only the Nextflow session UUID recorded in
   the run log, the downloaded `<TMP_DIR>/<RUN>` folder and the run's samplesheet.
   If the UUID cannot be identified, retain Nextflow work rather than guessing
   the most recent session. Other runs and database/resource caches are retained.
4. Remove staged routine results after their uploads and the initial log archive
   have succeeded. Validation results are retained because only selected CSVs
   were uploaded. Explicit SARS output directories are retained too.
5. Upload and verify the final logs again, including cleanup messages, then
   remove the corresponding local log files and staged log copies.

`wrapper_cleanup.config` disables the pipelines' automatic work cleanup so the
wrapper can apply this ordering. Failed/interrupted processing, result uploads or
initial log verification retain local logs and data. If cleanup or the final log
upload fails after cleanup has begun, remaining logs/data are retained and the
wrapper exits nonzero; already removed files are not restored. The initial log
archive was verified before cleanup began, but a failed final transfer can leave
an incomplete remote update; use the retained local logs for diagnosis.
Only the log files receive
byte-for-byte read-back verification; result uploads use SMB status/error checks.

The final console confirmation of successful log verification/deletion appears
after the archived log is closed. Small temporary archive directories may remain
if local snapshot creation itself fails. Logs are never deleted on the strength
of an unverified upload.

Requirements: Bash 4.4+, GNU `tee`, `flock`, `smbclient`, `cmp`, and the standard
Linux file utilities. `CONDA_PROFILE` can override the conda initialization script
in all three wrappers.

### Teams completion and failure notifications

The same helper sends one Adaptive Card when an online wrapper exits, using the
[Teams incoming webhook format](https://learn.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/add-incoming-webhook).
Success is reported only after required result uploads, verified log archival and
cleanup finish. Failures during setup, Nextflow, result uploads, log uploads or
cleanup are reported with the failing stage and exit code. The card includes the
workflow, run, host, pipeline branch/tag, start/finish times, duration, log location
and the last six wrapper status messages from this attempt. Caught `INT`, `TERM`
and `HUP` signals also produce failure notifications. A forced kill or host outage
cannot run the exit handler.

Create the URL files as the server account that runs the wrappers (normally
`ngs`). Each file contains its Teams Workflows webhook URL on a single line:

| Wrapper | Default private URL file |
| --- | --- |
| Influenza (`fluseq`) | `~/.teams_webhook_inf` |
| RSV (`rsvseq`) | `~/.teams_webhook_rsv` |
| SARS-CoV-2 (`sarsseq`) | `~/.teams_webhook_sars` |

```bash
umask 077
nano ~/.teams_webhook_inf
nano ~/.teams_webhook_rsv
nano ~/.teams_webhook_sars
chmod 600 ~/.teams_webhook_inf ~/.teams_webhook_rsv ~/.teams_webhook_sars
```

Use the same URL in multiple files if they should post to the same Teams
destination. `TEAMS_WEBHOOK_FILE=/path/to/file` overrides the default for a run.
Keep these URL files outside the repository; they are not included in log uploads.
Notifications require `curl` and `python3`. A missing/unreadable URL file, missing
notification dependency, or delivery error prints a console notice and preserves
the wrapper's exit code. Delivery has a 15-second timeout and no automatic retries.
The URL is not printed or passed in curl's process arguments.

Append **`-t`** to any of the three wrappers to suppress Teams during testing.
This only disables notifications: processing, uploads and cleanup still run as
usual. SARS also accepts `--test`, and `-o`/`--offline` always suppresses Teams.
Validation (`-v VER`) still sends notifications, marked as validation; add `-t`
alongside it to suppress them. Help, argument-parsing errors, rejected duplicate
runs and influenza's standalone reference check do not send notifications.

Notification delivery happens after log finalization, so its delivery notice is
console-only and does not recreate deleted logs or change the archive on N:.

Run the isolated lifecycle tests from the repository root:

```bash
python3 -m pytest -q resp-virus-toolkit/tests/test_wrapper_logging.py
```

---

## 1 — Primer Checker

**Purpose.** Run primer checks for Influenza, SARS‑CoV‑2, and RSV across provided FASTAs, generating CSV reports for dashboards and QA. Strict subtype routing for Influenza keeps H1/H3/B separated.  
Analysis code is sourced from a dedicated repository: <https://github.com/RasmusKoRiis/primer-checker>

### What the wrapper does
1. Activate `PRIMER_CHECK`; verify `smbclient`, `git`, `python3`, `blastn`.  
2. Sync local copies of `ngs_scripts` and `primer-checker` (auto‑pull with safe reclone fallback).  
3. Fetch `primer.json` from the N‑drive (overrides any local/repo copy).  
4. Recursively fetch `.fa|.fasta|.fna` from the N‑drive input folder.  
5. Classify files by virus; **Influenza** is split per file into **H1**, **H3**, **B**, or **A (fallback)**.  
6. Run `primer_checker.py` for each group, writing CSV reports.  
7. Upload all CSVs + `RUN_LOG_<stamp>.txt` to a timestamped folder next to the inputs on the N‑drive.

### Run
```bash
./primer_check_wrapper.sh
```

### Outputs
- Local: `<LOCAL_STAGING_DIR>/flu_toolkit_out/`
- Uploaded: `\\SERVER\SHARE\PATH\primer_check_<YYYYMMDD_HHMMSS>`
- Files: 
  - `YYYY-MM-DD_Influenza-H1_primer_report.csv`
  - `YYYY-MM-DD_Influenza-H3_primer_report.csv`
  - `YYYY-MM-DD_Influenza-B_primer_report.csv`
  - `YYYY-MM-DD_SARS-CoV-2_primer_report.csv`
  - `YYYY-MM-DD_RSV-*.csv`
  - `RUN_LOG_<stamp>.txt` (includes commit SHAs + `primer.json` MD5)

### Notes
- Influenza headers should include a recognizable segment token (e.g., `-HA-`, `-M-`, `PB1`, `NS`) so segment filtering in Python works as intended.
- Unknown Influenza files default to **A** panel.

### Prerequisites
- Conda env: `PRIMER_CHECK` with `python`, `blast` (BLAST+), `git`
- System package: `smbclient`

### Config (defaults inside `primer_check_wrapper.sh`)
- **Repos (auto‑updated):**  
  - `~/ngs_scripts`  
  - `~/primer-checker`, entrypoint: `primer_checker.py`
- **Primer DB (from N‑drive):**  
  `<N_DRIVE_PRIMER_DB_DIR>/primer.json` → staged at `<LOCAL_STAGING_DIR>/primercheck_db/primer.json`
- **FASTA inputs (from N‑drive):**  
  `<N_DRIVE_INPUT_DIR>` → staged at `<LOCAL_STAGING_DIR>/flu_toolkit/`
- **Outputs (local → upload back):**  
  local `<LOCAL_STAGING_DIR>/flu_toolkit_out/` → `\\SERVER\SHARE\PATH\primer_check_<YYYYMMDD_HHMMSS>`

### Input conventions
- FASTA extensions considered: `.fa`, `.fasta`, `.fna`
- **Influenza subtype routing** is inferred **per file** using filename and header hints:  
  `H1` → H1 panel, `H3` → H3 panel, `IBV`/type‑B → B panel, otherwise fall back to **A**.
- The Python script filters by **segment** (e.g., HA, M). Use headers that include a recognizable token to ensure correct primer‑to‑segment pairing.

---

## Placeholders (replace with your environment)

- `<LOCAL_STAGING_DIR>` — local base path for staging and outputs (e.g., `/mnt/tempdata`)
- `<N_DRIVE_INPUT_DIR>` — N‑drive path where FASTAs appear (SMB folder)
- `<N_DRIVE_PRIMER_DB_DIR>` — N‑drive path containing `primer.json`
- `\\SERVER\SHARE\PATH\...` — UNC path to the SMB location where outputs are uploaded

---

