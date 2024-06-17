TODO:
- [ ] Consider changing the reference sequence for alignment. Currently original wuhan is used [https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta](https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta). Can be specified in the [builds.yaml](builds.yaml) for example.
- [ ] Consider updating/changing the alignment masking. See [sites_ignored_for_tree_topology.txt](sites_ignored_for_tree_topology.txt)
- [ ] The subsampling/filtering of foreign strains can be done smarter in the builds file.
- [ ] Automate the creation of Pango queries to filter the dataset. See Step 1.
- [ ] Automate the cleaning of `N/Virologi/NGS/tmp`. See Step 2.

# Step 1: Refresh the list of Pango queries  
First run interactively on the FHI laptop the script [create_pango_queries_for_builds_file.R](create_pango_queries_for_builds_file.R).  Copy and paste the list of pangos into the [builds.yaml](builds.yaml) file [here](https://github.com/folkehelseinstituttet/ngs_scripts/blob/main/nextstrain/builds.yaml#L42).  

This should probably be automated. See [here](https://discussion.nextstrain.org/t/methods-to-automate-the-list-of-pangos-for-augur-filter/1665).

# Step 2: Download Gisaid files  
Download Gisaid fasta and metadata files and move to `N:\Virologi\NGS\tmp`. Remember to delete files from this folder after the build is finished. Should probably be automated. Can perhaps be done with `smbclient` from the server side after the files are moved. 

# Step 3: Get data from BN    
On a FHI laptop, run the R-script `N:\Virologi\JonBrate\Prosjekter\refresh_data_from_BN.R`. This should put a file called `BN.RData` in `N:\Virologi\NGS\tmp`.

# Step 4:  
Move files from N to the server.  
Use script: `get_files_from_N.sh`  
Untar the Gisaid files

Step 4:
Parse Gisaid files

Step 5:
Parse BN files

Step 6:
Run Nextstrain
