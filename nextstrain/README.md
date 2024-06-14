How to get the latest Pango queries and update the builds file? First run interactively on the FHI laptop the script [create_pango_queries_for_builds_file.R](create_pango_queries_for_builds_file.R). Copy and paste the list of pangos into the [builds.yaml](builds.yaml) file.

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
