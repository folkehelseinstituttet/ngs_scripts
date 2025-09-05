# resp-virus-toolkit

Utilities for routine analysis of respiratory virus data.

---

## 1-Primer Checker 

**Purpose.** Run primer checks for Influenza, SARS‑CoV‑2, and RSV across provided FASTAs, generating CSV reports suitable for dashboards and QA. Strict subtype routing for Influenza keeps H1/H3/B separated.

**What the wrapper does:**
1) Activate `PRIMER_CHECK`; verify `smbclient`, `git`, `python3`, `blastn`.  
2) Sync `~/ngs_scripts` and `~/primer-checker` (simple pull, reclone if needed).  
3) Fetch `primer.json` from the N‑drive (overrides any repo copy).  
4) Recursively fetch `.fa|.fasta|.fna` from the N‑drive input folder.  
5) Classify files by virus; **Influenza** is split per file into **H1**, **H3**, **B**, or **A (fallback)**.  
6) Run `primer_checker.py` for each group, writing CSV reports.  
7) Upload all CSVs + `RUN_LOG_<stamp>.txt` to a timestamped subfolder next to the inputs.

**Run.**
```bash
./primer_check_wrapper.sh
```

**Outputs.**
- Local: `/mnt/tempdata/flu_toolkit_out/`
- Uploaded: `\\Pos1-fhi-svm01\styrt\Virologi\NGS\tmp\flu_toolkit\primer_check_<YYYYMMDD_HHMMSS>`
- Files: 
  - `YYYY-MM-DD_Influenza-H1_primer_report.csv`
  - `YYYY-MM-DD_Influenza-H3_primer_report.csv`
  - `YYYY-MM-DD_Influenza-B_primer_report.csv`
  - `YYYY-MM-DD_SARS-CoV-2_primer_report.csv`
  - `YYYY-MM-DD_RSV-*.csv`
  - `RUN_LOG_<stamp>.txt` (includes SHAs + `primer.json` MD5)

**Notes.**
- Influenza headers should include a recognizable segment token (e.g., `-HA-`, `-M-`) so segment filtering in Python works as intended.
- Unknown Influenza files default to **A** panel (jat1 ci3 = sensible default).



