#!/usr/bin/env python3
"""Prepare existing GISAID TSV + HA FASTA without changing source files."""

import argparse
import csv
import re
import shutil
from collections import Counter
from pathlib import Path


def prepare(metadata, fasta, output):
    with metadata.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        columns = reader.fieldnames or []
        required = {"strain", "date", "region", "country", "division", "host", "subtype"}
        missing = required - set(columns)
        if missing:
            raise ValueError("Missing metadata columns: " + ", ".join(sorted(missing)))
        if len(columns) != len(set(columns)):
            raise ValueError("Duplicate metadata column names")
        rows = list(reader)
    if not rows:
        raise ValueError("Metadata has no records")
    for row in rows:
        if None in row or any(value is None for value in row.values()):
            raise ValueError("Metadata row has a different number of fields than the header")
    strains = [row["strain"].strip() for row in rows]
    if any(not strain or any(c.isspace() for c in strain) for strain in strains):
        raise ValueError("Strain identifiers must be nonempty and contain no whitespace")
    if len(strains) != len(set(strains)):
        raise ValueError("Duplicate strain identifiers in metadata")

    fasta_ids = []
    with fasta.open() as handle:
        for line in handle:
            if line.startswith(">"):
                header = line[1:].strip()
                if not header:
                    raise ValueError("Empty FASTA header")
                fasta_ids.append(header.split()[0])
    if not fasta_ids:
        raise ValueError("No sequences in HA FASTA")
    if len(fasta_ids) != len(set(fasta_ids)):
        raise ValueError("Duplicate sequence identifiers in HA FASTA")
    unmatched = set(fasta_ids) - set(strains)
    if unmatched:
        raise ValueError(f"{len(unmatched)} HA FASTA identifiers lack metadata; examples: {sorted(unmatched)[:3]}")

    # Keep every existing field, particularly the already-separated geography.
    # Retain subtype for Auspice and add the field used by the subtype queries.
    for name in ("virus_subtype", "gisaid_clade", "genoflu"):
        if name not in columns:
            columns.append(name)
    # The upstream clade-labeling script expects strain in the first column.
    columns = ["strain"] + [column for column in columns if column != "strain"]
    unknown = {"", "?", "na", "n/a", "unknown", "nan"}
    for row in rows:
        for key in columns:
            value = row.get(key, "").strip()
            row[key] = "unknown" if value.lower() in unknown else value
        subtype = re.sub(r"^A\s*/\s*", "", row["subtype"].upper())
        row["virus_subtype"] = subtype if subtype != "UNKNOWN" else "unknown"
        row["subtype"] = row["virus_subtype"]
        if row["date"].lower() == "unknown" or row["date"].upper().startswith("XXXX"):
            row["date"] = "XXXX-XX-XX"

    ha_ids = set(fasta_ids)
    summaries = []
    for subtype in ("H5N1", "H5N5"):
        matched = [row for row in rows if row["virus_subtype"] == subtype and row["strain"] in ha_ids]
        eligible = sum(bool(re.match(r"\d{4}", row["date"])) and int(row["date"][:4]) >= 2024 for row in matched)
        if not eligible:
            raise ValueError(f"No matched {subtype} HA records dated 2024 or later")
        summaries.append(f"Matched {subtype} HA: {len(matched)}; dated 2024 onward: {eligible} before other build filters")
    output.mkdir(parents=True, exist_ok=True)
    if metadata.resolve() == (output / "metadata.tsv").resolve() or fasta.resolve() == (output / "sequences_ha.fasta").resolve():
        raise ValueError("Output directory must differ from the source input directory")
    with (output / "metadata.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    shutil.copyfile(fasta, output / "sequences_ha.fasta")
    print(f"Metadata: {len(rows)} unique strains; HA FASTA: {len(fasta_ids)} matching identifiers")
    print(f"Subtypes: {dict(Counter(row['virus_subtype'] for row in rows))}")
    for summary in summaries:
        print(summary)
    print("Existing geographic columns preserved; unknown values standardized to 'unknown'.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("fasta", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        prepare(args.metadata, args.fasta, args.output)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Input error: {error}\n")


if __name__ == "__main__":
    main()
