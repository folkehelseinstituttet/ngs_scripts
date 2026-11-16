# HA-only wrapper: H5N1 and H5N5

`wrapper_avian_ha.sh` builds separate H5N1 and H5N5 HA datasets from an
already prepared metadata TSV and HA FASTA. Both subtypes must have matching
records dated 2024 or later; subsequent workflow filters also apply.

```bash
# Download the prepared TSV and HA FASTA from the existing SMB source and build:
bash wrapper_avian_ha.sh
# Or supply the prepared files locally:
bash wrapper_avian_ha.sh --prepare-only metadata.tsv sequences_ha.fasta
bash wrapper_avian_ha.sh --dry-run metadata.tsv sequences_ha.fasta
bash wrapper_avian_ha.sh metadata.tsv sequences_ha.fasta
```

With no input paths, the wrapper downloads exactly `metadata.tsv` and
`sequences_ha.fasta` from
`//pos1-fhi-svm01.fhi.no/styrt/Virologi/NGS/tmp/avianflu_nextstrain`, using
`~/.smbcreds`. This is the whole-genome wrapper's source folder, but the HA
wrapper requires the prepared TSV and HA-only FASTA, not Excel or multi-segment
inputs. Override `SMB_HOST`, `SMB_SOURCE`, or `SMB_AUTH` when needed.

`PROJECT_DIR` defaults to `~/avian_project`. The wrapper expects its upstream
checkout in `$PROJECT_DIR/avian-flu` and clones it if absent. Existing checkouts
are not updated. Set `PROJECT_DIR` to change that base folder, or set `AVIAN_REPO`
separately. These settings do not move files.
Each run is saved under `RUN_ROOT` (default `~/avianflu_ha_runs`).

The default Conda environment is `AVIAN_HA`; it must satisfy the version
requirements of the chosen upstream checkout. Set `CONDA_ENV=''` to use the
active environment instead. The checkout inspected during development requires
Augur 34.1.2 or newer.

On a machine with the existing `SNAKEMAKE` environment (including MAFFT and
IQ-TREE), create the separate HA environment once:

```bash
conda create --name AVIAN_HA --clone SNAKEMAKE --yes
conda run --name AVIAN_HA python -m pip install 'nextstrain-augur==34.1.2'
```

`--prepare-only` uses standard-library Python and does not require this environment.

Outputs are `auspice/avian-flu_h5n1_ha_local.json` and
`auspice/avian-flu_h5n5_ha_local.json` within the run directory. `--smb` downloads
the two input files; `--upload` uploads both JSON files after a successful build.
H5N5 uses upstream H5Nx HA resources; the upstream workflow does not add clade
labels for the `h5n5` build name.

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




