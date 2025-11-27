#!/usr/bin/env python3
"""
dedup_rename_fasta.py

Remove duplicate sequences from FASTA files based on (ID, segment),
where headers look like:
>A/mallard/Idaho/23-029400-016-origi02-NAl/2023|MP|EPI_ISL_19660853

Rules:
- ID  = part before first '|'
- SEG = second '|' field, renamed using a fixed map
- If more than one record exists for the same (ID, SEG), keep only the first.
- NEW: If ID length > 59 characters, drop that record entirely.
- Process multiple input FASTAs, outputting one deduped/renamed FASTA per input.

Usage:
  python dedup_rename_fasta.py 01.fasta 02.fasta 03.fasta
"""

import argparse
import os
import sys


SEGMENT_MAP = {
    "HA": "01-HA",
    "NA": "02-NA",
    "M":  "03-M",
    "MP": "03-M",
    "PB1": "04-PB1",
    "PB2": "05-PB2",
    "NP": "06-NP",
    "PA": "07-PA",
    "NS": "08-NS",
}


def normalize_segment(seg_raw: str) -> str:
    seg = seg_raw.strip().upper()
    if seg in SEGMENT_MAP:
        return SEGMENT_MAP[seg]
    # Unknown segment: leave as-is but warn
    if seg:
        print(f"[warn] Unknown segment '{seg_raw}' -> leaving unchanged", file=sys.stderr)
        return seg_raw.strip()
    return seg_raw.strip()


def derive_outpath(in_path: str) -> str:
    base, ext = os.path.splitext(in_path)
    if ext.lower() in (".fa", ".fasta", ".fna", ".faa", ".fas"):
        return f"{base}_dedup{ext}"
    return f"{in_path}_dedup.fasta"


def process_fasta(in_path: str) -> str:
    out_path = derive_outpath(in_path)
    seen = set()

    def flush_record(header, seq_lines, out_fh):
        if header is None:
            return 0, 0, 0  # kept, skipped_dup, skipped_longid

        seq = "".join(seq_lines).replace("\n", "").strip()
        if not seq:
            return 0, 0, 0

        # Parse header
        h = header[1:].strip()  # drop ">"
        parts = h.split("|")
        id_part = parts[0].strip() if len(parts) >= 1 else h
        seg_raw = parts[1].strip() if len(parts) >= 2 else ""
        rest = parts[2:] if len(parts) > 2 else []

        # NEW: drop if ID too long
        if len(id_part) > 59:
            # optional warning:
            # print(f"[warn] Dropping long ID ({len(id_part)} chars): {id_part}", file=sys.stderr)
            return 0, 0, 1

        seg_std = normalize_segment(seg_raw)

        key = (id_part, seg_std)
        if key in seen:
            return 0, 1, 0  # duplicate skipped
        seen.add(key)

        # Rebuild header with renamed segment
        new_header = f">{id_part}|{seg_std}"
        if rest:
            new_header += "|" + "|".join(rest)

        out_fh.write(new_header + "\n")
        # Wrap sequence to 80 chars per line
        for i in range(0, len(seq), 80):
            out_fh.write(seq[i:i+80] + "\n")

        return 1, 0, 0  # kept

    kept = skipped_dup = skipped_longid = 0
    header = None
    seq_lines = []

    with open(in_path, "r", encoding="utf-8") as in_fh, \
         open(out_path, "w", encoding="utf-8") as out_fh:

        for line in in_fh:
            if line.startswith(">"):
                k, sd, sl = flush_record(header, seq_lines, out_fh)
                kept += k
                skipped_dup += sd
                skipped_longid += sl
                header = line.rstrip("\n")
                seq_lines = []
            else:
                seq_lines.append(line)

        # flush last record
        k, sd, sl = flush_record(header, seq_lines, out_fh)
        kept += k
        skipped_dup += sd
        skipped_longid += sl

    print(
        f"[ok] {in_path} -> {out_path} | kept={kept}, "
        f"skipped_duplicates={skipped_dup}, skipped_long_ids={skipped_longid}",
        file=sys.stderr
    )
    return out_path


def main():
    ap = argparse.ArgumentParser(description="Deduplicate FASTA by (ID, segment), rename segments, drop long IDs.")
    ap.add_argument("fastas", nargs="+", help="Input FASTA files")
    args = ap.parse_args()

    for fp in args.fastas:
        try:
            process_fasta(fp)
        except FileNotFoundError:
            print(f"[error] File not found: {fp}", file=sys.stderr)
        except Exception as e:
            print(f"[error] Failed on {fp}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
