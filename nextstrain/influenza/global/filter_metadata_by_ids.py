#!/usr/bin/env python3
import argparse
import csv

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--metadata", required=True)
    ap.add_argument("--ids", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--id-col", default="strain")
    args = ap.parse_args()

    ids = set()
    with open(args.ids, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s:
                ids.add(s)

    with open(args.metadata, "r", encoding="utf-8", newline="") as fin:
        reader = csv.DictReader(fin, delimiter="\t")
        if reader.fieldnames is None:
            raise SystemExit("[ERROR] metadata file has no header")

        if args.id_col not in reader.fieldnames:
            raise SystemExit(f"[ERROR] id-col '{args.id_col}' not in metadata header: {reader.fieldnames}")

        with open(args.output, "w", encoding="utf-8", newline="") as fout:
            writer = csv.DictWriter(fout, fieldnames=reader.fieldnames, delimiter="\t")
            writer.writeheader()
            for row in reader:
                key = (row.get(args.id_col) or "").strip()
                if key in ids:
                    writer.writerow(row)

if __name__ == "__main__":
    main()
