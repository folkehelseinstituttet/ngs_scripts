#!/usr/bin/env python3
"""Export Microreact-ready tree and metadata files from run_phylo outputs."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import re
import shutil
from pathlib import Path

PALETTE = [
    "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b",
    "#e377c2", "#7f7f7f", "#bcbd22", "#17becf", "#4e79a7", "#f28e2b",
    "#59a14f", "#e15759", "#76b7b2", "#edc948", "#b07aa1", "#ff9da7",
    "#9c755f", "#bab0ac",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create Microreact upload files from a Newick tree and metadata TSV.")
    parser.add_argument("--tree", type=Path, required=True, help="IQ-TREE .treefile or another Newick tree.")
    parser.add_argument("--metadata", type=Path, required=True, help="retained_visualization_metadata.tsv from run_phylo.sh.")
    parser.add_argument("--dates", type=Path, help="dates_with_audit.tsv from run_phylo.sh for date/year/month/day columns.")
    parser.add_argument("--outdir", type=Path, required=True, help="Directory for Microreact files.")
    parser.add_argument(
        "--colour-columns",
        default="ngs_run,clade,ha_subclade,county,region,lab",
        help="Comma-separated categorical metadata columns for which FIELD__colour columns are added.",
    )
    return parser.parse_args()


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return [row for row in reader if any((value or "").strip() for value in row.values())]


def parse_date(value: str) -> tuple[str, str, str, str]:
    value = (value or "").strip()
    if not value:
        return "", "", "", ""
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        parsed = dt.datetime.strptime(value, "%Y-%m-%d")
        return value, str(parsed.year), str(parsed.month), str(parsed.day)
    if re.fullmatch(r"\d{4}-\d{2}", value):
        year, month = value.split("-")
        return value, year, str(int(month)), ""
    if re.fullmatch(r"\d{4}", value):
        return value, value, "", ""
    return value, "", "", ""


def color_map(values: list[str]) -> dict[str, str]:
    unique = sorted(set(value for value in values if value), key=lambda item: (item.casefold(), item))
    return {value: PALETTE[index % len(PALETTE)] for index, value in enumerate(unique)}


def main() -> None:
    args = parse_args()
    if not args.tree.is_file():
        raise SystemExit(f"Tree file not found: {args.tree}")
    if not args.metadata.is_file():
        raise SystemExit(f"Metadata file not found: {args.metadata}")

    args.outdir.mkdir(parents=True, exist_ok=True)
    tree_out = args.outdir / "microreact_tree.nwk"
    shutil.copyfile(args.tree, tree_out)

    metadata_rows = read_tsv(args.metadata)
    if not metadata_rows:
        raise SystemExit(f"Metadata file contains no rows: {args.metadata}")
    metadata_headers = list(metadata_rows[0].keys())
    if "name" not in metadata_headers:
        raise SystemExit(f"Metadata must contain a 'name' column: {args.metadata}")

    dates_by_name = {}
    if args.dates and args.dates.exists():
        for row in read_tsv(args.dates):
            name = (row.get("name") or "").strip()
            if name:
                dates_by_name[name] = row

    colour_columns = [item.strip() for item in args.colour_columns.split(",") if item.strip()]
    colour_columns = [column for column in colour_columns if column in metadata_headers]
    colours = {
        column: color_map([(row.get(column) or "").strip() for row in metadata_rows])
        for column in colour_columns
    }

    base_headers = ["id", "name"]
    extra_headers = [header for header in metadata_headers if header not in {"name"}]
    date_headers = ["date", "year", "month", "day", "decimal_date"]
    colour_headers = [f"{column}__colour" for column in colour_columns]
    output_headers = base_headers + extra_headers + date_headers + colour_headers

    metadata_out = args.outdir / "microreact_metadata.csv"
    with metadata_out.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=output_headers)
        writer.writeheader()
        for row in metadata_rows:
            name = (row.get("name") or "").strip()
            date_row = dates_by_name.get(name, {})
            original_date = (date_row.get("original_date") or "").strip()
            date_value, year, month, day = parse_date(original_date)
            out_row = {"id": name, "name": name}
            for header in extra_headers:
                out_row[header] = row.get(header, "")
            out_row["date"] = date_value
            out_row["year"] = year
            out_row["month"] = month
            out_row["day"] = day
            out_row["decimal_date"] = (date_row.get("normalized_decimal_date") or "").strip()
            for column in colour_columns:
                value = (row.get(column) or "").strip()
                out_row[f"{column}__colour"] = colours[column].get(value, "")
            writer.writerow(out_row)

    readme = args.outdir / "README.txt"
    with readme.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("Microreact upload bundle\n")
        handle.write("=======================\n\n")
        handle.write("Upload both files at https://microreact.org/upload:\n")
        handle.write("- microreact_tree.nwk\n")
        handle.write("- microreact_metadata.csv\n\n")
        handle.write("When configuring the tree panel, choose metadata column 'id' as the labels column.\n")
        handle.write("Use any metadata field for colour; matching FIELD__colour columns are included for common categorical fields.\n")
        handle.write("Date, year, month, day, and decimal_date columns are included when date audit data is available.\n")

    manifest = args.outdir / "manifest.tsv"
    with manifest.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("type\tpath\n")
        handle.write(f"tree\t{tree_out}\n")
        handle.write(f"metadata\t{metadata_out}\n")
        handle.write(f"instructions\t{readme}\n")

    print(f"Wrote Microreact bundle: {args.outdir}")


if __name__ == "__main__":
    main()
