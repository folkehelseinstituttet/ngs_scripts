First log on to `up-ngs-4`.  

Then switch to the ngs-user: `sudo -u ngs /bin/bash`  

Then start the download, for example like this:    
`bash /home/ngs/ngs_scripts/basespace/basespace.sh -p nextseq -y 2024 -r NGS_SEQ-20241031-01 -d b`

---

### Argument descriptions

- `-h, --help`        Display help message
- `-p, --platform`    Platform: nextseq (for Bacteriology, both for NextSeq550 and NextSeq1000), miseq, or nextseq_virus (only for NextSeq1000 and Virology)
- `-r, --run`         Run name (e.g. NGS_SEQ-20240606-01)
- `-y, --year`        Year sequencing was performed (e.g. 2024). Decides which result folder fastq files will end up in. 
- `-d, --department`  Department: b (bacteriology) or v (virology)
