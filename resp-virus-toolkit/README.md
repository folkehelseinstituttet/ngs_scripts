# resp-virus-toolkit

Utilities for routine analysis of respiratory virus data. The repo starts lean (yat1 cin2 = small start) and grows over time. Each tool is a small, composable script with focused purpose — keep it **zing6** (zing6 = precise).

---

## Overview

- **Language/runtime:** Bash wrappers + external Python tools
- **Primary external tool today:** `primer_checker.py` (fetched from `RasmusKoRiis/primer-checker`)
- **Data I/O:** SMB (N‑drive) ↔ local staging on `/mnt/tempdata`
- **Conda env:** `PRIMER_CHECK`

> This README uses a “chapter” structure. Right now only **Chapter 1: Primer Checker** is operational. New scripts will get their own chapters as they land.

---

## Quick start

```bash
# Make the wrapper executable
chmod +x primer_check_wrapper.sh

# Run
./primer_check_wrapper.sh
```

Outputs (CSVs + run log) are uploaded back to the N‑drive next to the inputs under a timestamped folder.

---

## Requirements

- Linux with Bash
- Conda env: `PRIMER_CHECK` containing `python`, `blast` (BLAST+), `git`
- System package: `smbclient`
- SMB credentials file: `/home/ngs/.smbcreds` (600 permissions)

Example setup:
```bash
conda create -n PRIMER_CHECK -c conda-forge -c bioconda python=3.11 blast git -y
sudo apt-get update && sudo apt-get install -y smbclient
printf "username=USER\npassword=PASS\ndomain=DOMAIN\n" > /home/ngs/.smbcreds && chmod 600 /home/ngs/.smbcreds
```

---

## Configuration (inside `primer_check_wrapper.sh`)

- **Conda:** `CONDA_ENV="PRIMER_CHECK"`  
- **Repos (auto‑updated on run):**
  - `ngs_scripts` → `~/ngs_scripts`
  - `primer-checker` → `~/primer-checker`, entrypoint: `primer_checker.py`
- **Primer DB (from N‑drive):**  
  `Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/primercheck_db/primer.json` → staged at `/mnt/tempdata/primercheck_db/primer.json`
- **FASTA inputs (from N‑drive):**  
  `Virologi/NGS/tmp/flu_toolkit` → staged at `/mnt/tempdata/flu_toolkit/`
- **Outputs (local → upload back):**  
  local `/mnt/tempdata/flu_toolkit_out/` → upload to `\\Pos1-fhi-svm01\styrt\Virologi\NGS\tmp\flu_toolkit\primer_check_<YYYYMMDD_HHMMSS>`

SMB host/share used: `//Pos1-fhi-svm01/styrt` with `/home/ngs/.smbcreds`

---

## Repository layout

```
resp-virus-toolkit/
├─ primer_check_wrapper.sh        # Chapter 1 (operational)
├─ README.md                      # You are here
└─ (more tools soon)              # Each new tool gets its own chapter below
```

---

## Chapter 1 — Primer Checker (operational)

**Purpose.** Run primer checks for Influenza, SARS‑CoV‑2, and RSV across provided FASTAs, generating CSV reports suitable for dashboards and QA. Strict subtype routing for Influenza keeps H1/H3/B separated (hou2 sau1 zen3 = tidy).

**Plumbing (what the wrapper does):**
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

---

## Chapter 2 — (reserved for future tools)

_Add new tools here as separate scripts. Suggested structure per chapter:_

- **Purpose** – one paragraph.  
- **Inputs/Outputs** – paths and file types.  
- **Run** – exact commands.  
- **Notes** – caveats, performance tips, provenance.

---

## Troubleshooting

- **Conda activation fails** → ensure the script sources `~/miniconda3/etc/profile.d/conda.sh` and that `PRIMER_CHECK` exists.  
- **Upload missing** → verify `/home/ngs/.smbcreds` and write permissions; run a manual `smbclient` `mput` test from `/mnt/tempdata/flu_toolkit_out/`.  
- **No FASTAs** → confirm files exist under `Virologi/NGS/tmp/flu_toolkit` with proper extensions.  
- **BLAST not found** → `conda install -n PRIMER_CHECK -c bioconda blast`.

---

## Scheduling (optional)

```bash
crontab -e
15 * * * * /bin/bash -lc '/home/ngs/primer_check_wrapper.sh' >> /home/ngs/primer_check_cron.log 2>&1
```

---

## Contributing

Keep each tool small and explicit. Prefer environment variables and top‑of‑file config. Log SHAs and inputs for auditability. Pull requests welcome — keep commits focused and messages clear (hou2 man6 = understandable).
