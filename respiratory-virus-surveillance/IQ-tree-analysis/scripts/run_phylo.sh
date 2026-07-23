#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run_phylo.sh \
    --fasta data/sequences.fasta \
    --metadata data/metadata.tsv \
    --metadata-format default \
    --outdir results \
    --seq-len 1700 \
    [--clock-root least-squares] \
    [--display-columns auto] \
    [--alignment-method mafft|nextclade] \
    [--nextclade-dataset NAME_OR_PATH] \
    [--nextclade-dataset-tag TAG] \
    [--nextclade-reference reference.fasta] \
    [--nextclade-annotation genome_annotation.gff3] \
    [--nextclade-pathogen-json pathogen.json] \
    [--influenza-type A|B|C|D] \
    [--segment HA] \
    [--include-nextclade-failed] \
    [--force-align]

Description:
  Version 1 viral tip-dated phylogeny workflow using IQ-TREE and TreeTime.
  The workflow validates the FASTA and metadata, derives TreeTime-ready dates,
  aligns sequences with the selected method, infers a maximum-likelihood tree with IQ-TREE,
  runs TreeTime clock analysis, runs TreeTime timetree inference, and enriches
  Auspice output with selected metadata when available.

Options:
  --fasta PATH              Input FASTA file. Default: data/sequences.fasta
  --metadata PATH           Input metadata table. Default: data/metadata.tsv
  --metadata-format NAME    Metadata parser to use. Default: default
  --outdir PATH             Output directory. Default: results
  --seq-len INT             Sequence length for TreeTime clock analysis.
                            If omitted, the aligned sequence length is used.
  --clock-root VALUE        TreeTime rerooting mode. Examples:
                            least-squares, min_dev, oldest, keep, or a tip name.
                            Comma-separated tip names are treated as an outgroup.
  --outgroup LIST           Comma-separated tip names to pass to TreeTime as
                            an explicit outgroup. Cannot be combined with
                            --clock-root.
  --display-columns VALUE   Metadata columns to add to visualization outputs.
                            Use 'auto' (default), 'none', or a comma-separated
                            list of metadata header names.
  --alignment-method NAME   Alignment method: mafft or nextclade.
                            Default: mafft.
  --nextclade-dataset VALUE Nextclade dataset directory/zip or dataset name.
                            Optional when using --nextclade-reference and
                            --nextclade-annotation instead.
  --nextclade-dataset-tag   Optional version tag when --nextclade-dataset is
                            a dataset name rather than a local path.
  --nextclade-reference     Custom Nextclade reference FASTA. Use together
                            with --nextclade-annotation when no dataset exists.
  --nextclade-annotation    Custom Nextclade genome annotation in GFF3.
  --nextclade-pathogen-json Optional custom pathogen.json for custom reference
                            mode.
  --influenza-type VALUE    Optional influenza type hint for Nextclade
                            reporting.
  --segment VALUE           Optional influenza segment hint for Nextclade
                            reporting.
  --include-nextclade-failed
                            Request inclusion of sequences that fail Nextclade
                            QC. Default: disabled.
  --aa-gene NAME            Protein/gene key for Auspice amino-acid branch
                            mutations. Default: HA.
  --aa-frame INT            Coding frame offset for amino-acid mutation calls:
                            0, 1, or 2. Default: 0.
  --exclude-ngs-report-no   Exclude rows where metadata column NGS_Report is NO.
                            Default: disabled.
  --force-align             Accepted for compatibility. The workflow always runs
                            the selected aligner before IQ-TREE.
  --help                    Show this help message and exit.

Notes:
  - The default metadata parser currently supports tab-, comma-, and semicolon-
    delimited text files.
  - FASTA headers are matched exactly against the selected metadata identifier
    column. Headers containing whitespace are rejected to avoid downstream
    naming issues in IQ-TREE and TreeTime.
  - Samples without a usable sampling date are skipped, reported, and excluded
    from alignment, IQ-TREE, and TreeTime.
  - In Nextclade mode, the script supports three input styles: a downloaded
    dataset directory/zip, a dataset name plus optional tag, or a custom
    reference FASTA plus genome annotation.
  - Optional influenza type/segment hints are accepted for reporting, but
    dataset-target validation is not enforced automatically.
  - In Nextclade mode, the date-qualified FASTA is analyzed with Nextclade,
    optionally filtered by QC, and the accepted aligned FASTA is passed to
    IQ-TREE and TreeTime.
  - When TreeTime writes an Auspice JSON, the workflow can enrich terminal
    nodes with retained metadata such as geography, age, host, HA subclade, or lab.
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

warn() {
  log "WARNING: $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_readable_file() {
  local path=$1
  local label=$2
  [[ -f "$path" ]] || die "$label not found: $path"
  [[ -r "$path" ]] || die "$label is not readable: $path"
  [[ -s "$path" ]] || die "$label is empty: $path"
}

ensure_parent_dir() {
  local path=$1
  local parent
  parent=$(dirname "$path")
  mkdir -p "$parent"
}

detect_python() {
  if command_exists python3; then
    echo "python3"
  elif command_exists python; then
    echo "python"
  else
    die "Python is required for metadata/date parsing and FASTA validation."
  fi
}

detect_iqtree() {
  if command_exists iqtree; then
    echo "iqtree"
  elif command_exists iqtree3; then
    echo "iqtree3"
  else
    die "Could not find IQ-TREE. Install either 'iqtree' or 'iqtree3'."
  fi
}

detect_cpu_count() {
  if command_exists nproc; then
    nproc
  elif command_exists getconf; then
    getconf _NPROCESSORS_ONLN
  else
    echo "1"
  fi
}

trim_whitespace() {
  local value=$1
  printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

build_treetime_root_args() {
  TREETIME_ROOT_ARGS=()

  if [[ -n "${CLOCK_ROOT:-}" && -n "${OUTGROUP:-}" ]]; then
    die "Use either --clock-root or --outgroup, not both."
  fi

  if [[ -n "${OUTGROUP:-}" ]]; then
    IFS=',' read -r -a _root_items <<<"$OUTGROUP"
    local _clean_items=()
    local _item
    for _item in "${_root_items[@]}"; do
      _item=$(trim_whitespace "$_item")
      [[ -n "$_item" ]] || continue
      _clean_items+=("$_item")
    done
    [[ ${#_clean_items[@]} -gt 0 ]] || die "--outgroup requires at least one tip name."
    TREETIME_ROOT_ARGS=(--reroot "${_clean_items[@]}")
    TREETIME_ROOT_DESC="explicit outgroup: ${_clean_items[*]}"
    return 0
  fi

  if [[ -z "${CLOCK_ROOT:-}" ]]; then
    TREETIME_ROOT_ARGS=(--reroot least-squares)
    TREETIME_ROOT_DESC="least-squares"
    return 0
  fi

  if [[ "$CLOCK_ROOT" == "keep" ]]; then
    TREETIME_ROOT_ARGS=(--keep-root)
    TREETIME_ROOT_DESC="keep existing root"
    return 0
  fi

  IFS=',' read -r -a _root_items <<<"$CLOCK_ROOT"
  local _clean_items=()
  local _item
  for _item in "${_root_items[@]}"; do
    _item=$(trim_whitespace "$_item")
    [[ -n "$_item" ]] || continue
    _clean_items+=("$_item")
  done
  [[ ${#_clean_items[@]} -gt 0 ]] || die "--clock-root requires a non-empty value."
  TREETIME_ROOT_ARGS=(--reroot "${_clean_items[@]}")
  TREETIME_ROOT_DESC="${_clean_items[*]}"
}

validate_fasta_and_collect_stats() {
  local fasta=$1
  local names_out=$2
  local summary_out=$3

  "$PYTHON_BIN" - "$fasta" "$names_out" "$summary_out" <<'PY'
import re
import statistics
import sys

fasta_path, names_out, summary_out = sys.argv[1:4]

headers = []
lengths = []
duplicate_headers = set()
header_seen = set()
current_header = None
current_seq = []
sequence_chars = re.compile(r'^[A-Za-z\-\.\*\?]+$')
line_number = 0

def fail(message):
    raise SystemExit(message)

def flush_record():
    global current_header, current_seq
    if current_header is None:
        return
    seq = ''.join(current_seq).strip()
    if not seq:
        fail(f"FASTA record '{current_header}' does not contain sequence characters.")
    if not sequence_chars.fullmatch(seq):
        fail(
            f"FASTA record '{current_header}' contains unsupported characters. "
            "Expected letters, '-', '.', '*', or '?'."
        )
    headers.append(current_header)
    lengths.append(len(seq))
    current_seq = []

with open(fasta_path, 'r', encoding='utf-8') as handle:
    for raw_line in handle:
        line_number += 1
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith('>'):
            flush_record()
            header = line[1:].strip()
            if not header:
                fail(f"Encountered an empty FASTA header at line {line_number}.")
            if re.search(r'\s', header):
                fail(
                    f"FASTA header '{header}' contains whitespace. "
                    "Use simple whitespace-free identifiers so they match metadata exactly."
                )
            if header in header_seen:
                duplicate_headers.add(header)
            header_seen.add(header)
            current_header = header
        else:
            if current_header is None:
                fail("FASTA sequence data appeared before the first header line.")
            current_seq.append(line.replace(' ', '').upper())

flush_record()

if not headers:
    fail("No FASTA records were found in the input file.")

if duplicate_headers:
    dup_list = ', '.join(sorted(duplicate_headers)[:10])
    fail(f"Duplicate FASTA headers detected: {dup_list}")

all_same_length = len(set(lengths)) == 1
any_gap = False
with open(fasta_path, 'r', encoding='utf-8') as handle:
    any_gap = any('-' in line for line in handle if not line.startswith('>'))

appears_aligned = all_same_length

with open(names_out, 'w', encoding='utf-8') as handle:
    for header in headers:
        handle.write(f"{header}\n")

with open(summary_out, 'w', encoding='utf-8') as handle:
    handle.write("metric\tvalue\n")
    handle.write(f"sequence_count\t{len(headers)}\n")
    handle.write(f"min_length\t{min(lengths)}\n")
    handle.write(f"max_length\t{max(lengths)}\n")
    handle.write(f"median_length\t{int(statistics.median(lengths))}\n")
    handle.write(f"all_same_length\t{str(all_same_length).lower()}\n")
    handle.write(f"any_gap_characters\t{str(any_gap).lower()}\n")
    handle.write(f"appears_aligned\t{str(appears_aligned).lower()}\n")
    if appears_aligned and not any_gap:
        note = (
            "All sequences have the same length but no gaps were observed. "
            "The workflow will treat this as aligned unless --force-align is used."
        )
    elif appears_aligned:
        note = "All sequences have the same length and the FASTA appears aligned."
    else:
        note = "Sequence lengths differ, so the FASTA does not appear aligned."
    handle.write(f"note\t{note}\n")
PY
}

derive_dates_from_metadata() {
  local metadata=$1
  local metadata_format=$2
  local dates_out=$3
  local audit_out=$4
  local summary_out=$5
  local skipped_out=$6
  local exclude_ngs_report_no=$7

  "$PYTHON_BIN" - "$metadata" "$metadata_format" "$dates_out" "$audit_out" "$summary_out" "$skipped_out" "$exclude_ngs_report_no" <<'PY'
import csv
import datetime as dt
import math
import re
import sys
from pathlib import Path

metadata_path, metadata_format, dates_out, audit_out, summary_out, skipped_out, exclude_ngs_report_no = sys.argv[1:8]
exclude_ngs_report_no = exclude_ngs_report_no.lower() == "true"

if metadata_format != "default":
    raise SystemExit(
        f"Unsupported metadata format '{metadata_format}'. "
        "Version 1 currently supports only '--metadata-format default'."
    )

ID_CANDIDATES = [
    "sample_id",
    "sequence_name",
    "strain",
    "sample",
    "name",
    "taxon",
    "id",
    "accession",
    "key",
]
DATE_CANDIDATES = [
    "collection_date",
    "specimen_date",
    "isolation_date",
    "sample_date",
    "sampling_date",
    "collection_dato",
    "prove_tatt",
    "date",
]
NA_VALUES = {"", "na", "n/a", "nan", "none", "null", "missing", "unknown", "unk"}

def normalize_header(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value

def choose_delimiter(path: str) -> str:
    with open(path, "r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            line = raw_line.strip("\n\r")
            if line.strip():
                counts = {delim: line.count(delim) for delim in ("\t", ";", ",")}
                best = max(counts, key=counts.get)
                if counts[best] > 0:
                    return best
                break
    raise SystemExit(
        "Could not detect the metadata delimiter. Expected a tab-, semicolon-, "
        "or comma-delimited text file with a header row."
    )

def decimal_year_from_datetime(ts: dt.datetime) -> float:
    year_start = dt.datetime(ts.year, 1, 1)
    next_year = dt.datetime(ts.year + 1, 1, 1)
    return ts.year + ((ts - year_start).total_seconds() / (next_year - year_start).total_seconds())

def midpoint_decimal_year_for_year(year: int) -> float:
    start = dt.datetime(year, 1, 1)
    end = dt.datetime(year + 1, 1, 1)
    midpoint = start + (end - start) / 2
    return decimal_year_from_datetime(midpoint)

def midpoint_decimal_year_for_month(year: int, month: int) -> float:
    start = dt.datetime(year, month, 1)
    if month == 12:
        end = dt.datetime(year + 1, 1, 1)
    else:
        end = dt.datetime(year, month + 1, 1)
    midpoint = start + (end - start) / 2
    return decimal_year_from_datetime(midpoint)

def normalize_date(raw_value: str):
    value = raw_value.strip()
    lower = value.lower()
    if lower in NA_VALUES:
        raise ValueError("missing or NA-like date value")

    if re.fullmatch(r"\d{4}\.\d+", value):
        decimal = float(value)
        if not (1800.0 <= decimal <= 2200.0):
            raise ValueError("decimal year outside expected range 1800-2200")
        return decimal, "decimal_year"

    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        parsed = dt.datetime.strptime(value, "%Y-%m-%d")
        return decimal_year_from_datetime(parsed), "full_date"

    if re.fullmatch(r"\d{4}-\d{2}", value):
        year, month = map(int, value.split("-"))
        if not 1 <= month <= 12:
            raise ValueError("month must be between 01 and 12")
        return midpoint_decimal_year_for_month(year, month), "year_month_midpoint"

    if re.fullmatch(r"\d{4}", value):
        year = int(value)
        return midpoint_decimal_year_for_year(year), "year_midpoint"

    raise ValueError(
        "unsupported date format; expected YYYY-MM-DD, YYYY-MM, YYYY, or decimal year"
    )

def detect_column(headers, preferred_names, column_kind):
    normalized_headers = [normalize_header(header) for header in headers]
    exact_positions = []
    for preferred in preferred_names:
        if preferred in normalized_headers:
            exact_positions.append((preferred, normalized_headers.index(preferred)))

    if exact_positions:
        selected_name, selected_idx = exact_positions[0]
        confidence = "high" if len(exact_positions) == 1 else "medium"
        matches = [headers[idx] for _, idx in exact_positions]
        return {
            "index": selected_idx,
            "header": headers[selected_idx],
            "normalized": normalized_headers[selected_idx],
            "confidence": confidence,
            "match_type": "exact",
            "candidates": matches,
        }

    fuzzy_indexes = []
    if column_kind == "id":
        for idx, normalized in enumerate(normalized_headers):
            if normalized.endswith("_id") or normalized in {"identifier", "sample_identifier"}:
                fuzzy_indexes.append(idx)
    elif column_kind == "date":
        for idx, normalized in enumerate(normalized_headers):
            if (
                normalized.endswith("date")
                or normalized.endswith("_date")
                or normalized.endswith("dato")
                or normalized == "prove_tatt"
            ):
                fuzzy_indexes.append(idx)

    if len(fuzzy_indexes) == 1:
        idx = fuzzy_indexes[0]
        return {
            "index": idx,
            "header": headers[idx],
            "normalized": normalized_headers[idx],
            "confidence": "low",
            "match_type": "fuzzy",
            "candidates": [headers[idx]],
        }

    found = ", ".join(headers)
    expected = ", ".join(preferred_names)
    raise SystemExit(
        f"Could not confidently identify the metadata {column_kind} column.\n"
        f"Found columns: {found}\n"
        f"Expected one of: {expected}\n"
        "Adapt the metadata header names or extend the parser logic."
    )

delimiter = choose_delimiter(metadata_path)
with open(metadata_path, "r", encoding="utf-8-sig", newline="") as handle:
    reader = csv.DictReader(handle, delimiter=delimiter)
    headers = reader.fieldnames or []
    if not headers:
        raise SystemExit("Metadata file is missing a header row.")

    id_info = detect_column(headers, ID_CANDIDATES, "id")
    date_info = detect_column(headers, DATE_CANDIDATES, "date")

    rows = list(reader)
    if not rows:
        raise SystemExit("Metadata file contains a header row but no data rows.")

records = []
seen_ids = set()
duplicate_ids = set()
invalid_rows = []
missing_date_rows = []
excluded_by_flag_rows = []
date_formats_seen = {}

for row_number, row in enumerate(rows, start=2):
    raw_id = (row.get(id_info["header"], "") or "").strip()
    raw_date = (row.get(date_info["header"], "") or "").strip()

    if not raw_id:
        invalid_rows.append((row_number, "missing identifier"))
        continue
    if re.search(r"\s", raw_id):
        invalid_rows.append((row_number, f"identifier '{raw_id}' contains whitespace"))
        continue

    if raw_id in seen_ids:
        duplicate_ids.add(raw_id)
    seen_ids.add(raw_id)

    if exclude_ngs_report_no:
        ngs_report_value = (row.get("NGS_Report", "") or "").strip().upper()
        if ngs_report_value == "NO":
            excluded_by_flag_rows.append((row_number, raw_id, "NGS_Report", row.get("NGS_Report", ""), "excluded by --exclude-ngs-report-no"))
            continue

    if raw_date.strip().lower() in NA_VALUES:
        missing_date_rows.append((row_number, raw_id, raw_date, "missing or NA-like date value"))
        continue

    try:
        normalized_date, date_style = normalize_date(raw_date)
    except ValueError as exc:
        invalid_rows.append((row_number, f"identifier '{raw_id}' has invalid date '{raw_date}': {exc}"))
        continue

    date_formats_seen[date_style] = date_formats_seen.get(date_style, 0) + 1
    records.append((raw_id, raw_date, normalized_date, date_style))

if duplicate_ids:
    dup_list = ", ".join(sorted(duplicate_ids)[:10])
    raise SystemExit(f"Duplicate metadata identifiers detected: {dup_list}")

if invalid_rows:
    examples = "\n".join(f"  line {line_no}: {message}" for line_no, message in invalid_rows[:10])
    raise SystemExit(
        "Metadata validation failed.\n"
        "Examples:\n"
        f"{examples}\n"
        "Fix the metadata identifiers/dates or extend the parser logic."
    )

if not records:
    raise SystemExit(
        "Metadata validation left zero dated samples after removing rows without a usable sampling date."
    )

records.sort(key=lambda item: item[0])
missing_date_rows.sort(key=lambda item: item[1])
excluded_by_flag_rows.sort(key=lambda item: item[1])

Path(dates_out).parent.mkdir(parents=True, exist_ok=True)
Path(audit_out).parent.mkdir(parents=True, exist_ok=True)
Path(summary_out).parent.mkdir(parents=True, exist_ok=True)
Path(skipped_out).parent.mkdir(parents=True, exist_ok=True)

with open(dates_out, "w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle, delimiter="\t")
    writer.writerow(["name", "date"])
    for sample_id, _, normalized_date, _ in records:
        writer.writerow([sample_id, f"{normalized_date:.6f}"])

with open(audit_out, "w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle, delimiter="\t")
    writer.writerow(["name", "original_date", "normalized_decimal_date", "date_interpretation"])
    for sample_id, raw_date, normalized_date, date_style in records:
        writer.writerow([sample_id, raw_date, f"{normalized_date:.6f}", date_style])

with open(skipped_out, "w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle, delimiter="\t")
    writer.writerow(["line_number", "name", "column", "raw_value", "reason"])
    for line_number, sample_id, raw_date, reason in missing_date_rows:
        writer.writerow([line_number, sample_id, date_info["header"], raw_date, reason])
    for line_number, sample_id, column_name, raw_value, reason in excluded_by_flag_rows:
        writer.writerow([line_number, sample_id, column_name, raw_value, reason])

with open(summary_out, "w", encoding="utf-8") as handle:
    handle.write(f"metadata_file\t{metadata_path}\n")
    handle.write(f"metadata_format\t{metadata_format}\n")
    handle.write(f"detected_delimiter\t{repr(delimiter)}\n")
    handle.write(f"selected_id_column\t{id_info['header']}\n")
    handle.write(f"selected_id_match_type\t{id_info['match_type']}\n")
    handle.write(f"selected_id_confidence\t{id_info['confidence']}\n")
    handle.write(f"selected_id_candidates\t{', '.join(id_info['candidates'])}\n")
    handle.write(f"selected_date_column\t{date_info['header']}\n")
    handle.write(f"selected_date_match_type\t{date_info['match_type']}\n")
    handle.write(f"selected_date_confidence\t{date_info['confidence']}\n")
    handle.write(f"selected_date_candidates\t{', '.join(date_info['candidates'])}\n")
    handle.write(f"row_count\t{len(rows)}\n")
    handle.write(f"valid_record_count\t{len(records)}\n")
    handle.write(f"skipped_missing_date_count\t{len(missing_date_rows)}\n")
    handle.write(f"excluded_ngs_report_no_count\t{len(excluded_by_flag_rows)}\n")
    for date_style, count in sorted(date_formats_seen.items()):
        handle.write(f"date_style_{date_style}\t{count}\n")
PY
}

export_retained_visualization_metadata() {
  local metadata=$1
  local metadata_format=$2
  local selected_id_column=$3
  local dates_audit=$4
  local metadata_out=$5
  local summary_out=$6
  local display_columns_spec=$7

  "$PYTHON_BIN" - "$metadata" "$metadata_format" "$selected_id_column" "$dates_audit" "$metadata_out" "$summary_out" "$display_columns_spec" <<'PY'
import csv
import re
import sys
from pathlib import Path

metadata_path, metadata_format, selected_id_column, dates_audit_path, metadata_out, summary_out, display_columns_spec = sys.argv[1:8]

if metadata_format != "default":
    raise SystemExit(
        f"Visualization metadata export currently supports '--metadata-format default' only, not '{metadata_format}'."
    )

AUTO_FIELDS = [
    ("country", "Country", ["country", "country_name", "geo_country"]),
    ("county", "County", ["county", "county_name", "pasient_fylke_name"]),
    ("region", "Region", ["region", "region_name", "pasient_landsdel"]),
    ("age", "Age", ["age", "patient_age", "pasient_alder"]),
    ("age_group", "Age Group", ["age_group", "patient_age_group", "pasient_aldersgruppe"]),
    ("host", "Host", ["host"]),
    ("segment", "Segment", ["segment"]),
    ("lab", "Lab", ["lab", "lab_name", "prove_innsender_navn", "prove_innsender_id"]),
    ("ngs_run", "NGS Run", ["ngs_run", "ngs_run_id", "ngsrun", "ngsrunid", "run_id", "runid"]),
    ("lineage", "Lineage", ["lineage"]),
    ("clade", "Clade", ["clade", "ha_clade", "nc_ha_clade"]),
    ("ha_subclade", "HA Subclade", ["nc_ha_subclade"]),
]

VALUE_REPAIR_MAP = {
    "Tr ndelag": "Trøndelag",
    "M re og Romsdal": "Møre og Romsdal",
    "stfold": "Østfold",
    "stlandet": "Østlandet",
}

def normalize_header(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value

def choose_delimiter(path: str) -> str:
    with open(path, "r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            line = raw_line.strip("\n\r")
            if line.strip():
                counts = {delim: line.count(delim) for delim in ("\t", ";", ",")}
                best = max(counts, key=counts.get)
                if counts[best] > 0:
                    return best
                break
    raise SystemExit("Could not detect metadata delimiter while exporting visualization metadata.")

def title_from_key(key: str) -> str:
    return key.replace("_", " ").title()

def repair_value(value: str) -> str:
    repaired = value.strip()
    return VALUE_REPAIR_MAP.get(repaired, repaired)

delimiter = choose_delimiter(metadata_path)
with open(metadata_path, "r", encoding="utf-8-sig", newline="") as handle:
    reader = csv.DictReader(handle, delimiter=delimiter)
    headers = reader.fieldnames or []
    if not headers:
        raise SystemExit("Metadata file is missing a header row.")
    rows = list(reader)

normalized_to_headers = {}
for header in headers:
    normalized_to_headers.setdefault(normalize_header(header), []).append(header)

selected_display_fields = []

def add_field(output_key: str, title: str, header: str, selection_mode: str):
    if any(existing[0] == output_key for existing in selected_display_fields):
        return
    selected_display_fields.append((output_key, title, header, selection_mode))

spec_lower = display_columns_spec.strip().lower()
if spec_lower == "none":
    pass
elif spec_lower == "auto":
    for output_key, title, candidates in AUTO_FIELDS:
        for candidate in candidates:
            matches = normalized_to_headers.get(candidate, [])
            if matches:
                add_field(output_key, title, matches[0], "auto")
                break
else:
    requested_items = [item.strip() for item in display_columns_spec.split(",") if item.strip()]
    if not requested_items:
        raise SystemExit("--display-columns was provided but no columns were specified.")
    for requested in requested_items:
        if requested in headers:
            add_field(normalize_header(requested), requested, requested, "explicit")
            continue
        normalized_requested = normalize_header(requested)
        matches = normalized_to_headers.get(normalized_requested, [])
        if len(matches) == 1:
            add_field(normalized_requested, matches[0], matches[0], "explicit")
            continue
        if len(matches) > 1:
            raise SystemExit(
                f"Requested display column '{requested}' matches multiple metadata headers: {', '.join(matches)}"
            )
        raise SystemExit(
            f"Requested display column '{requested}' was not found in the metadata header."
        )

with open(dates_audit_path, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    audit_rows = [row for row in reader if row.get("name", "").strip()]

metadata_by_id = {}
duplicate_ids = set()
for row in rows:
    metadata_id = (row.get(selected_id_column, "") or "").strip()
    if not metadata_id:
        continue
    if metadata_id in metadata_by_id:
        duplicate_ids.add(metadata_id)
    metadata_by_id[metadata_id] = row

if duplicate_ids:
    dup_list = ", ".join(sorted(duplicate_ids)[:10])
    raise SystemExit(
        f"Duplicate metadata identifiers encountered while exporting visualization metadata: {dup_list}"
    )

Path(metadata_out).parent.mkdir(parents=True, exist_ok=True)
Path(summary_out).parent.mkdir(parents=True, exist_ok=True)

output_headers = ["name", "metadata_id"] + [field[0] for field in selected_display_fields]
written_rows = []
missing_ids = []

for audit_row in audit_rows:
    final_name = (audit_row.get("name", "") or "").strip()
    metadata_id = (audit_row.get("metadata_id", "") or "").strip() or final_name
    source_row = metadata_by_id.get(metadata_id)
    if source_row is None:
        missing_ids.append(metadata_id)
        continue
    out_row = {"name": final_name, "metadata_id": metadata_id}
    for output_key, _, source_header, _ in selected_display_fields:
        out_row[output_key] = repair_value((source_row.get(source_header, "") or "").strip())
    written_rows.append(out_row)

if missing_ids:
    raise SystemExit(
        "Could not find retained metadata rows for these identifiers: "
        + ", ".join(sorted(set(missing_ids))[:10])
    )

with open(metadata_out, "w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=output_headers, delimiter="\t")
    writer.writeheader()
    for row in written_rows:
        writer.writerow(row)

with open(summary_out, "w", encoding="utf-8") as handle:
    handle.write("output_key\ttitle\tsource_header\tselection_mode\n")
    for output_key, title, source_header, selection_mode in selected_display_fields:
      handle.write(f"{output_key}\t{title}\t{source_header}\t{selection_mode}\n")
PY
}

augment_auspice_json_with_metadata() {
  local auspice_json=$1
  local metadata_tsv=$2
  local field_summary_tsv=$3
  local backup_json=$4
  local report_out=$5

  "$PYTHON_BIN" - "$auspice_json" "$metadata_tsv" "$field_summary_tsv" "$backup_json" "$report_out" <<'PY'
import csv
import json
import math
import shutil
import sys
from pathlib import Path

auspice_json, metadata_tsv, field_summary_tsv, backup_json, report_out = sys.argv[1:6]

with open(metadata_tsv, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    metadata_rows = [row for row in reader if row.get("name", "").strip()]

with open(field_summary_tsv, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    field_rows = [row for row in reader if row.get("output_key", "").strip()]

if not Path(auspice_json).exists():
    raise SystemExit(f"Auspice JSON not found: {auspice_json}")

Path(report_out).parent.mkdir(parents=True, exist_ok=True)

if not field_rows:
    with open(report_out, "w", encoding="utf-8") as handle:
        handle.write("metric\tvalue\n")
        handle.write("augmented_fields\t0\n")
        handle.write("tips_with_metadata\t0\n")
        handle.write("note\tNo visualization metadata fields were selected, so the Auspice JSON was left unchanged.\n")
    raise SystemExit(0)

with open(auspice_json, "r", encoding="utf-8") as handle:
    data = json.load(handle)

field_titles = {row["output_key"]: row["title"] for row in field_rows}
field_order = [row["output_key"] for row in field_rows]

metadata_by_name = {row["name"]: row for row in metadata_rows}
field_types = {}
for field in field_order:
    non_empty_values = [row[field] for row in metadata_rows if row.get(field, "").strip()]
    numeric = True
    for value in non_empty_values:
        try:
            float(value)
        except ValueError:
            numeric = False
            break
    field_types[field] = "continuous" if non_empty_values and numeric else "categorical"

tips_seen = 0
tips_augmented = 0

def walk(node):
    global tips_seen, tips_augmented
    children = node.get("children", [])
    if children:
        for child in children:
            walk(child)
        return

    tips_seen += 1
    name = node.get("name")
    metadata = metadata_by_name.get(name)
    if metadata is None:
        return

    node_attrs = node.setdefault("node_attrs", {})
    added_any = False
    for field in field_order:
        raw_value = (metadata.get(field, "") or "").strip()
        if raw_value == "":
            continue
        value = float(raw_value) if field_types[field] == "continuous" else raw_value
        node_attrs[field] = {"value": value}
        added_any = True
    if added_any:
        tips_augmented += 1

walk(data["tree"])

meta = data.setdefault("meta", {})
colorings = meta.setdefault("colorings", [])
existing_coloring_keys = {item.get("key") for item in colorings}
for field in field_order:
    if field not in existing_coloring_keys:
        colorings.append(
            {
                "title": field_titles[field],
                "type": field_types[field],
                "key": field,
            }
        )

filters = meta.setdefault("filters", [])
existing_filters = set(filters)
for field in field_order:
    if field_types[field] == "categorical" and field not in existing_filters:
        filters.append(field)

shutil.copyfile(auspice_json, backup_json)
with open(auspice_json, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")

with open(report_out, "w", encoding="utf-8") as handle:
    handle.write("metric\tvalue\n")
    handle.write(f"augmented_fields\t{len(field_order)}\n")
    handle.write(f"tips_seen\t{tips_seen}\n")
    handle.write(f"tips_with_metadata\t{tips_augmented}\n")
    handle.write("field_keys\t" + ", ".join(field_order) + "\n")
PY
}

reconcile_fasta_and_metadata_ids() {
  local fasta_names=$1
  local raw_dates_file=$2
  local raw_audit_file=$3
  local skipped_metadata_file=$4
  local dates_out=$5
  local audit_out=$6
  local report_out=$7

  "$PYTHON_BIN" - "$fasta_names" "$raw_dates_file" "$raw_audit_file" "$skipped_metadata_file" "$dates_out" "$audit_out" "$report_out" <<'PY'
import csv
import sys
from pathlib import Path

fasta_names_path, raw_dates_path, raw_audit_path, skipped_metadata_path, dates_out, audit_out, report_out = sys.argv[1:8]

with open(fasta_names_path, "r", encoding="utf-8") as handle:
    fasta_names = [line.strip() for line in handle if line.strip()]

with open(raw_dates_path, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    raw_dates = [row for row in reader if row.get("name", "").strip()]

with open(raw_audit_path, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    raw_audit = [row for row in reader if row.get("name", "").strip()]

with open(skipped_metadata_path, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    skipped_metadata_rows = [row for row in reader if row.get("name", "").strip()]

metadata_names = [row["name"].strip() for row in raw_dates]
skipped_metadata_names = [row["name"].strip() for row in skipped_metadata_rows]
fasta_set = set(fasta_names)
metadata_set = set(metadata_names)
skipped_metadata_set = set(skipped_metadata_names)

def write_outputs(date_rows, audit_rows, strategy, missing_in_metadata, missing_in_fasta, skipped_sequences):
    Path(dates_out).parent.mkdir(parents=True, exist_ok=True)
    Path(audit_out).parent.mkdir(parents=True, exist_ok=True)
    Path(report_out).parent.mkdir(parents=True, exist_ok=True)

    with open(dates_out, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["name", "date"])
        for row in date_rows:
            writer.writerow([row["name"], row["date"]])

    fieldnames = []
    if audit_rows:
        fieldnames = list(audit_rows[0].keys())
    else:
        fieldnames = ["name", "original_date", "normalized_decimal_date", "date_interpretation", "id_mapping_strategy"]

    with open(audit_out, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for row in audit_rows:
            writer.writerow(row)

    with open(report_out, "w", encoding="utf-8") as handle:
        handle.write(f"fasta_sequence_count\t{len(fasta_names)}\n")
        handle.write(f"metadata_name_count\t{len(metadata_names)}\n")
        handle.write(f"skipped_metadata_name_count\t{len(skipped_metadata_names)}\n")
        handle.write(f"id_mapping_strategy\t{strategy}\n")
        handle.write(f"missing_in_metadata_count\t{len(missing_in_metadata)}\n")
        handle.write(f"missing_in_fasta_count\t{len(missing_in_fasta)}\n")
        handle.write(f"excluded_metadata_rows_count\t{len(skipped_metadata_names)}\n")
        handle.write(f"excluded_sequence_count\t{len(skipped_sequences)}\n")
        if missing_in_metadata:
            handle.write("missing_in_metadata_examples\t" + ", ".join(missing_in_metadata[:10]) + "\n")
        if missing_in_fasta:
            handle.write("missing_in_fasta_examples\t" + ", ".join(missing_in_fasta[:10]) + "\n")
        if skipped_sequences:
            handle.write("excluded_sequence_examples\t" + ", ".join(skipped_sequences[:10]) + "\n")

allowed_metadata_set = metadata_set | skipped_metadata_set
missing_in_metadata = sorted(fasta_set - allowed_metadata_set)
missing_in_fasta = sorted(metadata_set - fasta_set)

if not missing_in_metadata and not missing_in_fasta:
    exact_audit = []
    for row in raw_audit:
        updated = dict(row)
        updated["id_mapping_strategy"] = "exact"
        exact_audit.append(updated)
    skipped_sequences = sorted(fasta_set & skipped_metadata_set)
    write_outputs(raw_dates, exact_audit, "exact", missing_in_metadata, missing_in_fasta, skipped_sequences)
    raise SystemExit(0)

suffix_to_fasta = {}
ambiguous_suffixes = set()
for fasta_name in fasta_names:
    if "|" not in fasta_name:
        continue
    suffix = fasta_name.rsplit("|", 1)[1]
    if suffix in suffix_to_fasta:
        ambiguous_suffixes.add(suffix)
    suffix_to_fasta[suffix] = fasta_name

suffix_set = set(suffix_to_fasta.keys())
missing_suffixes_in_metadata = sorted(suffix_set - allowed_metadata_set)
missing_suffixes_in_fasta = sorted(metadata_set - suffix_set)

if not ambiguous_suffixes and not missing_suffixes_in_metadata and not missing_suffixes_in_fasta and len(suffix_to_fasta) == len(fasta_names):
    date_by_metadata_id = {row["name"]: row["date"] for row in raw_dates}
    audit_by_metadata_id = {row["name"]: row for row in raw_audit}
    reconciled_dates = []
    reconciled_audit = []
    skipped_sequences = []
    for fasta_name in fasta_names:
        metadata_id = fasta_name.rsplit("|", 1)[1]
        if metadata_id in skipped_metadata_set:
            skipped_sequences.append(fasta_name)
            continue
        reconciled_dates.append({"name": fasta_name, "date": date_by_metadata_id[metadata_id]})
        source_audit = dict(audit_by_metadata_id[metadata_id])
        source_audit["metadata_id"] = source_audit["name"]
        source_audit["name"] = fasta_name
        source_audit["id_mapping_strategy"] = "pipe_suffix_to_metadata_id"
        reconciled_audit.append(source_audit)
    write_outputs(reconciled_dates, reconciled_audit, "pipe_suffix_to_metadata_id", [], [], sorted(skipped_sequences))
    raise SystemExit(0)

parts = ["FASTA headers and metadata identifiers do not match exactly."]
if missing_in_metadata:
    parts.append(
        "Present in FASTA but missing from metadata: " + ", ".join(missing_in_metadata[:10])
    )
if missing_in_fasta:
    parts.append(
        "Present in metadata but missing from FASTA: " + ", ".join(missing_in_fasta[:10])
    )
parts.append(
    "Fix the identifiers so the FASTA headers match the selected metadata identifier column exactly, "
    "or use a consistent 'prefix|metadata_id' FASTA naming pattern that can be reconciled automatically."
)
raise SystemExit("\n".join(parts))
PY
}

filter_fasta_by_dates() {
  local input_fasta=$1
  local dates_file=$2
  local filtered_fasta=$3
  local filter_report=$4

  "$PYTHON_BIN" - "$input_fasta" "$dates_file" "$filtered_fasta" "$filter_report" <<'PY'
import csv
import sys
from pathlib import Path

input_fasta, dates_file, filtered_fasta, filter_report = sys.argv[1:5]

with open(dates_file, "r", encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    keep_names = [row["name"].strip() for row in reader if row.get("name", "").strip()]

keep_set = set(keep_names)
written_names = []
dropped_names = []
current_header = None
current_lines = []

Path(filtered_fasta).parent.mkdir(parents=True, exist_ok=True)
Path(filter_report).parent.mkdir(parents=True, exist_ok=True)

def flush_record(out_handle):
    global current_header, current_lines
    if current_header is None:
        return
    if current_header in keep_set:
        out_handle.write(f">{current_header}\n")
        out_handle.write("".join(current_lines))
        written_names.append(current_header)
    else:
        dropped_names.append(current_header)

with open(input_fasta, "r", encoding="utf-8") as in_handle, open(filtered_fasta, "w", encoding="utf-8") as out_handle:
    for raw_line in in_handle:
        if raw_line.startswith(">"):
            flush_record(out_handle)
            current_header = raw_line[1:].strip()
            current_lines = []
        else:
            current_lines.append(raw_line)
    flush_record(out_handle)

missing_after_filter = sorted(keep_set - set(written_names))
if missing_after_filter:
    raise SystemExit(
        "Could not find the following date-qualified sequence names in the FASTA after reconciliation: "
        + ", ".join(missing_after_filter[:10])
    )

with open(filter_report, "w", encoding="utf-8") as handle:
    handle.write("metric\tvalue\n")
    handle.write(f"input_sequence_count\t{len(written_names) + len(dropped_names)}\n")
    handle.write(f"retained_sequence_count\t{len(written_names)}\n")
    handle.write(f"dropped_sequence_count\t{len(dropped_names)}\n")
    if dropped_names:
        handle.write("dropped_sequence_examples\t" + ", ".join(dropped_names[:10]) + "\n")
PY
}

filter_dates_to_fasta() {
  local dates_file=$1
  local aligned_fasta=$2
  local filtered_dates=$3

  "$PYTHON_BIN" - "$dates_file" "$aligned_fasta" "$filtered_dates" <<'PY'
import csv
import sys
from pathlib import Path

dates_file, aligned_fasta, filtered_dates = sys.argv[1:]
aligned_ids = {
    line[1:].strip()
    for line in Path(aligned_fasta).read_text(encoding="utf-8-sig").splitlines()
    if line.startswith(">")
}
if not aligned_ids:
    raise SystemExit(f"No sequence identifiers found in accepted alignment: {aligned_fasta}")

with open(dates_file, "r", encoding="utf-8-sig", newline="") as source:
    reader = csv.DictReader(source, delimiter="\t")
    if reader.fieldnames != ["name", "date"]:
        raise SystemExit(f"Unexpected TreeTime dates header in {dates_file}: {reader.fieldnames}")
    rows = list(reader)
by_name = {row.get("name", "").strip(): row for row in rows}
missing = sorted(aligned_ids - set(by_name))
if missing:
    raise SystemExit(
        "Accepted alignment contains identifiers missing from TreeTime dates: "
        + ", ".join(missing[:10])
    )

Path(filtered_dates).parent.mkdir(parents=True, exist_ok=True)
with open(filtered_dates, "w", encoding="utf-8", newline="") as output:
    writer = csv.DictWriter(output, fieldnames=["name", "date"], delimiter="\t")
    writer.writeheader()
    for row in rows:
        if row.get("name", "").strip() in aligned_ids:
            writer.writerow({"name": row.get("name", ""), "date": row.get("date", "")})
PY
}

fasta_appears_aligned() {
  local summary_file=$1
  awk -F '\t' '$1=="appears_aligned"{print $2}' "$summary_file"
}

run_qc_placeholder() {
  local aligned_fasta=$1
  local qc_note=$2
  local qc_masking_placeholder=$3

  cat >"$qc_note" <<EOF
This workflow currently performs validation-oriented QC only.

Implemented in version 1:
- FASTA readability and header validation
- duplicate identifier checks
- filtering of sequences without usable sampling dates
- MAFFT alignment before phylogeny inference
- metadata identifier/date parsing and normalization
- exact FASTA-to-metadata name matching

Not yet implemented, but reserved here for extension:
- low-quality sequence filtering
- terminal trimming
- virus-specific masking of problematic sites
- trait-aware annotation or downstream ancestral analyses

Alignment used for this run:
$aligned_fasta
EOF

  cat >"$qc_masking_placeholder" <<'EOF'
# Placeholder for future masking rules
# Add virus-specific problematic sites here in a later version if needed.
EOF
}

run_nextclade_qc_note() {
  local aligned_fasta=$1
  local qc_note=$2
  local qc_masking_placeholder=$3
  local nextclade_dir=$4
  local nextclade_qc_dir=$5

  cat >"$qc_note" <<EOF
Nextclade alignment and QC were used for this run.

Nextclade outputs:
$nextclade_dir

Nextclade QC filter outputs:
$nextclade_qc_dir

Accepted aligned FASTA used downstream:
$aligned_fasta

The accepted alignment is passed to IQ-TREE and TreeTime. The full Nextclade
results, provenance metadata, and QC filter report are retained in the paths
above.
EOF

  cat >"$qc_masking_placeholder" <<'EOF'
No additional site-masking rules were applied after Nextclade QC.
EOF
}

run_mafft_alignment() {
  local input_fasta=$1
  local aligned_fasta=$2

  command_exists mafft || die "Alignment is required but MAFFT is not available in PATH."
  log "Running MAFFT alignment."
  mafft --auto "$input_fasta" >"$aligned_fasta"
}

run_nextclade_alignment() {
  local input_fasta=$1
  local aligned_fasta=$2
  local nextclade_dir="$QC_DIR/nextclade"
  local nextclade_qc_dir="$QC_DIR/nextclade_qc"
  local runner="$SCRIPT_DIR/run_nextclade.py"
  local filter="$SCRIPT_DIR/filter_nextclade_qc.py"
  local -a command=(
    "$PYTHON_BIN" "$runner"
    --fasta "$input_fasta"
    --outdir "$nextclade_dir"
  )

  [[ -f "$runner" ]] || die "Nextclade runner was not found: $runner"
  [[ -f "$filter" ]] || die "Nextclade QC filter was not found: $filter"

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
    command+=(--include-failed)
  fi

  log "Running Nextclade alignment and reporting."
  "${command[@]}"

  local -a filter_command=(
    "$PYTHON_BIN" "$filter"
    --aligned-fasta "$nextclade_dir/aligned_nucleotide.fasta"
    --qc "$nextclade_dir/qc.tsv"
    --outdir "$nextclade_qc_dir"
  )
  if [[ "$INCLUDE_NEXTCLADE_FAILED" -eq 0 ]]; then
    filter_command+=(--filter-qc)
    log "Filtering Nextclade sequences with non-good QC status."
  else
    log "Keeping sequences with non-good Nextclade QC status by request."
  fi
  "${filter_command[@]}"

  local accepted_fasta="$nextclade_qc_dir/accepted_aligned.fasta"
  [[ -s "$accepted_fasta" ]] || die "Nextclade QC filter produced no accepted alignment: $accepted_fasta"
  local accepted_count
  accepted_count=$(awk '/^>/{count++} END{print count+0}' "$accepted_fasta")
  [[ "$accepted_count" -ge 2 ]] || die "Fewer than 2 sequences remain after Nextclade QC filtering."
  cp "$accepted_fasta" "$aligned_fasta"
  log "Nextclade accepted $accepted_count sequence(s) for downstream phylogeny."
  log "Nextclade outputs: $nextclade_dir"
  log "Nextclade QC outputs: $nextclade_qc_dir"
}

prepare_nextclade_inputs() {
  local report_out=$1
  local helper="$SCRIPT_DIR/resolve_nextclade_inputs.py"
  local output
  local -a command=(
    "$PYTHON_BIN" "$helper"
    --fasta "$FASTA"
    --metadata "$METADATA"
    --metadata-format "$METADATA_FORMAT"
    --report "$report_out"
  )

  [[ -f "$helper" ]] || die "Nextclade validation helper was not found: $helper"

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

  NEXTCLADE_INPUT_MODE=""
  NEXTCLADE_RESOLVED_TYPE=""
  NEXTCLADE_RESOLVED_SEGMENT=""
  NEXTCLADE_RESOLVED_SUBTYPE=""
  NEXTCLADE_DATASET_LABEL=""
  NEXTCLADE_RESOLVED_DATASET_TYPE=""
  NEXTCLADE_RESOLVED_DATASET_SEGMENT=""
  NEXTCLADE_RESOLVED_DATASET_SUBTYPE=""
  NEXTCLADE_MATCHED_RECORD_COUNT=""

  if ! output=$("${command[@]}"); then
    warn "Automatic Nextclade target summary was not resolved. Continuing without it because dataset validation is being handled manually."
    return 0
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      nextclade_input_mode) NEXTCLADE_INPUT_MODE=$value ;;
      analysis_influenza_type) NEXTCLADE_RESOLVED_TYPE=$value ;;
      analysis_segment) NEXTCLADE_RESOLVED_SEGMENT=$value ;;
      analysis_subtype_hint) NEXTCLADE_RESOLVED_SUBTYPE=$value ;;
      dataset_label) NEXTCLADE_DATASET_LABEL=$value ;;
      dataset_influenza_type) NEXTCLADE_RESOLVED_DATASET_TYPE=$value ;;
      dataset_segment) NEXTCLADE_RESOLVED_DATASET_SEGMENT=$value ;;
      dataset_subtype_hint) NEXTCLADE_RESOLVED_DATASET_SUBTYPE=$value ;;
      matched_record_count) NEXTCLADE_MATCHED_RECORD_COUNT=$value ;;
    esac
  done <<<"$output"
}

run_selected_alignment() {
  local input_fasta=$1
  local aligned_fasta=$2

  case "$ALIGNMENT_METHOD" in
    mafft)
      run_mafft_alignment "$input_fasta" "$aligned_fasta"
      ;;
    nextclade)
      run_nextclade_alignment "$input_fasta" "$aligned_fasta"
      ;;
    *)
      die "Internal error: unsupported alignment method '$ALIGNMENT_METHOD'."
      ;;
  esac
}

infer_alignment_length() {
  local aligned_fasta=$1

  "$PYTHON_BIN" - "$aligned_fasta" <<'PY'
import sys

fasta_path = sys.argv[1]
lengths = []
current = []

with open(fasta_path, "r", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(">"):
            if current:
                lengths.append(len("".join(current)))
                current = []
        else:
            current.append(line)
    if current:
        lengths.append(len("".join(current)))

if not lengths:
    raise SystemExit("Could not infer sequence length from the alignment.")

if len(set(lengths)) != 1:
    raise SystemExit(
        "Alignment length inference failed because the sequences are not all the same length."
    )

print(lengths[0])
PY
}

run_iqtree() {
  local aligned_fasta=$1
  local iqtree_prefix=$2

  log "Running IQ-TREE with ModelFinder, SH-aLRT, and ultrafast bootstrap."
  "$IQTREE_BIN" \
    -s "$aligned_fasta" \
    -m MFP \
    -alrt 1000 \
    -B 1000 \
    -nt AUTO \
    -pre "$iqtree_prefix" \
    -redo
}

write_iqtree_run_note() {
  local note_file=$1

  cat >"$note_file" <<EOF
IQ-TREE executable: $IQTREE_BIN
Threads requested: AUTO
Primary command:
$IQTREE_BIN -s $ALIGNED_FASTA -m MFP -alrt 1000 -B 1000 -nt AUTO -pre $IQTREE_PREFIX -redo

Future extension points intentionally left simple in version 1:
- user-supplied partition files
- partitioned analyses
- codon models
EOF
}

run_treetime_clock() {
  local tree_file=$1
  local dates_file=$2
  local seq_len=$3
  local outdir=$4
  local log_file=$5

  command_exists treetime || die "TreeTime is not available in PATH."
  log "Running TreeTime clock analysis."
  treetime clock \
    --tree "$tree_file" \
    --dates "$dates_file" \
    --sequence-length "$seq_len" \
    "${TREETIME_ROOT_ARGS[@]}" \
    --outdir "$outdir" \
    2>&1 | tee "$log_file"
}

choose_treetime_input_tree() {
  local clock_dir=$1
  local fallback_tree=$2

  local candidates=(
    "$clock_dir/rerooted.newick"
    "$clock_dir/rerooted_tree.nwk"
    "$clock_dir/rerooted_tree.newick"
    "$clock_dir/timetree_rerooted.newick"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  warn "Could not find a rerooted tree from TreeTime clock output. Falling back to the IQ-TREE tree."
  echo "$fallback_tree"
}

summarize_clock_outputs() {
  local clock_dir=$1
  local clock_log=$2
  local summary_out=$3
  local warnings_out=$4

  "$PYTHON_BIN" - "$clock_dir" "$clock_log" "$summary_out" "$warnings_out" <<'PY'
import os
import re
import sys
from pathlib import Path

clock_dir, clock_log, summary_out, warnings_out = sys.argv[1:5]

rate = None
r2 = None
rerooted_tree = None
warning_messages = []

candidate_tree_names = [
    "rerooted.newick",
    "rerooted_tree.nwk",
    "rerooted_tree.newick",
    "timetree_rerooted.newick",
]
for name in candidate_tree_names:
    path = os.path.join(clock_dir, name)
    if os.path.exists(path):
        rerooted_tree = path
        break

text_blobs = []
for path in [clock_log] + [
    os.path.join(clock_dir, entry)
    for entry in os.listdir(clock_dir)
    if entry.endswith((".log", ".txt", ".tsv", ".csv"))
]:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            text_blobs.append(handle.read())
    except OSError:
        continue

combined = "\n".join(text_blobs)

rate_patterns = [
    r"(?:substitution rate|clock rate)[^0-9eE+\-]*([+\-]?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)",
    r"\brate\b[^0-9eE+\-]*([+\-]?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)",
]
r2_patterns = [
    r"R\^?2[^0-9+\-]*([+\-]?\d+(?:\.\d+)?)",
    r"root-to-tip[^0-9+\-]*([+\-]?\d+(?:\.\d+)?)",
]

for pattern in rate_patterns:
    match = re.search(pattern, combined, flags=re.IGNORECASE)
    if match:
        try:
            rate = float(match.group(1))
            break
        except ValueError:
            pass

for pattern in r2_patterns:
    match = re.search(pattern, combined, flags=re.IGNORECASE)
    if match:
        try:
            r2 = float(match.group(1))
            break
        except ValueError:
            pass

if rate is not None and rate < 0:
    warning_messages.append(
        f"Estimated substitution rate is negative ({rate}). Check temporal signal, rooting, and metadata dates."
    )
if r2 is not None and r2 < 0.1:
    warning_messages.append(
        f"Root-to-tip R^2 is low ({r2}). Temporal signal may be weak."
    )
if rate is None:
    warning_messages.append(
        "Could not automatically parse the estimated substitution rate from TreeTime clock outputs."
    )
if r2 is None:
    warning_messages.append(
        "Could not automatically parse the root-to-tip R^2 from TreeTime clock outputs."
    )
if rerooted_tree is None:
    warning_messages.append(
        "Could not locate a rerooted tree in the TreeTime clock output directory."
    )

Path(summary_out).parent.mkdir(parents=True, exist_ok=True)
Path(warnings_out).parent.mkdir(parents=True, exist_ok=True)

with open(summary_out, "w", encoding="utf-8") as handle:
    handle.write("metric\tvalue\n")
    handle.write(f"estimated_substitution_rate\t{rate if rate is not None else 'NA'}\n")
    handle.write(f"root_to_tip_r2\t{r2 if r2 is not None else 'NA'}\n")
    handle.write(f"rerooted_tree\t{rerooted_tree if rerooted_tree is not None else 'NA'}\n")
    handle.write(f"clock_log\t{clock_log}\n")

with open(warnings_out, "w", encoding="utf-8") as handle:
    if warning_messages:
        for message in warning_messages:
            handle.write(message + "\n")
    else:
        handle.write("No obvious clock-analysis warnings were detected by the simple heuristics.\n")
PY
}

run_treetime_timetree() {
  local tree_file=$1
  local aligned_fasta=$2
  local dates_file=$3
  local outdir=$4
  local log_file=$5

  log "Running TreeTime timetree inference."
  treetime \
    --tree "$tree_file" \
    --aln "$aligned_fasta" \
    --dates "$dates_file" \
    "${TREETIME_ROOT_ARGS[@]}" \
    --outdir "$outdir" \
    2>&1 | tee "$log_file"
}

write_downstream_placeholder() {
  local downstream_note=$1

  cat >"$downstream_note" <<'EOF'
Future downstream hooks reserved here:
- ancestral sequence reconstruction
- homoplasy / recurrent mutation analysis
- metadata-driven trait annotation and visualization
EOF
}

export_itol_bundle() {
  local tree_file=$1
  local metadata_tsv=$2
  local field_summary_tsv=$3
  local outdir=$4

  local exporter
  exporter="$(dirname "${BASH_SOURCE[0]}")/export_itol_annotations.py"
  if [[ ! -f "$exporter" ]]; then
    warn "iTOL exporter was not found, so no circular tree annotation bundle was written: $exporter"
    return 0
  fi
  if [[ ! -s "$metadata_tsv" ]]; then
    warn "Visualization metadata is missing, so no iTOL metadata rings were written: $metadata_tsv"
    return 0
  fi

  log "Writing iTOL circular-tree annotation bundle."
  "$PYTHON_BIN" "$exporter"     --tree "$tree_file"     --metadata "$metadata_tsv"     --fields "$field_summary_tsv"     --outdir "$outdir"
}

export_microreact_bundle() {
  local tree_file=$1
  local metadata_tsv=$2
  local dates_audit_tsv=$3
  local outdir=$4

  local exporter
  exporter="$(dirname "${BASH_SOURCE[0]}")/export_microreact.py"
  if [[ ! -f "$exporter" ]]; then
    warn "Microreact exporter was not found, so no Microreact bundle was written: $exporter"
    return 0
  fi
  if [[ ! -s "$metadata_tsv" ]]; then
    warn "Visualization metadata is missing, so no Microreact metadata CSV was written: $metadata_tsv"
    return 0
  fi

  log "Writing Microreact upload bundle."
  "$PYTHON_BIN" "$exporter"     --tree "$tree_file"     --metadata "$metadata_tsv"     --dates "$dates_audit_tsv"     --outdir "$outdir"
}

add_aa_mutations_to_auspice() {
  local auspice_json=$1
  local ancestral_sequences=$2
  local gene=$3
  local frame=$4
  local report=$5

  local mutator
  mutator="$(dirname "${BASH_SOURCE[0]}")/add_aa_mutations_to_auspice.py"
  if [[ ! -f "$mutator" ]]; then
    warn "Auspice amino-acid mutation helper was not found: $mutator"
    return 0
  fi
  if [[ ! -s "$auspice_json" || ! -s "$ancestral_sequences" ]]; then
    warn "Auspice JSON or ancestral sequences are missing, so amino-acid branch mutations were not added."
    return 0
  fi

  log "Adding $gene amino-acid branch mutations to Auspice JSON."
  "$PYTHON_BIN" "$mutator"     --auspice "$auspice_json"     --ancestral-sequences "$ancestral_sequences"     --gene "$gene"     --frame "$frame"     --report "$report"
}

FASTA="data/sequences.fasta"
METADATA="data/metadata.tsv"
METADATA_FORMAT="default"
OUTDIR="results"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SEQ_LEN=""
CLOCK_ROOT=""
OUTGROUP=""
DISPLAY_COLUMNS="auto"
ALIGNMENT_METHOD="mafft"
NEXTCLADE_DATASET=""
NEXTCLADE_DATASET_TAG=""
NEXTCLADE_REFERENCE=""
NEXTCLADE_ANNOTATION=""
NEXTCLADE_PATHOGEN_JSON=""
INCLUDE_NEXTCLADE_FAILED=0
ANALYSIS_INFLUENZA_TYPE=""
ANALYSIS_SEGMENT=""
AA_GENE="HA"
AA_FRAME=0
EXCLUDE_NGS_REPORT_NO=0
FORCE_ALIGN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fasta)
      [[ $# -ge 2 ]] || die "Missing value for --fasta"
      FASTA=$2
      shift 2
      ;;
    --metadata)
      [[ $# -ge 2 ]] || die "Missing value for --metadata"
      METADATA=$2
      shift 2
      ;;
    --metadata-format)
      [[ $# -ge 2 ]] || die "Missing value for --metadata-format"
      METADATA_FORMAT=$2
      shift 2
      ;;
    --outdir)
      [[ $# -ge 2 ]] || die "Missing value for --outdir"
      OUTDIR=$2
      shift 2
      ;;
    --seq-len)
      [[ $# -ge 2 ]] || die "Missing value for --seq-len"
      SEQ_LEN=$2
      shift 2
      ;;
    --clock-root)
      [[ $# -ge 2 ]] || die "Missing value for --clock-root"
      CLOCK_ROOT=$2
      shift 2
      ;;
    --outgroup)
      [[ $# -ge 2 ]] || die "Missing value for --outgroup"
      OUTGROUP=$2
      shift 2
      ;;
    --display-columns)
      [[ $# -ge 2 ]] || die "Missing value for --display-columns"
      DISPLAY_COLUMNS=$2
      shift 2
      ;;
    --alignment-method)
      [[ $# -ge 2 ]] || die "Missing value for --alignment-method"
      ALIGNMENT_METHOD=$2
      shift 2
      ;;
    --nextclade-dataset)
      [[ $# -ge 2 ]] || die "Missing value for --nextclade-dataset"
      NEXTCLADE_DATASET=$2
      shift 2
      ;;
    --nextclade-dataset-tag)
      [[ $# -ge 2 ]] || die "Missing value for --nextclade-dataset-tag"
      NEXTCLADE_DATASET_TAG=$2
      shift 2
      ;;
    --nextclade-reference)
      [[ $# -ge 2 ]] || die "Missing value for --nextclade-reference"
      NEXTCLADE_REFERENCE=$2
      shift 2
      ;;
    --nextclade-annotation)
      [[ $# -ge 2 ]] || die "Missing value for --nextclade-annotation"
      NEXTCLADE_ANNOTATION=$2
      shift 2
      ;;
    --nextclade-pathogen-json)
      [[ $# -ge 2 ]] || die "Missing value for --nextclade-pathogen-json"
      NEXTCLADE_PATHOGEN_JSON=$2
      shift 2
      ;;
    --influenza-type)
      [[ $# -ge 2 ]] || die "Missing value for --influenza-type"
      ANALYSIS_INFLUENZA_TYPE=$2
      shift 2
      ;;
    --segment)
      [[ $# -ge 2 ]] || die "Missing value for --segment"
      ANALYSIS_SEGMENT=$2
      shift 2
      ;;
    --include-nextclade-failed)
      INCLUDE_NEXTCLADE_FAILED=1
      shift
      ;;
    --aa-gene)
      [[ $# -ge 2 ]] || die "Missing value for --aa-gene"
      AA_GENE=$2
      shift 2
      ;;
    --aa-frame)
      [[ $# -ge 2 ]] || die "Missing value for --aa-frame"
      AA_FRAME=$2
      shift 2
      ;;
    --exclude-ngs-report-no)
      EXCLUDE_NGS_REPORT_NO=1
      shift
      ;;
    --force-align)
      FORCE_ALIGN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$OUTDIR" ]] || die "--outdir must not be empty"
[[ "$METADATA_FORMAT" =~ ^[A-Za-z0-9._-]+$ ]] || die "Unsupported --metadata-format value: $METADATA_FORMAT"
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
    ;;
  *)
    die "--alignment-method must be 'mafft' or 'nextclade', not '$ALIGNMENT_METHOD'."
    ;;
esac
if [[ -n "$SEQ_LEN" ]] && ! [[ "$SEQ_LEN" =~ ^[0-9]+$ ]]; then
  die "--seq-len must be an integer."
fi
if ! [[ "$AA_FRAME" =~ ^[0-2]$ ]]; then
  die "--aa-frame must be 0, 1, or 2."
fi
[[ -n "$AA_GENE" ]] || die "--aa-gene must not be empty."

require_readable_file "$FASTA" "FASTA file"
require_readable_file "$METADATA" "Metadata file"

build_treetime_root_args

PYTHON_BIN=$(detect_python)
IQTREE_BIN=$(detect_iqtree)
CPU_COUNT=$(detect_cpu_count)

IQTREE_DIR="$OUTDIR/iqtree"
DERIVED_DIR="$OUTDIR/derived_metadata"
CLOCK_DIR="$OUTDIR/clock"
TIMETREE_DIR="$OUTDIR/timetree"
QC_DIR="$OUTDIR/qc"
ITOL_DIR="$OUTDIR/itol"
MICROREACT_DIR="$OUTDIR/microreact"

mkdir -p "$OUTDIR" "$IQTREE_DIR" "$DERIVED_DIR" "$CLOCK_DIR" "$TIMETREE_DIR" "$QC_DIR" "$ITOL_DIR" "$MICROREACT_DIR"

FASTA_NAMES="$QC_DIR/fasta_names.txt"
FASTA_SUMMARY="$QC_DIR/fasta_summary.tsv"
ALIGNMENT_PATH="$QC_DIR/aligned_sequences.fasta"
PARSER_SUMMARY="$DERIVED_DIR/parser_summary.tsv"
RAW_DATES_FILE="$DERIVED_DIR/dates_for_treetime.raw.tsv"
RAW_DATES_AUDIT="$DERIVED_DIR/dates_with_audit.raw.tsv"
DATES_FILE="$DERIVED_DIR/dates_for_treetime.tsv"
DATES_AUDIT="$DERIVED_DIR/dates_with_audit.tsv"
SKIPPED_SAMPLES_REPORT="$DERIVED_DIR/skipped_samples_missing_dates.tsv"
VISUALIZATION_METADATA_TSV="$DERIVED_DIR/retained_visualization_metadata.tsv"
VISUALIZATION_FIELDS_SUMMARY="$DERIVED_DIR/visualization_fields.tsv"
ID_MATCH_REPORT="$QC_DIR/id_match_report.tsv"
FASTA_FILTERED_TO_DATED="$QC_DIR/sequences_with_dates.fasta"
FASTA_FILTER_REPORT="$QC_DIR/sequence_filter_report.tsv"
QC_NOTE="$QC_DIR/qc_notes.txt"
MASKING_PLACEHOLDER="$QC_DIR/masking_rules.placeholder.txt"
DOWNSTREAM_PLACEHOLDER="$OUTDIR/downstream_hooks.txt"
IQTREE_PREFIX="$IQTREE_DIR/viral_phylogeny"
IQTREE_NOTE="$IQTREE_DIR/run_notes.txt"
CLOCK_LOG="$CLOCK_DIR/clock.stdout.log"
CLOCK_SUMMARY="$CLOCK_DIR/clock_summary.tsv"
CLOCK_WARNINGS="$CLOCK_DIR/clock_warnings.txt"
TIMETREE_LOG="$TIMETREE_DIR/timetree.stdout.log"
AUSPICE_JSON="$TIMETREE_DIR/auspice_tree.json"
AUSPICE_JSON_RAW="$TIMETREE_DIR/auspice_tree.treetime_raw.json"
AUSPICE_AUGMENT_REPORT="$TIMETREE_DIR/auspice_metadata_report.tsv"
ANCESTRAL_SEQUENCES="$TIMETREE_DIR/ancestral_sequences.fasta"
AA_MUTATION_REPORT="$TIMETREE_DIR/amino_acid_branch_mutations.tsv"
NEXTCLADE_INPUT_REPORT="$QC_DIR/nextclade_input_validation.tsv"

log "Starting viral phylogeny workflow."
log "FASTA: $FASTA"
log "Metadata: $METADATA"
log "Metadata format: $METADATA_FORMAT"
log "Output directory: $OUTDIR"
log "TreeTime rooting mode: $TREETIME_ROOT_DESC"
log "Visualization metadata columns: $DISPLAY_COLUMNS"
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
    log "Requested influenza type override: $ANALYSIS_INFLUENZA_TYPE"
  fi
  if [[ -n "$ANALYSIS_SEGMENT" ]]; then
    log "Requested segment override: $ANALYSIS_SEGMENT"
  fi
  log "Include Nextclade-failed sequences: $INCLUDE_NEXTCLADE_FAILED"
fi
log "Auspice amino-acid mutation gene/frame: $AA_GENE / $AA_FRAME"
log "Exclude NGS_Report=NO: $EXCLUDE_NGS_REPORT_NO"
log "Detected IQ-TREE executable: $IQTREE_BIN"
log "Detected Python executable: $PYTHON_BIN"
log "Detected CPU count: $CPU_COUNT"

if [[ "$ALIGNMENT_METHOD" == "nextclade" ]]; then
  log "Attempting a non-blocking Nextclade target summary from the matched metadata rows."
  prepare_nextclade_inputs "$NEXTCLADE_INPUT_REPORT"
  if [[ -n "$NEXTCLADE_INPUT_MODE" ]]; then
    log "Nextclade input mode: $NEXTCLADE_INPUT_MODE"
  fi
  if [[ -n "$NEXTCLADE_RESOLVED_TYPE" || -n "$NEXTCLADE_RESOLVED_SEGMENT" ]]; then
    log "Resolved influenza target hint: type=${NEXTCLADE_RESOLVED_TYPE:-unknown} segment=${NEXTCLADE_RESOLVED_SEGMENT:-unknown}"
  fi
  if [[ -n "$NEXTCLADE_RESOLVED_SUBTYPE" ]]; then
    log "Resolved subtype hint: $NEXTCLADE_RESOLVED_SUBTYPE"
  fi
  if [[ -n "$NEXTCLADE_DATASET_LABEL" ]]; then
    log "Resolved Nextclade source hint: $NEXTCLADE_DATASET_LABEL"
  fi
  if [[ -n "$NEXTCLADE_RESOLVED_DATASET_TYPE" || -n "$NEXTCLADE_RESOLVED_DATASET_SEGMENT" ]]; then
    log "Resolved Nextclade source target hint: type=${NEXTCLADE_RESOLVED_DATASET_TYPE:-unknown} segment=${NEXTCLADE_RESOLVED_DATASET_SEGMENT:-unknown}"
  fi
  if [[ -n "$NEXTCLADE_MATCHED_RECORD_COUNT" ]]; then
    log "Matched metadata rows used for the summary: $NEXTCLADE_MATCHED_RECORD_COUNT"
  fi
  if [[ -s "$NEXTCLADE_INPUT_REPORT" ]]; then
    log "Nextclade input summary report: $NEXTCLADE_INPUT_REPORT"
  fi
fi

log "Validating FASTA and collecting sequence statistics."
validate_fasta_and_collect_stats "$FASTA" "$FASTA_NAMES" "$FASTA_SUMMARY"

log "Deriving TreeTime-ready dates from metadata."
derive_dates_from_metadata "$METADATA" "$METADATA_FORMAT" "$RAW_DATES_FILE" "$RAW_DATES_AUDIT" "$PARSER_SUMMARY" "$SKIPPED_SAMPLES_REPORT" "$([[ "$EXCLUDE_NGS_REPORT_NO" -eq 1 ]] && echo true || echo false)"

selected_id_column=$(awk -F '\t' '$1=="selected_id_column"{print $2}' "$PARSER_SUMMARY")
selected_date_column=$(awk -F '\t' '$1=="selected_date_column"{print $2}' "$PARSER_SUMMARY")
skipped_missing_date_count=$(awk -F '\t' '$1=="skipped_missing_date_count"{print $2}' "$PARSER_SUMMARY")
excluded_ngs_report_no_count=$(awk -F '\t' '$1=="excluded_ngs_report_no_count"{print $2}' "$PARSER_SUMMARY")
log "Selected metadata identifier column: $selected_id_column"
log "Selected metadata date column: $selected_date_column"
if [[ "${skipped_missing_date_count:-0}" -gt 0 ]]; then
  warn "Skipping $skipped_missing_date_count sample(s) without a usable date from metadata column '$selected_date_column'."
  skipped_examples=$(awk -F '\t' 'NR>1 {print $2; count++; if (count==5) exit}' "$SKIPPED_SAMPLES_REPORT" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
  [[ -n "${skipped_examples:-}" ]] && warn "Examples of skipped metadata identifiers: $skipped_examples"
  warn "Detailed skipped-sample report: $SKIPPED_SAMPLES_REPORT"
fi
if [[ "${excluded_ngs_report_no_count:-0}" -gt 0 ]]; then
  warn "Excluded $excluded_ngs_report_no_count sample(s) because NGS_Report was NO."
fi

log "Checking that FASTA headers match derived metadata identifiers."
reconcile_fasta_and_metadata_ids "$FASTA_NAMES" "$RAW_DATES_FILE" "$RAW_DATES_AUDIT" "$SKIPPED_SAMPLES_REPORT" "$DATES_FILE" "$DATES_AUDIT" "$ID_MATCH_REPORT"

log "Exporting retained metadata for visualization outputs."
export_retained_visualization_metadata "$METADATA" "$METADATA_FORMAT" "$selected_id_column" "$DATES_AUDIT" "$VISUALIZATION_METADATA_TSV" "$VISUALIZATION_FIELDS_SUMMARY" "$DISPLAY_COLUMNS"

excluded_sequences_count=$(awk -F '\t' '$1=="excluded_sequence_count"{print $2}' "$ID_MATCH_REPORT")
if [[ "${excluded_sequences_count:-0}" -gt 0 ]]; then
  warn "Excluding $excluded_sequences_count sequence(s) from phylogeny because they were removed during metadata filtering."
fi

log "Filtering FASTA down to sequences with usable dates."
filter_fasta_by_dates "$FASTA" "$DATES_FILE" "$FASTA_FILTERED_TO_DATED" "$FASTA_FILTER_REPORT"

retained_sequences=$(awk -F '\t' '$1=="retained_sequence_count"{print $2}' "$FASTA_FILTER_REPORT")
if [[ -z "${retained_sequences:-}" || "${retained_sequences:-0}" -lt 2 ]]; then
  die "Fewer than 2 sequences remain after excluding samples without usable dates."
fi

appears_aligned=$(fasta_appears_aligned "$FASTA_SUMMARY")
if [[ "$FORCE_ALIGN" -eq 1 ]]; then
  warn "--force-align is now redundant because the workflow always runs MAFFT."
fi
if [[ "$appears_aligned" == "true" ]]; then
  log "Input FASTA appears aligned, but MAFFT will still be run to ensure a consistent aligned output."
else
  log "Input FASTA does not appear aligned. MAFFT will be run."
fi
run_selected_alignment "$FASTA_FILTERED_TO_DATED" "$ALIGNMENT_PATH"

if [[ "$ALIGNMENT_METHOD" == "nextclade" ]]; then
  NEXTCLADE_DATES_FILE="$DERIVED_DIR/dates_for_treetime.nextclade.tsv"
  filter_dates_to_fasta "$DATES_FILE" "$ALIGNMENT_PATH" "$NEXTCLADE_DATES_FILE"
  DATES_FILE="$NEXTCLADE_DATES_FILE"
  run_nextclade_qc_note \
    "$ALIGNMENT_PATH" \
    "$QC_NOTE" \
    "$MASKING_PLACEHOLDER" \
    "$QC_DIR/nextclade" \
    "$QC_DIR/nextclade_qc"
else
  run_qc_placeholder "$ALIGNMENT_PATH" "$QC_NOTE" "$MASKING_PLACEHOLDER"
fi
write_downstream_placeholder "$DOWNSTREAM_PLACEHOLDER"

if [[ -z "$SEQ_LEN" ]]; then
  log "No --seq-len was supplied. Inferring sequence length from the aligned FASTA."
  SEQ_LEN=$(infer_alignment_length "$ALIGNMENT_PATH")
fi
log "Sequence length for TreeTime clock analysis: $SEQ_LEN"

ALIGNED_FASTA="$ALIGNMENT_PATH"
log "Aligned FASTA for downstream steps: $ALIGNED_FASTA"

run_iqtree "$ALIGNED_FASTA" "$IQTREE_PREFIX"
write_iqtree_run_note "$IQTREE_NOTE"

IQTREE_TREE="${IQTREE_PREFIX}.treefile"
[[ -f "$IQTREE_TREE" ]] || die "IQ-TREE finished but the expected tree file was not found: $IQTREE_TREE"

run_treetime_clock "$IQTREE_TREE" "$DATES_FILE" "$SEQ_LEN" "$CLOCK_DIR" "$CLOCK_LOG"
summarize_clock_outputs "$CLOCK_DIR" "$CLOCK_LOG" "$CLOCK_SUMMARY" "$CLOCK_WARNINGS"

if grep -qiE 'negative|low \(|weak temporal signal|could not automatically parse' "$CLOCK_WARNINGS"; then
  warn "Clock-analysis warnings were recorded in $CLOCK_WARNINGS"
fi

TREETIME_TREE=$(choose_treetime_input_tree "$CLOCK_DIR" "$IQTREE_TREE")
run_treetime_timetree "$TREETIME_TREE" "$ALIGNED_FASTA" "$DATES_FILE" "$TIMETREE_DIR" "$TIMETREE_LOG"

if [[ -f "$AUSPICE_JSON" ]]; then
  log "Augmenting Auspice JSON with retained metadata."
  augment_auspice_json_with_metadata "$AUSPICE_JSON" "$VISUALIZATION_METADATA_TSV" "$VISUALIZATION_FIELDS_SUMMARY" "$AUSPICE_JSON_RAW" "$AUSPICE_AUGMENT_REPORT"
else
  warn "TreeTime did not produce an Auspice JSON, so no metadata augmentation was performed."
fi

if [[ -f "$AUSPICE_JSON" ]]; then
  add_aa_mutations_to_auspice "$AUSPICE_JSON" "$ANCESTRAL_SEQUENCES" "$AA_GENE" "$AA_FRAME" "$AA_MUTATION_REPORT"
fi

export_itol_bundle "$IQTREE_TREE" "$VISUALIZATION_METADATA_TSV" "$VISUALIZATION_FIELDS_SUMMARY" "$ITOL_DIR"
export_microreact_bundle "$IQTREE_TREE" "$VISUALIZATION_METADATA_TSV" "$DATES_AUDIT" "$MICROREACT_DIR"

log "Workflow completed successfully."
log "Key outputs:"
log "  IQ-TREE results: $IQTREE_DIR"
log "  Derived metadata: $DERIVED_DIR"
log "  Clock analysis: $CLOCK_DIR"
log "  Timetree analysis: $TIMETREE_DIR"
log "  iTOL circular tree bundle: $ITOL_DIR"
log "  Microreact upload bundle: $MICROREACT_DIR"
if [[ -f "$AUSPICE_JSON" ]]; then
  log "  Enriched Auspice JSON: $AUSPICE_JSON"
fi
log "  QC notes: $QC_DIR"
