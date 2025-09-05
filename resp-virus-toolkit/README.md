# resp-virus-toolkit

Utilities for routine analysis of respiratory virus data.

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

