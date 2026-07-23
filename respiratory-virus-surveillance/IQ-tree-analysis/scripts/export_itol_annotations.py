#!/usr/bin/env python3
"""Export iTOL color-strip annotation files from run_phylo outputs."""

from __future__ import annotations

import argparse
import csv
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
    parser = argparse.ArgumentParser(
        description="Create iTOL tree and metadata color-strip files from a Newick tree and retained metadata TSV."
    )
    parser.add_argument("--tree", type=Path, required=True, help="IQ-TREE .treefile or another Newick tree.")
    parser.add_argument("--metadata", type=Path, required=True, help="retained_visualization_metadata.tsv from run_phylo.sh.")
    parser.add_argument("--fields", type=Path, help="visualization_fields.tsv from run_phylo.sh, used for display titles.")
    parser.add_argument("--outdir", type=Path, required=True, help="Directory for iTOL files.")
    parser.add_argument(
        "--columns",
        help="Comma-separated metadata columns to export. Defaults to every retained column except name/metadata_id.",
    )
    return parser.parse_args()


def sanitize_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    return cleaned.strip("_") or "metadata"


def read_metadata(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        headers = reader.fieldnames or []
        rows = [row for row in reader if (row.get("name") or "").strip()]
    if "name" not in headers:
        raise SystemExit(f"Metadata file must contain a 'name' column: {path}")
    if not rows:
        raise SystemExit(f"Metadata file contains no rows: {path}")
    return headers, rows


def read_titles(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return {
            (row.get("output_key") or "").strip(): (row.get("title") or row.get("output_key") or "").strip()
            for row in reader
            if (row.get("output_key") or "").strip()
        }


def choose_columns(headers: list[str], rows: list[dict[str, str]], requested: str | None) -> list[str]:
    if requested:
        columns = [item.strip() for item in requested.split(",") if item.strip()]
        missing = [column for column in columns if column not in headers]
        if missing:
            raise SystemExit("Requested metadata column(s) not found: " + ", ".join(missing))
    else:
        columns = [column for column in headers if column not in {"name", "metadata_id"}]

    return [column for column in columns if any((row.get(column) or "").strip() for row in rows)]


def color_for_values(values: list[str]) -> dict[str, str]:
    unique = sorted(set(values), key=lambda value: (value.casefold(), value))
    return {value: PALETTE[index % len(PALETTE)] for index, value in enumerate(unique)}


def write_colorstrip(column: str, title: str, rows: list[dict[str, str]], outdir: Path) -> Path:
    values = [(row["name"].strip(), (row.get(column) or "").strip()) for row in rows]
    values = [(name, value) for name, value in values if value]
    colors = color_for_values([value for _, value in values])

    out_path = outdir / f"itol_colorstrip_{sanitize_filename(column)}.txt"
    with out_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("DATASET_COLORSTRIP\n")
        handle.write("SEPARATOR TAB\n")
        handle.write(f"DATASET_LABEL\t{title}\n")
        handle.write("COLOR\t#666666\n")
        handle.write(f"LEGEND_TITLE\t{title}\n")
        handle.write("LEGEND_SHAPES\t" + "\t".join(["1"] * len(colors)) + "\n")
        handle.write("LEGEND_COLORS\t" + "\t".join(colors[value] for value in colors) + "\n")
        handle.write("LEGEND_LABELS\t" + "\t".join(colors.keys()) + "\n")
        handle.write("DATA\n")
        for name, value in values:
            handle.write(f"{name}\t{colors[value]}\t{value}\n")
    return out_path


def main() -> None:
    args = parse_args()
    if not args.tree.is_file():
        raise SystemExit(f"Tree file not found: {args.tree}")
    if not args.metadata.is_file():
        raise SystemExit(f"Metadata file not found: {args.metadata}")

    args.outdir.mkdir(parents=True, exist_ok=True)
    tree_out = args.outdir / "iqtree_with_branch_supports.tree"
    shutil.copyfile(args.tree, tree_out)

    headers, rows = read_metadata(args.metadata)
    titles = read_titles(args.fields)
    columns = choose_columns(headers, rows, args.columns)

    written = []
    for column in columns:
        title = titles.get(column, column.replace("_", " ").title())
        written.append(write_colorstrip(column, title, rows, args.outdir))

    readme = args.outdir / "README.txt"
    with readme.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("iTOL upload bundle\n")
        handle.write("==================\n\n")
        handle.write("1. Upload iqtree_with_branch_supports.tree to https://itol.embl.de/\n")
        handle.write("2. In iTOL, set Display mode to Circular.\n")
        handle.write("3. Enable internal node labels / bootstrap labels to show IQ-TREE branch support values.\n")
        handle.write("4. Drag the itol_colorstrip_*.txt files onto the tree to add metadata rings.\n\n")
        handle.write("Tree file:\n")
        handle.write(f"- {tree_out.name}\n\n")
        handle.write("Metadata ring files:\n")
        for path in written:
            handle.write(f"- {path.name}\n")

    manifest = args.outdir / "manifest.tsv"
    with manifest.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("type\tpath\n")
        handle.write(f"tree\t{tree_out}\n")
        for path in written:
            handle.write(f"metadata_ring\t{path}\n")
        handle.write(f"instructions\t{readme}\n")

    print(f"Wrote iTOL bundle: {args.outdir}")


if __name__ == "__main__":
    main()
