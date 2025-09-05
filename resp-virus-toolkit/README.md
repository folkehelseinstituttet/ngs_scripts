# resp-virus-toolkit

Utilities for routine analysis of respiratory virus data.

---

## 1 — Primer Checker

**Purpose.** Run primer checks for Influenza, SARS‑CoV‑2, and RSV across provided FASTAs, generating CSV reports suitable for dashboards and QA. Strict subtype routing for Influenza keeps H1/H3/B separated.  
Analysis is based on: https://github.com/RasmusKoRiis/primer-checker

### What the wrapper does
1. Activate `PRIMER_CHECK`; verify `smbclient`, `git`, `python3`, `blastn`.  
2. Sync `~/ngs_scripts` and `~/primer-checker` (simple pull, reclone if needed).  
3. Fetch `primer.json` from the N‑drive (overrides any repo copy).  
4. Recursively fetch `.fa|.fasta|.fna` from the N‑drive input folder.  
5. Classify files by virus; **Influenza** is split per file into **H1**, **H3**, **B**, or **A (fallback)**.  
6. Run `primer_checker.py` for each group, writing CSV reports.  
7. Upload all CSVs + `RUN_LOG_<stamp>.txt` to a timestamped subfolder next to the inputs.

### Run
```bash
./primer_check_wrapper.sh
```

### Outputs
- Local: `/mnt/tempdata/flu_toolkit_out/`
- Uploaded: `\\Pos1-fhi-svm01\styrt\Virologi\NGS\tmp\flu_toolkit\primer_check_<YYYYMMDD_HHMMSS>`
- Files: 
  - `YYYY-MM-DD_Influenza-H1_primer_report.csv`
  - `YYYY-MM-DD_Influenza-H3_primer_report.csv`
  - `YYYY-MM-DD_Influenza-B_primer_report.csv`
  - `YYYY-MM-DD_SARS-CoV-2_primer_report.csv`
  - `YYYY-MM-DD_RSV-*.csv`
  - `RUN_LOG_<stamp>.txt` (includes SHAs + `primer.json` MD5)

### Notes
- Influenza headers should include a recognizable segment token (e.g., `-HA-`, `-M-`) so segment filtering in Python works as intended.
- Unknown Influenza files default to **A** panel.

### Prerequisites
- Conda env: `PRIMER_CHECK` with `python`, `blast` (BLAST+), `git`
- System package: `smbclient`

### Config (defaults inside `primer_check_wrapper.sh`)
- **Repos:**  
  - `~/ngs_scripts` (auto-updated)  
  - `~/primer-checker` (auto-updated), entrypoint: `primer_checker.py`
- **Primer DB (from N-drive):**  
  `Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/primercheck_db/primer.json`  
  → staged at `/mnt/tempdata/primercheck_db/primer.json`
- **FASTA inputs (from N-drive):**  
  `Virologi/NGS/tmp/flu_toolkit` → staged at `/mnt/tempdata/flu_toolkit/`
- **Outputs (local → upload back):**  
  local `/mnt/tempdata/flu_toolkit_out/` → `\\Pos1-fhi-svm01\styrt\Virologi\NGS\tmp\flu_toolkit\primer_check_<YYYYMMDD_HHMMSS>`

### Input conventions
- FASTA extensions considered: `.fa`, `.fasta`, `.fna`
- **Influenza subtype routing** is inferred **per file** using filename and header hints:  
  `H1` → H1 panel, `H3` → H3 panel, `IBV`/type‑B → B panel, otherwise fall back to **A**.
- The Python script filters by **segment** (e.g., HA, M). Use headers that include a recognizable token like `-HA-`, `-M-`, `PB1`, `NS` to ensure the right primers hit the right sequences.

### Logs & provenance
- `RUN_LOG_<stamp>.txt` records commit SHAs for `ngs_scripts` and `primer-checker`, plus MD5 of `primer.json`.
- CSVs are dated; uploads land in a unique timestamped folder to avoid overwrites.

### Exit behavior
- Exits non‑zero on: missing tools, failed Conda activation, or missing `primer.json`.
- If no FASTAs are found, exits cleanly after logging (no reports generated).
