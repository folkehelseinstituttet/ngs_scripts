"""Validate reference header names and EPI identifiers against a seasonal table."""

import csv
from pathlib import Path
import re
import sys


EPI_PATTERN = re.compile(r"EPI_ISL_[0-9]+")
REQUIRED_COLUMNS = {"Subtype", "Reference", "Type", "GISAID_EPI"}


def normalize_reference_name(value):
    return re.sub(r"_+", "_", re.sub(r"[^A-Za-z0-9._-]", "_", value.strip()))


def load_reference_table(path, reference_type):
    rows = {}
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        reader.fieldnames = [name.strip() for name in (reader.fieldnames or [])]
        missing = REQUIRED_COLUMNS - set(reader.fieldnames)
        if missing:
            raise ValueError("Reference table is missing columns: " + ", ".join(sorted(missing)))
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                raise ValueError(f"Malformed reference-table row {line_number}")
            row = {key: value.strip() for key, value in row.items()}
            if row["Type"] != reference_type:
                continue
            if not all(row[column] for column in REQUIRED_COLUMNS):
                raise ValueError(f"Missing value in reference-table row {line_number}")
            subtype = row["Subtype"]
            if not re.fullmatch(r"[A-Za-z0-9._-]+", subtype) or subtype in {".", ".."}:
                raise ValueError(f"Invalid subtype in reference-table row {line_number}: {subtype!r}")
            if not EPI_PATTERN.fullmatch(row["GISAID_EPI"]):
                raise ValueError(f"Invalid GISAID_EPI for {reference_type}/{subtype}: {row['GISAID_EPI']!r}")
            if "|" in row["Reference"]:
                raise ValueError(f"Reference name contains a reserved pipe character: {row['Reference']!r}")
            if subtype in rows:
                raise ValueError(f"Duplicate reference-table entry for {reference_type}/{subtype}")
            rows[subtype] = row
    if not rows:
        raise ValueError(f"No reference-table entries for Type={reference_type}")
    return rows


def parse_reference_header(header, fasta_path, allow_legacy=False):
    name_and_epi, separator, segment = header.strip().rpartition("_")
    if not separator or not segment:
        raise ValueError(f"Missing terminal segment suffix in {fasta_path}: {header!r}")
    if "|" in name_and_epi:
        fields = name_and_epi.split("|")
        if len(fields) != 2 or not EPI_PATTERN.fullmatch(fields[1]):
            raise ValueError(f"Invalid EPI header in {fasta_path}: {header!r}")
        name, epi = fields
    elif allow_legacy:
        name, epi = name_and_epi, None
    else:
        raise ValueError(f"Missing EPI identifier in {fasta_path}; expected STRAIN|EPI_ISL_<digits>_<segment>")

    protein = Path(fasta_path).stem.upper()
    aliases = {
        "HA1": {"HA1", "HA"},
        "HA2": {"HA2", "HA"},
        "NS1": {"NS1", "NS"},
        "NS2": {"NS2", "NS"},
        "M1": {"M1", "M", "MP"},
        "M2": {"M2", "M", "MP"},
        "SIGPEP": {"SIGPEP", "SIG"},
    }
    if segment.upper() not in aliases.get(protein, {protein}):
        raise ValueError(f"Wrong segment suffix in {fasta_path}: {segment!r}")
    if not name.strip():
        raise ValueError(f"Empty reference name in {fasta_path}")
    return name.strip(), epi, segment


def check_reference_header(header, fasta_path, expected, allow_legacy=False):
    name, epi, segment = parse_reference_header(header, fasta_path, allow_legacy=allow_legacy)
    if normalize_reference_name(name) != normalize_reference_name(expected["Reference"]):
        raise ValueError(
            f"Wrong reference in {fasta_path}: expected {expected['Reference']!r}, found {name!r}"
        )
    if epi is not None and epi != expected["GISAID_EPI"]:
        raise ValueError(
            f"Wrong EPI in {fasta_path}: expected {expected['GISAID_EPI']}, found {epi}"
        )
    return segment


def validate_reference_type(reference_root, reference_type, table_path):
    root = Path(reference_root)
    if not root.is_dir():
        raise ValueError(f"Reference directory not found: {root}")
    expected_rows = load_reference_table(table_path, reference_type)
    total_files = 0
    for subtype, expected in expected_rows.items():
        subtype_dir = root / subtype
        if not subtype_dir.is_dir():
            raise ValueError(f"Missing subtype directory: {subtype_dir}")
        fasta_files = sorted(subtype_dir.glob("*.fasta"))
        if not fasta_files:
            raise ValueError(f"No FASTA files found in {subtype_dir}")
        records = 0
        for fasta in fasta_files:
            header = None
            has_sequence = False
            with fasta.open(encoding="utf-8-sig") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith(">"):
                        if header is not None and not has_sequence:
                            raise ValueError(f"Empty FASTA record in {fasta}: {header!r}")
                        header = line[1:]
                        check_reference_header(header, fasta, expected)
                        has_sequence = False
                        records += 1
                    else:
                        if header is None:
                            raise ValueError(f"Sequence appears before a FASTA header in {fasta}")
                        has_sequence = True
            if header is None or not has_sequence:
                raise ValueError(f"Missing header or empty FASTA record in {fasta}")
        total_files += len(fasta_files)
        print(
            f"OK: {reference_type}/{subtype} -> {expected['Reference']} | "
            f"{expected['GISAID_EPI']} ({len(fasta_files)} FASTA files, {records} records)"
        )
    print(f"Validated {total_files} {reference_type} FASTA files against {table_path}")
    print("Validation checks reference headers, not sequence identity or segment completeness.")


def main():
    if len(sys.argv) != 4:
        print("Usage: validator REFERENCE_TYPE_DIRECTORY TYPE REFERENCE_TABLE", file=sys.stderr)
        return 2
    try:
        validate_reference_type(*sys.argv[1:])
    except (OSError, ValueError, csv.Error, UnicodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
