#!/usr/bin/env python3
"""Apply optional Nextclade QC filtering to a normalized alignment."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aligned-fasta", type=Path, required=True)
    parser.add_argument("--qc", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument(
        "--filter-qc",
        action="store_true",
        help="Exclude sequences whose qc.overallStatus is not 'good'. Default keeps all sequences.",
    )
    return parser.parse_args()


def read_fasta(path: Path):
    records = []
    header = None
    sequence = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines(keepends=True):
        if raw.startswith(">"):
            if header is not None:
                records.append((header, "".join(sequence)))
            header = raw[1:].strip()
            sequence = []
        elif raw.strip():
            sequence.append(raw)
    if header is not None:
        records.append((header, "".join(sequence)))
    if not records:
        raise SystemExit(f"No FASTA records found: {path}")
    ids = [name for name, _ in records]
    if len(ids) != len(set(ids)):
        raise SystemExit(f"Duplicate identifiers in FASTA: {path}")
    return records


def read_qc(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        headers = reader.fieldnames or []
        rows = list(reader)
    if "seqName" not in headers:
        raise SystemExit(f"QC table does not contain seqName: {path}")
    status_column = "qc.overallStatus"
    if status_column not in headers:
        raise SystemExit(f"QC table does not contain {status_column}: {path}")
    by_id = {}
    for row in rows:
        name = (row.get("seqName") or "").strip()
        if not name:
            raise SystemExit(f"QC table contains an empty seqName: {path}")
        if name in by_id:
            raise SystemExit(f"Duplicate seqName in QC table: {name}")
        by_id[name] = row
    return by_id


def main() -> int:
    args = parse_args()
    records = read_fasta(args.aligned_fasta)
    qc_by_id = read_qc(args.qc)
    fasta_ids = {name for name, _ in records}
    qc_ids = set(qc_by_id)
    if fasta_ids != qc_ids:
        missing = sorted(fasta_ids - qc_ids)
        unexpected = sorted(qc_ids - fasta_ids)
        raise SystemExit(f"QC/FASTA identifier mismatch: missing={missing[:5]} unexpected={unexpected[:5]}")

    args.outdir.mkdir(parents=True, exist_ok=True)
    accepted = []
    excluded = []
    report_rows = []
    for name, sequence in records:
        status = (qc_by_id[name].get("qc.overallStatus") or "").strip().lower()
        keep = not args.filter_qc or status == "good"
        reason = "QC filtering disabled" if not args.filter_qc else ("QC status is good" if keep else f"QC status is {status or 'missing'}")
        (accepted if keep else excluded).append((name, sequence))
        report_rows.append({"seqName": name, "qc_overall_status": status, "included": str(keep).lower(), "reason": reason})

    def write_fasta(path: Path, selected):
        with path.open("w", encoding="utf-8") as handle:
            for name, sequence in selected:
                handle.write(f">{name}\n{sequence}")

    write_fasta(args.outdir / "accepted_aligned.fasta", accepted)
    write_fasta(args.outdir / "excluded_aligned.fasta", excluded)
    with (args.outdir / "qc_filter_report.tsv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["seqName", "qc_overall_status", "included", "reason"], delimiter="\t")
        writer.writeheader()
        writer.writerows(report_rows)

    with (args.outdir / "qc_filter_summary.tsv").open("w", encoding="utf-8") as handle:
        handle.write("metric\tvalue\n")
        handle.write(f"filter_enabled\t{str(args.filter_qc).lower()}\n")
        handle.write(f"input_sequence_count\t{len(records)}\n")
        handle.write(f"accepted_sequence_count\t{len(accepted)}\n")
        handle.write(f"excluded_sequence_count\t{len(excluded)}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
