# Prepare GISAID files

Use the complete checkout at `N:/Virologi/NGS/tmp/ngs_scripts`.
Only samples with a current **Approved** Sequence Review decision are included.
Both scripts run in R, with the existing filters and default settings.

## Run in PowerShell

Paste this once to find R automatically:

```powershell
$Rscript = if (Get-Command Rscript.exe -ErrorAction SilentlyContinue) { (Get-Command Rscript.exe).Source } else { (Get-ChildItem "$env:ProgramFiles\R\R-*\bin\Rscript.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
```

Run the relevant command. Replace only `RUN` and `USER`.

**Influenza**

```powershell
& $Rscript "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/influenza/influenza_gisaid_csv.R" "RUN" "USER"
```

**SC2**

```powershell
& $Rscript "N:/Virologi/NGS/tmp/ngs_scripts/gisaid/sars-cov-2/sc2_gisaid_csv.R" "RUN" "USER"
```

The CSV and FASTA go to the usual N-drive submission folders:

- Influenza: `.../2-Resultater/Influensa/10-GISAID`
- SC2: `.../2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon` (also includes an audit manifest)

These commands prepare files. Upload is a separate step.

Package setup and details: [Influenza](influenza/README_CSV.md) · [SC2](sars-cov-2/README_CSV.md).
Old scripts and historical instructions: [archive](archive/README.md).
