# GENERATING NEXTSTRAIN-TREES

# Table of Contents
1. [Influenza](#influenza)
2. [SARS-CoV-2](#sars-cov-2)

# Influenza

### Open the excel submission log document
Missing log file!

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
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Using PowerShell on a FHI laptop, run the script `influenza_gisaid.R` by typing in:
```
& "C:\Program Files\R\R-4.3.0\bin\Rscript.exe" ".\influenza\influenza_gisaid.R" "RUNID"
```
Remeber to replace RUNID with run-id for samples you want to submit.

This should create a directory with today's date here: `N:\Virologi\NGS\1-NGS-Analyser\1-Rutine\2-Resultater\Influensa\10-GISAID`.  
That directory should contain two files. One csv file with metadata and one fasta file.

### Upload to Gisaid (Windows)  
Upload to GISAID using version 4 of the cli.

No need do naviagte and clone repo if already done.

Using PowerShell, naviagte to N:\Virologi\NGS\tmp 
```
cd N:\Virologi\NGS\tmp
```
Using PowerShell on a FHI laptop, clone the repo:
```
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git
```
Using PowerShell, naviagte into gisaid-repo:
```
cd .\ngs_scripts\gisaid\
```
Prepare a "credentials.txt" file with this content and format and save at `.\ngs_scripts\gisaid\`:
```
password=your_password
clientid=your_clientid
```
Run submission-script:
```
.\influenza\GISAID_INF_submission.ps1 -m "metadata.csv" -f "sequences.fasta" -c "credentials.txt" -u "username"
```
If .\GISAID_INF_submission.ps1 is not executable try `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process`


# SARS-CoV-2

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
