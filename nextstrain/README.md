TODO:
- [ ] Consider changing the reference sequence for alignment. Currently original wuhan is used [https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta](https://github.com/nextstrain/ncov/blob/master/defaults/reference_seq.fasta). Can be specified in the [builds.yaml](builds.yaml) for example.
- [ ] Consider updating/changing the alignment masking. See [sites_ignored_for_tree_topology.txt](sites_ignored_for_tree_topology.txt)
- [ ] The subsampling/filtering of foreign strains can be done smarter in the builds file.

# Step 1: Refresh the list of Pango queries  
First run interactively on the FHI laptop the script [create_pango_queries_for_builds_file.R](create_pango_queries_for_builds_file.R). Copy and paste the list of pangos into the [builds.yaml](builds.yaml) file here:

How to get the latest Pango queries and update the builds file? 

Step 1:  
Download Gisaid fasta and metadata files to N/Virologi/NGS/tmp  

Step 2:  
Run "refresh BN" R-script  

Step 3:  
Move files from N to the server.  
Use script: `get_files_from_N.sh`  
Untar the Gisaid files

Step 4:
Parse Gisaid files

Step 5:
Parse BN files

Step 6:
Run Nextstrain
