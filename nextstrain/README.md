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
Run the wrapper script with `nohup /home/ngs/ngs_scripts/nexstrain/wrapper.sh &`  
It will run in the background and you can log out. It takes ca. 2 hours to complete. 

# Step 5: Upload the build to Nextstrain.org  
Log on to the VM. Without switching to the ngs user, copy the three `.json` files in `/mnt/tempdata/ncov/auspice/` to N with `sudo cp /mnt/tempdata/ncov/auspice/*.json /mnt/N/Virologi/NGS/tmp/`.  
You need to have a Nextstrain account and to remember your credentials. And make sure there are no old build files in `/home/ngs/ncov/auspice/`.  
```bash
nextstrain login
nextstrain remote upload nextstrain.org/groups/niph /home/ngs/ncov/auspice/*.json
```
