# Approved master-based inputs (R only)

`SC2_META.R` reads the SC2 `master.csv`, matching `master.fasta`, and the
semicolon-delimited `Innsender_GISAID.csv` lookup. It requires R packages
`jsonlite` and `digest`. It does not need Node.js, Python or a SQL connection.
Keep the complete `ngs_scripts` checkout, including `gisaid/shared/approval.R`
and `gisaid/sars-cov-2/sc2_export.R`.

```powershell
Rscript "N:/Virologi/NGS/tmp/ngs_scripts/nextstrain/sars-cov-2/SC2_META.R"
# Optional minimum date and custom inputs/output:
Rscript "N:/Virologi/NGS/tmp/ngs_scripts/nextstrain/sars-cov-2/SC2_META.R" --min-date "2025-01-01" --master "C:/data/SC2/master.csv" --lab "C:/data/Innsender_GISAID.csv" --output "C:/nextstrain-inputs"
```

In RStudio, from any working directory:

```r
install.packages(c("jsonlite", "digest")) # once, if missing
nextstrain_args <- c("--min-date", "2025-01-01")
source("N:/Virologi/NGS/tmp/ngs_scripts/nextstrain/sars-cov-2/SC2_META.R", encoding = "UTF-8")
```

Only **current, conflict-free Approved** Sequence Review decisions pass. The
script reads `config.json` and `reviews/` beside the selected master and applies
current approved overrides before the existing Nextstrain selection: collection
date strictly after the minimum (default `2025-01-01`) and finite `NC_Coverage`
at least `0.75`. Blank keys are skipped. The first positional date is also
accepted for older command lines. No GISAID-specific run or comment filter is
added to Nextstrain.

Missing/invalid approval storage stops the export. Unreviewed, outdated,
conflicting, rejected and follow-up samples are excluded. A CSV QC assessment
alone is not approval. Master/review inputs are checked again before writing;
master, configuration and review files remain read-only. See the
[shared rules](../../gisaid/shared/README.md).

The FASTA is matched exactly against original identifiers, including aliases
of excluded master samples when checking ambiguity. Approved metadata overrides
do not change FASTA identity matching. Every selected row must match one FASTA
record, and duplicate isolate names fail. The original naming convention
`hCoV-19/Norway/<last four Key characters>/<year>` and metadata column order are
retained; metadata and FASTA include exactly the same selected samples.

Default files are `nextstrain_metadata_YYYY-MM-DD.tsv` and
`nextstrain_fasta<week>-<year>.fasta` under the existing
`N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-Nextstrain`
directory. Existing files with those names are overwritten. `--fasta` selects
an archive other than `master.fasta` beside the master. The lookup supplies
originating lab names; `GISAID_Isolate_ID` supplies accessions when available.
Shared code is found from the full source path, repository working directories
or the standard N-drive checkout; `GISAID_SHARED_DIR` can override the shared
location.

The BN/tree-building instructions below describe the legacy workflow and do
not apply the master-based approval gate.


TODO:
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
Run the wrapper script with `nohup bash /ngs_scripts/nextstrain/sars-cov-2/wrapper.sh &`  
It will run in the background and you can log out. It takes ca. 2 hours to complete. 

# Step 5: Upload the build to Nextstrain.org  
Log on to the VM. Without switching to the ngs user, copy the three `.json` files in `/mnt/tempdata/ncov/auspice/` to N with `sudo cp /mnt/tempdata/ncov/auspice/*.json /mnt/N/Virologi/NGS/tmp/`.  
You need to have a Nextstrain account and to remember your credentials. And make sure there are no old build files in `/home/ngs/ncov/auspice/`.  
```bash
nextstrain login
nextstrain remote upload nextstrain.org/groups/niph /home/ngs/ncov/auspice/*.json
```
