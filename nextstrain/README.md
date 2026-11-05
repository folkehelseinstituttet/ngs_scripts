# GENERATING NEXTSTRAIN-TREES

# Table of Contents
1. [Influenza](#influenza)
2. [RSV](#rsv)
3. [SARS-CoV-2](#sars-cov-2)

# Influenza

### Prepare input files (PowerShell)
Prerequisite: PowerShell, R and git.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into nextstrain-repo:
```
cd .\ngs_scripts\nextstrain\influenza
```
Using PowerShell on a FHI laptop, run the script `INF.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" "INF.R"
```
This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\11-Nextstrain`.  
That directory should contain three directories (H1, H3 and VIC) which each should contain three files.

### Prepare influenza input from the FluSeq master CSV and FASTA

`INF_master_csv.R` is an alternative to `INF.R`. It reads `master.csv` and
`master.fasta` from the FluSeq master directory and uses the semicolon-delimited
`Innsender_GISAID.csv` lookup in the GISAID directory. It requires the R package
`writexl`, plus `jsonlite` and `digest` for Sequence Review approval checks.
It runs entirely in R, without Node.js or Python. From the repository's
`nextstrain/influenza` directory, run:

```powershell
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" "INF_master_csv.R"
```

In RStudio, from any working directory:

```r
install.packages(c("jsonlite", "digest", "writexl")) # once, if missing
nextstrain_args <- character() # defaults; alternatively c("--master", "C:/data/INF/master.csv", ...)
source("N:/Virologi/NGS/tmp/ngs_scripts/nextstrain/influenza/INF_master_csv.R", encoding = "UTF-8")
```

Keep the complete `ngs_scripts` checkout, including `gisaid/shared/approval.R`.
The script locates it from the source path, repository working directories or the
standard N-drive checkout. `GISAID_SHARED_DIR` can explicitly select another
complete shared directory. It rejects the older Node-based helper.

Only rows with a **current, conflict-free Approved decision** in Sequence Review
are eligible. The R reader uses `config.json` and `reviews/` beside the selected
master, applies approved manual overrides, and excludes unreviewed, outdated,
conflicting, rejected and follow-up rows. A QC-assessment CSV cell does not
replace a review. Missing or invalid review storage stops the export; there is
no bypass. Approval is checked again before creating output or staging files.
See the [shared approval rules](../gisaid/shared/README.md). The GISAID
exporter's RunID and comment exclusions are not applied to Nextstrain inputs.

It writes the same dated output directory and H1, H3 and VIC file names as
`INF.R`: `metadata.xlsx`, `raw_sequences_ha.fasta`, and
`raw_sequences_na.fasta`. It copies the files to `N:\Virologi\NGS\tmp\flu_nextstrain`
for the existing wrapper. Existing files with those names are overwritten, as
with the original script.

For testing with other input files and output directories, specify paths:

```powershell
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" "INF_master_csv.R" `
  --master "C:\test\master.csv" --fasta "C:\test\master.fasta" `
  --lab "C:\test\Innsender_GISAID.csv" `
  --output "C:\test\output" --staging "C:\test\staging"
```

If `--fasta` is omitted it defaults to `master.fasta` beside `master.csv`.
The lookup matches master `Prove_Innsender_ID` to `Innsender_nr` as text and
uses the corresponding `GISAID_Id` as `Originating_Lab`. Missing matches or
empty GISAID IDs use the existing default `3869` and are counted in the log.
The script uses eligible H1N1, H3N2 and B/Victoria rows in the master, skips
rows without a `Key`, and matches FASTA sample identifiers exactly against the
original master's sequencing and other sample IDs, before manual overrides.
Ambiguity is checked against all master rows, including excluded samples. Ambiguous matches and duplicate
sample/segment records stop the build. It reports records with no matching
sample and eligible samples without a FASTA record. The master FASTA only
contains sequences that have been added to that archive; older sequences may
need to be added before the new files contain the same historical data as
the previous workflow. The original source script's additional selection
criteria are not bundled in this repository and cannot be verified here.
`INF.R` and `INF_wholegenome.R` remain legacy SQL workflows and do not implement
this approval gate; use `INF_master_csv.R` for approved master-based inputs.

### Build Nextstrain-tree (VM)

Using PowerShell, log on the server. 
After a sucessful log-in write the command under in the terminal window.
```
cd $HOME
```
If ngs_script-directory dosent exist:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Start Nextstrain-script with:
```
bash ngs_scripts/nextstrain/influenza/wrapper.sh
```
This will save the Nextstrain-tree files at N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\11-Nextstrain\{DATE}_Nextstrain_Build

All *json files can uploaded to https://auspice.us/ for analysis. 

# RSV

### Prepare input files (PowerShell)
Prerequisite: PowerShell, R and git.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into nextstrain-repo:
```
cd .\ngs_scripts\nextstrain\rsv
```
Using PowerShell on a FHI laptop, run the script `RSV.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" "RSV.R"
```
This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\RSV\11-Nextstrain`.  

### Build Nextstrain-tree (VM)

Using PowerShell, log on the server following the description in 702-VIN-AR-032-document. 
After a sucessful log-in write the command under in the terminal window.
```
cd $HOME
```
If ngs_script-directory dosent exist:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Start Nextstrain-script with:
```
bash ngs_scripts/nextstrain/rsv/wrapper.sh
```
This will save the Nextstrain-tree files at N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\RSV\11-Nextstrain\{DATE}_Nextstrain_Build

All *json files can uploaded to https://auspice.us/ for analysis. 

# SARS-CoV-2

For approved, R-only master inputs use
[`sars-cov-2/SC2_META.R`](sars-cov-2/README.md#approved-master-based-inputs-r-only).
The BN workflow below is legacy and does not apply the Sequence Review approval gate.


After files are created delete the `ngs_scripts` folder in `N:\Virologi\NGS\tmp`.TODO:
- [X] Update (colors_norwaydivisions.tsv)[colors_norwaydivisions.tsv] with new counties.
- [ ] Fix the naming scheme of the Nextstrain build files
- [ ] Consider changing the reference sequence for alignment. Currently original wuhan is used [https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta](https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta). Can be specified in the [builds.yaml](builds.yaml) for example.
- [ ] Consider updating/changing the alignment masking. See [sites_ignored_for_tree_topology.txt](sites_ignored_for_tree_topology.txt)
- [ ] The subsampling/filtering of foreign strains can be done smarter in the builds file.
- [ ] Automate the creation of Pango queries to filter the dataset. See Step 1.
- [ ] Automate the cleaning of `N/Virologi/NGS/tmp`. See Step 2.

# Step 1: Refresh the list of Pango queries  
First run interactively on the FHI laptop the script [create_pango_queries_for_builds_file.R](create_pango_queries_for_builds_file.R).  Copy and paste the list of pangos into the [builds.yaml](builds.yaml) file [here](https://github.com/folkehelseinstituttet/ngs_scripts/blob/main/nextstrain/builds.yaml#L42). Do it in the web browser and commit the file.  

This should probably be automated. See [here](https://discussion.nextstrain.org/t/methods-to-automate-the-list-of-pangos-for-augur-filter/1665). One idea is to store the pangos in a separate file, then in the Snakefile read that file the same way as the builds.yaml is read via `['builds']`. 

# Step 2: Download Gisaid files  
Download Gisaid fasta and metadata files and move to `N:\Virologi\NGS\tmp`. Remember to delete files from this folder after the build is finished. Should probably be automated. Can perhaps be done with `smbclient` from the server side after the files are moved. 

# Step 3: Get data from BN    
On a FHI laptop, run the R-script `N:\Virologi\JonBrate\Prosjekter\refresh_data_from_BN.R`. This should put a file called `BN.RData` in `N:\Virologi\NGS\tmp`.  
Command: `source("N:/Virologi/JonBrate/Prosjekter/refresh_data_from_BN.R")`

# Step 4: Make the Nextstrain build
Log on to the `ngs-worker-1` VM.  
Swith to the `ngs` user with `sudo -u ngs /bin/bash`  
Run the wrapper script with `nohup bash /ngs_scripts/nexstrain/wrapper.sh &`  
It will run in the background and you can log out. It takes ca. 2 hours to complete. 

# Step 5: Upload the build to Nextstrain.org  
Log on to the VM. Without switching to the ngs user, copy the three `.json` files in `/mnt/tempdata/ncov/auspice/` to N with `sudo cp /mnt/tempdata/ncov/auspice/*.json /mnt/N/Virologi/NGS/tmp/`.  
You need to have a Nextstrain account and to remember your credentials. And make sure there are no old build files in `/home/ngs/ncov/auspice/`.  
```bash
nextstrain login
nextstrain remote upload nextstrain.org/groups/niph /home/ngs/ncov/auspice/*.json
```
