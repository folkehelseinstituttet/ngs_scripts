#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run_alignments_and_phylo.sh \
    --fasta-dir /path/to/FASTA \
    --metadata-dir /path/to/META \
    --outdir results/h3n2

Description:
  Orchestrates standalone alignment outputs plus the established run_phylo.sh
  workflow. For each FASTA file, this wrapper writes nucleotide and translated
  amino-acid MAFFT alignments, then runs scripts/run_phylo.sh with the matching
  metadata file.

Options:
  --fasta-dir PATH          Folder containing FASTA files.
  --fasta PATH              Single FASTA file to process instead of --fasta-dir.
  --metadata-dir PATH       Folder containing metadata CSV/TSV files. A file with
                            the same stem as the FASTA is preferred.
  --metadata PATH           Single metadata table to use for every FASTA.
  --outdir PATH             Output directory. Default: results/wrapper-run
  --alignment-method NAME   Alignment method: mafft or nextclade.
                            Default: mafft.
  --nextclade-dataset VALUE Nextclade dataset directory/zip or dataset name.
  --nextclade-dataset-tag   Optional version tag when --nextclade-dataset is
                            a dataset name rather than a local path.
  --nextclade-reference     Custom Nextclade reference FASTA.
  --nextclade-annotation    Custom Nextclade genome annotation in GFF3.
  --nextclade-pathogen-json Optional custom pathogen.json for custom reference
                            mode.
  --influenza-type VALUE    Optional influenza type hint forwarded to
                            run_phylo.sh.
  --segment VALUE           Optional influenza segment hint forwarded to
                            run_phylo.sh.
  --include-nextclade-failed
                            Request inclusion of sequences that fail Nextclade
                            QC. Default: disabled.
  --mafft-bin PATH          MAFFT executable name or path. Default: mafft
  --iqtree-bin PATH         IQ-TREE executable name or path. Default: auto-detect
  --metadata-format NAME    Passed to run_phylo.sh. Default: default
  --seq-len INT             Passed to run_phylo.sh when supplied.
  --clock-root VALUE        Passed to run_phylo.sh when supplied.
  --outgroup LIST           Passed to run_phylo.sh when supplied.
  --display-columns VALUE   Passed to run_phylo.sh. Default: auto
  --aa-gene NAME            Passed to run_phylo.sh for Auspice amino-acid branch
                            mutations. Default: HA
  --aa-frame INT            Passed to run_phylo.sh for Auspice amino-acid branch
                            mutations. Default: 0
  --exclude-ngs-report-no   Passed to run_phylo.sh.
  --recursive               Search --fasta-dir recursively.
  --skip-alignments         Skip standalone alignment outputs.
  --skip-aa-iqtree          Skip IQ-TREE on the amino-acid alignment.
  --skip-phylo              Skip run_phylo.sh.
  --keep-temp               Keep translated amino-acid FASTA intermediates.
  --dry-run                 Print planned work without running commands.
  -h, --help                Show this help.
EOF
}

log() {
  printf '[align+phylo] %s\n' "$*" >&2
}

die() {
  printf '[align+phylo] ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path=$1
  local label=$2
  [[ -f "$path" ]] || die "$label not found: $path"
  [[ -s "$path" ]] || die "$label is empty: $path"
}

require_dir() {
  local path=$1
  local label=$2
  [[ -d "$path" ]] || die "$label not found: $path"
}

need_value() {
  local option=$1
  local remaining=$2
  [[ "$remaining" -ge 2 ]] || die "$option requires a value"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_iqtree() {
  local requested=$1
  if [[ "$requested" != "auto" ]]; then
    command_exists "$requested" || die "Could not find requested IQ-TREE executable: $requested"
    printf '%s\n' "$requested"
    return 0
  fi

  if command_exists iqtree; then
    printf '%s\n' iqtree
  elif command_exists iqtree3; then
    printf '%s\n' iqtree3
  else
    die "Could not find IQ-TREE. Install either 'iqtree' or 'iqtree3', or rerun with --skip-aa-iqtree."
  fi
}

stem() {
  local base
  base=$(basename -- "$1")
  printf '%s' "${base%.*}"
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
RUN_PHYLO="$SCRIPT_DIR/run_phylo.sh"

DEFAULT_FASTA_DIR="/home/rasmuskopperud.riis/Coding/CODEX-projects/IQ-tree_tree_time/FASTA"
DEFAULT_METADATA_DIR="/home/rasmuskopperud.riis/Coding/CODEX-projects/IQ-tree_tree_time/META"

FASTA_DIR=$DEFAULT_FASTA_DIR
FASTA_FILE=""
METADATA_DIR=$DEFAULT_METADATA_DIR
METADATA_FILE=""
OUTDIR="results/wrapper-run"
ALIGNMENT_METHOD="mafft"
NEXTCLADE_DATASET=""
NEXTCLADE_DATASET_TAG=""
NEXTCLADE_REFERENCE=""
NEXTCLADE_ANNOTATION=""
NEXTCLADE_PATHOGEN_JSON=""
INCLUDE_NEXTCLADE_FAILED=0
ANALYSIS_INFLUENZA_TYPE=""
ANALYSIS_SEGMENT=""
MAFFT_BIN="mafft"
IQTREE_BIN="auto"
METADATA_FORMAT="default"
SEQ_LEN=""
CLOCK_ROOT=""
OUTGROUP=""
DISPLAY_COLUMNS="auto"
AA_GENE="HA"
AA_FRAME=0
EXCLUDE_NGS_REPORT_NO=0
RECURSIVE=0
SKIP_ALIGNMENTS=0
SKIP_AA_IQTREE=0
SKIP_PHYLO=0
KEEP_TEMP=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fasta-dir)
      need_value "$1" "$#"
      FASTA_DIR=$2
      shift 2
      ;;
    --fasta)
      need_value "$1" "$#"
      FASTA_FILE=$2
      shift 2
      ;;
    --metadata-dir)
      need_value "$1" "$#"
      METADATA_DIR=$2
      shift 2
      ;;
    --metadata)
      need_value "$1" "$#"
      METADATA_FILE=$2
      shift 2
      ;;
    --outdir)
      need_value "$1" "$#"
      OUTDIR=$2
      shift 2
      ;;
    --alignment-method)
      need_value "$1" "$#"
      ALIGNMENT_METHOD=$2
      shift 2
      ;;
    --nextclade-dataset)
      need_value "$1" "$#"
      NEXTCLADE_DATASET=$2
      shift 2
      ;;
    --nextclade-dataset-tag)
      need_value "$1" "$#"
      NEXTCLADE_DATASET_TAG=$2
      shift 2
      ;;
    --nextclade-reference)
      need_value "$1" "$#"
      NEXTCLADE_REFERENCE=$2
      shift 2
      ;;
    --nextclade-annotation)
      need_value "$1" "$#"
      NEXTCLADE_ANNOTATION=$2
      shift 2
      ;;
    --nextclade-pathogen-json)
      need_value "$1" "$#"
      NEXTCLADE_PATHOGEN_JSON=$2
      shift 2
      ;;
    --influenza-type)
      need_value "$1" "$#"
      ANALYSIS_INFLUENZA_TYPE=$2
      shift 2
      ;;
    --segment)
      need_value "$1" "$#"
      ANALYSIS_SEGMENT=$2
      shift 2
      ;;
    --include-nextclade-failed)
      INCLUDE_NEXTCLADE_FAILED=1
      shift
      ;;
    --mafft-bin)
      need_value "$1" "$#"
      MAFFT_BIN=$2
      shift 2
      ;;
    --iqtree-bin)
      need_value "$1" "$#"
      IQTREE_BIN=$2
      shift 2
      ;;
    --metadata-format)
      need_value "$1" "$#"
      METADATA_FORMAT=$2
      shift 2
      ;;
    --seq-len)
      need_value "$1" "$#"
      SEQ_LEN=$2
      shift 2
      ;;
    --clock-root)
      need_value "$1" "$#"
      CLOCK_ROOT=$2
      shift 2
      ;;
    --outgroup)
      need_value "$1" "$#"
      OUTGROUP=$2
      shift 2
      ;;
    --display-columns)
      need_value "$1" "$#"
      DISPLAY_COLUMNS=$2
      shift 2
      ;;
    --aa-gene)
      need_value "$1" "$#"
      AA_GENE=$2
      shift 2
      ;;
    --aa-frame)
      need_value "$1" "$#"
      AA_FRAME=$2
      shift 2
      ;;
    --exclude-ngs-report-no)
      EXCLUDE_NGS_REPORT_NO=1
      shift
      ;;
    --recursive)
      RECURSIVE=1
      shift
      ;;
    --skip-alignments)
      SKIP_ALIGNMENTS=1
      shift
      ;;
    --skip-aa-iqtree)
      SKIP_AA_IQTREE=1
      shift
      ;;
    --skip-phylo)
      SKIP_PHYLO=1
      shift
      ;;
    --keep-temp)
      KEEP_TEMP=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_file "$RUN_PHYLO" "run_phylo.sh"
if [[ -n "$FASTA_FILE" ]]; then
  require_file "$FASTA_FILE" "FASTA file"
else
  require_dir "$FASTA_DIR" "FASTA directory"
fi
if [[ -n "$METADATA_FILE" ]]; then
  require_file "$METADATA_FILE" "Metadata file"
elif [[ "$SKIP_PHYLO" -ne 1 ]]; then
  require_dir "$METADATA_DIR" "Metadata directory"
fi

if [[ -n "$CLOCK_ROOT" && -n "$OUTGROUP" ]]; then
  die "Use either --clock-root or --outgroup, not both."
fi
case "$ALIGNMENT_METHOD" in
  mafft)
    if [[ -n "$NEXTCLADE_DATASET" ]]; then
      die "--nextclade-dataset is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$NEXTCLADE_DATASET_TAG" ]]; then
      die "--nextclade-dataset-tag is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$NEXTCLADE_REFERENCE" ]]; then
      die "--nextclade-reference is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$NEXTCLADE_ANNOTATION" ]]; then
      die "--nextclade-annotation is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$NEXTCLADE_PATHOGEN_JSON" ]]; then
      die "--nextclade-pathogen-json is only valid with --alignment-method nextclade."
    fi
    if [[ "$INCLUDE_NEXTCLADE_FAILED" -eq 1 ]]; then
      die "--include-nextclade-failed is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$ANALYSIS_INFLUENZA_TYPE" ]]; then
      die "--influenza-type is only valid with --alignment-method nextclade."
    fi
    if [[ -n "$ANALYSIS_SEGMENT" ]]; then
      die "--segment is only valid with --alignment-method nextclade."
    fi
    ;;
  nextclade)
    if [[ -n "$NEXTCLADE_DATASET" ]]; then
      if [[ -n "$NEXTCLADE_REFERENCE" || -n "$NEXTCLADE_ANNOTATION" ]]; then
        die "Use either --nextclade-dataset or --nextclade-reference/--nextclade-annotation, not both."
      fi
      if [[ -n "$NEXTCLADE_PATHOGEN_JSON" ]]; then
        die "--nextclade-pathogen-json is only supported with --nextclade-reference/--nextclade-annotation."
      fi
    else
      [[ -n "$NEXTCLADE_REFERENCE" && -n "$NEXTCLADE_ANNOTATION" ]] || die "--alignment-method nextclade requires either --nextclade-dataset or both --nextclade-reference and --nextclade-annotation."
    fi
    if [[ "$DRY_RUN" -ne 1 ]]; then
      die "Nextclade alignment configuration is recognized, but Nextclade execution is not implemented yet. Use --alignment-method mafft until the Nextclade alignment stage is added."
    fi
    ;;
  *)
    die "--alignment-method must be 'mafft' or 'nextclade', not '$ALIGNMENT_METHOD'."
    ;;
esac
if ! [[ "$AA_FRAME" =~ ^[0-2]$ ]]; then
  die "--aa-frame must be 0, 1, or 2."
fi
[[ -n "$AA_GENE" ]] || die "--aa-gene must not be empty."

RESOLVED_IQTREE_BIN=""
if [[ "$SKIP_AA_IQTREE" -ne 1 && "$DRY_RUN" -ne 1 ]]; then
  RESOLVED_IQTREE_BIN=$(detect_iqtree "$IQTREE_BIN")
fi

mapfile -t FASTA_FILES < <(
  if [[ -n "$FASTA_FILE" ]]; then
    printf '%s\n' "$FASTA_FILE"
  elif [[ "$RECURSIVE" -eq 1 ]]; then
    find "$FASTA_DIR" -type f \( -iname '*.fa' -o -iname '*.fasta' -o -iname '*.fna' -o -iname '*.fas' \) | sort
  else
    find "$FASTA_DIR" -maxdepth 1 -type f \( -iname '*.fa' -o -iname '*.fasta' -o -iname '*.fna' -o -iname '*.fas' \) | sort
  fi
)

[[ "${#FASTA_FILES[@]}" -gt 0 ]] || die "No FASTA files found."

choose_metadata() {
  local fasta=$1
  local fasta_stem
  fasta_stem=$(stem "$fasta")

  if [[ -n "$METADATA_FILE" ]]; then
    printf '%s\n' "$METADATA_FILE"
    return 0
  fi

  local candidate
  for extension in csv tsv txt; do
    candidate="$METADATA_DIR/$fasta_stem.$extension"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  local metadata_files=()
  mapfile -t metadata_files < <(find "$METADATA_DIR" -maxdepth 1 -type f \( -iname '*.csv' -o -iname '*.tsv' -o -iname '*.txt' \) | sort)
  if [[ "${#metadata_files[@]}" -eq 1 ]]; then
    printf '%s\n' "${metadata_files[0]}"
    return 0
  fi

  die "Could not choose metadata for $fasta. Pass --metadata or add a matching metadata file in --metadata-dir."
}

write_translated_fasta() {
  local input_fasta=$1
  local output_fasta=$2
  python3 - "$input_fasta" "$output_fasta" <<'PY_TRANSLATE'
from pathlib import Path
import sys

input_fasta = Path(sys.argv[1])
output_fasta = Path(sys.argv[2])

code = {
    "TTT": "F", "TTC": "F", "TTA": "L", "TTG": "L",
    "TCT": "S", "TCC": "S", "TCA": "S", "TCG": "S",
    "TAT": "Y", "TAC": "Y", "TAA": "*", "TAG": "*",
    "TGT": "C", "TGC": "C", "TGA": "*", "TGG": "W",
    "CTT": "L", "CTC": "L", "CTA": "L", "CTG": "L",
    "CCT": "P", "CCC": "P", "CCA": "P", "CCG": "P",
    "CAT": "H", "CAC": "H", "CAA": "Q", "CAG": "Q",
    "CGT": "R", "CGC": "R", "CGA": "R", "CGG": "R",
    "ATT": "I", "ATC": "I", "ATA": "I", "ATG": "M",
    "ACT": "T", "ACC": "T", "ACA": "T", "ACG": "T",
    "AAT": "N", "AAC": "N", "AAA": "K", "AAG": "K",
    "AGT": "S", "AGC": "S", "AGA": "R", "AGG": "R",
    "GTT": "V", "GTC": "V", "GTA": "V", "GTG": "V",
    "GCT": "A", "GCC": "A", "GCA": "A", "GCG": "A",
    "GAT": "D", "GAC": "D", "GAA": "E", "GAG": "E",
    "GGT": "G", "GGC": "G", "GGA": "G", "GGG": "G",
}

def records(path):
    header = None
    seq = []
    with path.open("r", encoding="utf-8-sig") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    yield header, "".join(seq)
                header = line[1:].strip()
                if not header:
                    raise SystemExit(f"Empty FASTA header at line {line_no}: {path}")
                seq = []
            else:
                if header is None:
                    raise SystemExit(f"Sequence before first FASTA header at line {line_no}: {path}")
                seq.append(line.replace(" ", ""))
    if header is not None:
        yield header, "".join(seq)

def translate_frame(seq, frame):
    clean = seq.upper().replace("U", "T").replace("-", "").replace(".", "").replace("?", "N").replace(" ", "")
    clean = clean[frame:]
    usable = len(clean) - (len(clean) % 3)
    return "".join(code.get(clean[i:i+3], "X") for i in range(0, usable, 3))

def choose_translation(seq):
    candidates = []
    for frame in range(3):
        protein = translate_frame(seq, frame)
        internal = protein[:-1] if protein.endswith("*") else protein
        starts_with_m = 0 if protein.startswith("M") else 1
        candidates.append((internal.count("*"), starts_with_m, protein.count("X"), protein.count("*"), frame, protein))
    _, _, _, _, _, protein = min(candidates)
    if protein.endswith("*"):
        protein = protein[:-1]
    return protein

output_fasta.parent.mkdir(parents=True, exist_ok=True)
count = 0
with output_fasta.open("w", encoding="utf-8", newline="\n") as out:
    for header, seq in records(input_fasta):
        protein = choose_translation(seq)
        out.write(f">{header}\n")
        for i in range(0, len(protein), 80):
            out.write(protein[i:i+80] + "\n")
        count += 1
print(count)
PY_TRANSLATE
}

run_alignment_outputs() {
  local fasta=$1
  local fasta_stem=$2
  local sample_align_dir="$OUTDIR/alignments/$fasta_stem"
  local nucleotide_alignment="$sample_align_dir/$fasta_stem.nucleotide.aligned.fasta"
  local amino_unaligned="$sample_align_dir/$fasta_stem.amino_acid.unaligned.fasta"
  local amino_alignment="$sample_align_dir/$fasta_stem.amino_acid.aligned.fasta"

  mkdir -p "$sample_align_dir"
  log "Creating standalone nucleotide alignment: $nucleotide_alignment"
  "$MAFFT_BIN" --auto "$fasta" > "$nucleotide_alignment"
  local translated_count
  translated_count=$(write_translated_fasta "$fasta" "$amino_unaligned")
  log "Translated $translated_count sequence(s): $amino_unaligned"
  log "Creating standalone amino-acid alignment: $amino_alignment"
  "$MAFFT_BIN" --auto "$amino_unaligned" > "$amino_alignment"
  if [[ "$KEEP_TEMP" -ne 1 ]]; then
    rm -f "$amino_unaligned"
  fi
}

run_amino_acid_iqtree() {
  local amino_alignment=$1
  local fasta_stem=$2
  local aa_tree_dir="$OUTDIR/amino_acid_iqtree/$fasta_stem"
  local aa_tree_prefix="$aa_tree_dir/$fasta_stem.amino_acid"

  require_file "$amino_alignment" "Amino-acid alignment"
  mkdir -p "$aa_tree_dir"
  log "Running IQ-TREE on amino-acid alignment: $amino_alignment"
  "$RESOLVED_IQTREE_BIN" \
    -s "$amino_alignment" \
    -m MFP \
    -alrt 1000 \
    -B 1000 \
    -nt AUTO \
    -pre "$aa_tree_prefix" \
    -redo
}

run_phylo_for_fasta() {
  local fasta=$1
  local metadata=$2
  local fasta_stem=$3
  local phylo_outdir="$OUTDIR/phylo/$fasta_stem"
  local command=(
    bash "$RUN_PHYLO"
    --fasta "$fasta"
    --metadata "$metadata"
    --metadata-format "$METADATA_FORMAT"
    --outdir "$phylo_outdir"
    --display-columns "$DISPLAY_COLUMNS"
    --alignment-method "$ALIGNMENT_METHOD"
    --aa-gene "$AA_GENE"
    --aa-frame "$AA_FRAME"
  )
  if [[ -n "$NEXTCLADE_DATASET" ]]; then
    command+=(--nextclade-dataset "$NEXTCLADE_DATASET")
  fi
  if [[ -n "$NEXTCLADE_DATASET_TAG" ]]; then
    command+=(--nextclade-dataset-tag "$NEXTCLADE_DATASET_TAG")
  fi
  if [[ -n "$NEXTCLADE_REFERENCE" ]]; then
    command+=(--nextclade-reference "$NEXTCLADE_REFERENCE")
  fi
  if [[ -n "$NEXTCLADE_ANNOTATION" ]]; then
    command+=(--nextclade-annotation "$NEXTCLADE_ANNOTATION")
  fi
  if [[ -n "$NEXTCLADE_PATHOGEN_JSON" ]]; then
    command+=(--nextclade-pathogen-json "$NEXTCLADE_PATHOGEN_JSON")
  fi
  if [[ -n "$ANALYSIS_INFLUENZA_TYPE" ]]; then
    command+=(--influenza-type "$ANALYSIS_INFLUENZA_TYPE")
  fi
  if [[ -n "$ANALYSIS_SEGMENT" ]]; then
    command+=(--segment "$ANALYSIS_SEGMENT")
  fi
  if [[ "$INCLUDE_NEXTCLADE_FAILED" -eq 1 ]]; then
    command+=(--include-nextclade-failed)
  fi
  if [[ -n "$SEQ_LEN" ]]; then
    command+=(--seq-len "$SEQ_LEN")
  fi
  if [[ -n "$CLOCK_ROOT" ]]; then
    command+=(--clock-root "$CLOCK_ROOT")
  fi
  if [[ -n "$OUTGROUP" ]]; then
    command+=(--outgroup "$OUTGROUP")
  fi
  if [[ "$EXCLUDE_NGS_REPORT_NO" -eq 1 ]]; then
    command+=(--exclude-ngs-report-no)
  fi

  log "Running established phylogeny workflow for $fasta_stem"
  log "Command: ${command[*]}"
  "${command[@]}"
}

mkdir -p "$OUTDIR"
OUTDIR=$(CDPATH= cd -- "$OUTDIR" && pwd -P)
SUMMARY="$OUTDIR/run_alignments_and_phylo_summary.tsv"
printf 'sample\tfasta\tmetadata\tstandalone_alignment_dir\tamino_acid_iqtree_dir\tphylo_outdir\n' > "$SUMMARY"

log "Project directory: $PROJECT_DIR"
log "Found ${#FASTA_FILES[@]} FASTA file(s)."
log "Alignment method: $ALIGNMENT_METHOD"
if [[ "$ALIGNMENT_METHOD" == "nextclade" ]]; then
  if [[ -n "$NEXTCLADE_DATASET" ]]; then
    log "Nextclade dataset selector: $NEXTCLADE_DATASET"
  else
    log "Nextclade custom reference: $NEXTCLADE_REFERENCE"
    log "Nextclade custom annotation: $NEXTCLADE_ANNOTATION"
  fi
  if [[ -n "$NEXTCLADE_DATASET_TAG" ]]; then
    log "Nextclade dataset tag: $NEXTCLADE_DATASET_TAG"
  fi
  if [[ -n "$NEXTCLADE_PATHOGEN_JSON" ]]; then
    log "Nextclade pathogen JSON: $NEXTCLADE_PATHOGEN_JSON"
  fi
  if [[ -n "$ANALYSIS_INFLUENZA_TYPE" ]]; then
    log "Requested influenza type hint: $ANALYSIS_INFLUENZA_TYPE"
  fi
  if [[ -n "$ANALYSIS_SEGMENT" ]]; then
    log "Requested segment hint: $ANALYSIS_SEGMENT"
  fi
  log "Include Nextclade-failed sequences: $INCLUDE_NEXTCLADE_FAILED"
fi
if [[ "$SKIP_AA_IQTREE" -ne 1 && "$DRY_RUN" -ne 1 ]]; then
  log "Detected IQ-TREE executable for amino-acid tree: $RESOLVED_IQTREE_BIN"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "Dry run requested."
fi

for fasta in "${FASTA_FILES[@]}"; do
  fasta_stem=$(stem "$fasta")
  metadata=""
  if [[ "$SKIP_PHYLO" -ne 1 ]]; then
    metadata=$(choose_metadata "$fasta")
  fi

  log "Processing $fasta_stem"
  log "FASTA: $fasta"
  if [[ -n "$metadata" ]]; then
    log "Metadata: $metadata"
  fi

  if [[ "$DRY_RUN" -ne 1 && "$SKIP_ALIGNMENTS" -ne 1 ]]; then
    run_alignment_outputs "$fasta" "$fasta_stem"
  fi
  aa_iqtree_dir=""
  if [[ "$SKIP_AA_IQTREE" -ne 1 ]]; then
    aa_iqtree_dir="$OUTDIR/amino_acid_iqtree/$fasta_stem"
  fi
  if [[ "$DRY_RUN" -ne 1 && "$SKIP_AA_IQTREE" -ne 1 ]]; then
    run_amino_acid_iqtree "$OUTDIR/alignments/$fasta_stem/$fasta_stem.amino_acid.aligned.fasta" "$fasta_stem"
  fi
  if [[ "$DRY_RUN" -ne 1 && "$SKIP_PHYLO" -ne 1 ]]; then
    run_phylo_for_fasta "$fasta" "$metadata" "$fasta_stem"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$fasta_stem" \
    "$fasta" \
    "$metadata" \
    "$OUTDIR/alignments/$fasta_stem" \
    "$aa_iqtree_dir" \
    "$OUTDIR/phylo/$fasta_stem" >> "$SUMMARY"
done

log "Wrote summary: $SUMMARY"
