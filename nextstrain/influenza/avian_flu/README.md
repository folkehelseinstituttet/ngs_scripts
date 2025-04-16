# H5N1 Full Genome Analysis Pipeline

This pipeline provides a full H5N1 whole-genome analysis by including all available H5N1 sequences, rather than filtering on specific clades. It uses custom configuration and rule files tailored for genome tree construction and requires an empty file (`empty.txt`) for handling dropped strains.

## Features

- **All-inclusive H5N1 Analysis:**  
  Processes every H5N1 sequence (using subtype `h5n1`) for both whole-genome and individual segment analyses. The segments analyzed include:
  - genome
  - pb2, pb1, pa, ha, np, na, mp, ns

- **Custom Configuration & Rules:**  
  - Uses a custom `config.yaml` that defines builds specifically for `h5n1`.
  - Custom Snakemake rules are provided in the `rules` directory (e.g., `config.smk`, `main.smk`, `genome.smk`) to control filtering, alignment, tree building, and export.

- **Empty File for Dropped Strains:**  
  The pipeline expects an entry for `dropped_strains` in the configuration. Instead of filtering out any strains, an empty file (`config/empty.txt`) is used to bypass this step.

## Installation & Setup

To set up and run this pipeline, follow these steps:

### 1. Download the Avian Nextstrain Repository

Clone the original repository:

```bash
git clone https://github.com/nextstrain/avian-flu.git
cd avian-flu
```
### 2. Replace Original Files with Custom Files

#### Configuration:
Replace the default config.yaml with the custom version provided in this setup.

#### Rules:
Overwrite the contents of the rules/ directory (such as config.smk, main.smk, and genome.smk) with the custom versions from this setup.

#### Empty File:
Create an empty file for dropped_strains:

```bash
mkdir -p config
touch config/empty.txt
```

#### Additional Files:
Ensure that any custom reference files (e.g., config/h5n1/h5n1_genome_root.gb) and descriptive files (e.g., config/h5n1/description.md) are available in the proper directories.

### 3. Install Dependencies
Make sure you have the following installed:

  - Snakemake
  - Augur and its dependencies (Python, Pandas, etc.)
  - AWS CLI (if you're interacting with S3)
  - csvtk (for metadata processing)

You can install most Python packages via pip:

```bash
pip install snakemake augur
```

## Running the Pipeline
Once the repository has been updated with the custom files and you have installed the necessary software, run the workflow with:

```bash
snakemake --cores 1 -pf --snakefile genome-focused/Snakefile
```

### Local Data Folder

The pipeline expects a `data/` directory at the project root to store local input files required for the build. This folder should contain any pre-downloaded or curated sequence data and metadata that you want to include in your analysis. Typical contents include:

- `sequences.fasta` – the full set of H5N1 sequences for analysis  
- `metadata.tsv` – metadata file with required columns (e.g., `strain`, `virus_subtype`, `date`, `region`, etc.)  
- Segment-specific reference files, if not placed under `config/` (optional)

Ensure that all file paths referenced in `config.yaml` or the custom rule files correctly point to the files inside the `data/` directory. This setup allows for reproducible local runs without relying on remote data fetching.

