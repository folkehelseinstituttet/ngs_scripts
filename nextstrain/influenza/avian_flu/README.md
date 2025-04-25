# Nextstrain H5N1 Whole-Genome Wrapper

This README explains how to set up and run the **Nextstrain H5N1 whole-genome wrapper** (`wrapper_avian_full_genome.sh`) to perform a full avian-flu build, including:

- Downloading metadata and FASTA from an SMB share  
- Converting and cleaning metadata  
- Splitting FASTA by segment  
- Running the customized Nextstrain avian-flu Snakemake pipeline  
- Uploading results back to the SMB share  

---

## Table of Contents

1. [Prerequisites](#prerequisites)  
2. [Directory Layout](#directory-layout)  
3. [Configuration](#configuration)  
4. [Setup](#setup)  
5. [Running the Wrapper](#running-the-wrapper)  
6. [Output](#output)  
7. [Troubleshooting](#troubleshooting)  

---

## Prerequisites

- **Linux** system with network access to the SMB share  
- **Miniconda/Anaconda** installed under `$HOME/miniconda3`  
- **Permissions** to read/write on the SMB share and `/mnt/tempdata`  

### Required Commands

| Command     | Purpose                                            |
|-------------|----------------------------------------------------|
| `git`       | Clone & update repos                               |
| `smbclient` | Download/upload files via SMB                      |
| `conda`     | Activate the Snakemake environment                 |
| `python3`   | Run metadata conversion & FASTA-splitting scripts  |
| `snakemake` | Execute the Nextstrain build pipeline              |

---

## Directory Layout

By default, the wrapper uses:

- **Base scratch area:** `/mnt/tempdata`  
- **Raw input dir:** `/mnt/tempdata/avianflu_nextstrain`  
- **Output JSON dir:** `/mnt/tempdata/avianflu_nextstrain_out/YYYY-MM-DD`  
- **Local Nextstrain repo:** `/mnt/tempdata/avian-flu`  
- **Helper scripts repo:** `~/ngs_scripts/nextstrain/influenza/avian_flu`

Feel free to adjust these paths by editing the variables at the top of the wrapper script.

---

## Configuration

Customize the following before running:

1. **SMB settings** (in wrapper):
   ```bash
   SMB_HOST="//Pos1-fhi-svm01/styrt"
   SMB_AUTH="$HOME/.smbcreds"
   SMB_SOURCE="Virologi/NGS/tmp/avianflu_nextstrain"
   SMB_TARGET="Virologi/NGS/.../Nextstrain_Build"
   ```

2. Conda env name:
  
  ```bash
  CONDA_ENV="SNAKEMAKE"
   ```

3. Overlay directory (your custom scripts & configs):
  ```bash
  FHI_OVERLAY="$HOME/ngs_scripts/nextstrain/influenza/avian_flu"
   ```
Ensure your overlay folder mirrors the target structure in the cloned avian-flu repo:

  ```bash
 avian_flu/
├── h5n1/                          # Custom h5n1 configs & queries
├── genome-focused/
│   ├── config.yaml                # Overrides genome-focused/config.yaml
│   └── Snakefile                  # Overrides genome-focused/Snakefile
└── rules/
    ├── genome.smk                 # Overrides rules/genome.smk
    └── main.smk                   # Overrides rules/main.smk

   ```


## Setup
1. Activate your conda base & install Snakemake (if not already done):
   
  ```bash
  conda activate base
  conda install -c conda-forge snakemake
   ```
2. Clone helper scripts (if missing):
   
 ```bash
git clone https://github.com/folkehelseinstituttet/ngs_scripts.git ~/ngs_scripts
 ```

3. Make wrapper executable:
   
 ```bash
chmod +x ~/ngs_scripts/nextstrain/influenza/wrapper_avian_full_genome.sh
 ```

## Running the Wrapper
From anywhere (no need for sudo):
   
```bash
bash ~/ngs_scripts/nextstrain/influenza/wrapper_avian_full_genome.sh [metadata.xls sequences.fasta]
 ```
- During execution, you’ll see logs for:
- Updating repos
- Fetching from SMB
- Converting metadata & splitting FASTA
- Launching Snakemake
- Uploading results




