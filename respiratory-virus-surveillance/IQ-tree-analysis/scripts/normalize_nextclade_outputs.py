#!/usr/bin/env python3
"""Validate and normalize outputs produced by ``nextclade run``."""

from __future__ import annotations

import argparse
import csv
import shutil
from pathlib import Path


def args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nextclade-dir", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    return parser.parse_args()


def require(path: Path, label: str) -> Path:
    if not path.is_file() or not path.stat().st_size:
        raise SystemExit(f"Required Nextclade output missing or empty: {label}: {path}")
    return path


def fasta_records(path: Path):
    header = None
    sequence = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if raw.startswith(">"):
            if header is not None:
                yield header, "".join(sequence)
            header = raw[1:].strip()
            sequence = []
        elif raw.strip():
            sequence.append(raw.strip())
    if header is not None:
        yield header, "".join(sequence)


def unique_fasta_ids(path: Path):
    ids = [name for name, _ in fasta_records(path)]
    if not ids:
        raise SystemExit(f"No FASTA records found: {path}")
    if len(ids) != len(set(ids)):
        raise SystemExit(f"Duplicate identifiers in aligned FASTA: {path}")
    return ids


def read_tsv(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows = list(reader)
        headers = reader.fieldnames or []
    if "seqName" not in headers:
        raise SystemExit(f"Nextclade TSV does not contain seqName: {path}")
    ids = [(row.get("seqName") or "").strip() for row in rows]
    if any(not value for value in ids):
        raise SystemExit(f"Nextclade TSV contains an empty seqName: {path}")
    if len(ids) != len(set(ids)):
        raise SystemExit(f"Duplicate seqName values in Nextclade TSV: {path}")
    return headers, rows, ids


def write_selected(path: Path, headers, rows, fields):
    selected = [field for field in fields if field in headers]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["seqName", *selected], delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in writer.fieldnames})


def main() -> int:
    options = args()
    source = options.nextclade_dir
    outdir = options.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    aligned = require(source / "nextclade.aligned.fasta", "aligned FASTA")
    results = require(source / "nextclade.tsv", "results TSV")
    aligned_ids = unique_fasta_ids(aligned)
    headers, rows, result_ids = read_tsv(results)
    if set(aligned_ids) != set(result_ids):
        missing = sorted(set(aligned_ids) - set(result_ids))
        unexpected = sorted(set(result_ids) - set(aligned_ids))
        raise SystemExit(f"Nextclade identifier mismatch: missing={missing[:5]} unexpected={unexpected[:5]}")

    shutil.copyfile(aligned, outdir / "aligned_nucleotide.fasta")
    translation_files = sorted(source.glob("nextclade.cds_translation.*.fasta"))
    if not translation_files:
        raise SystemExit("No Nextclade translated amino-acid FASTA files found.")
    with (outdir / "translated_amino_acid.fasta").open("w", encoding="utf-8") as output:
        for translation in translation_files:
            output.write(translation.read_text(encoding="utf-8"))

    write_selected(outdir / "qc.tsv", headers, rows, [field for field in headers if field.startswith("qc.") or field in {"warnings", "errors", "failedCdses"}])
    write_selected(outdir / "nucleotide_mutations.tsv", headers, rows, ["substitutions", "deletions", "insertions", "privateNucMutations.labeledSubstitutions", "privateNucMutations.unlabeledSubstitutions"])
    write_selected(outdir / "amino_acid_mutations.tsv", headers, rows, ["aaSubstitutions", "aaDeletions", "aaInsertions", "privateAaMutations.labeledSubstitutions", "privateAaMutations.unlabeledSubstitutions"])
    write_selected(outdir / "insertions.tsv", headers, rows, ["insertions", "aaInsertions"])
    write_selected(outdir / "deletions.tsv", headers, rows, ["deletions", "aaDeletions"])
    shutil.copyfile(results, outdir / "nextclade_results.tsv")
    if (source / "nextclade.json").is_file():
        shutil.copyfile(source / "nextclade.json", outdir / "nextclade_results.json")

    with (outdir / "normalization_summary.tsv").open("w", encoding="utf-8") as handle:
        handle.write("metric\tvalue\n")
        handle.write(f"aligned_sequence_count\t{len(aligned_ids)}\n")
        handle.write(f"result_row_count\t{len(result_ids)}\n")
        handle.write(f"translation_file_count\t{len(translation_files)}\n")
        handle.write("identifier_sets_match\ttrue\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
