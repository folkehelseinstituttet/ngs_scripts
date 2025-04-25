#!/usr/bin/env python3
import sys
import os
import re

def extract_segment(header):
    """
    Extracts the segment type from a FASTA header string.
    If the header contains '|' delimiters, returns the second field (e.g. "HA").
    Fallbacks to regex or underscore-splitting if needed.
    """
    parts = header.split("|")
    if len(parts) >= 2:
        return parts[1].strip()
    m = re.search(r"segment[:=]\s*([A-Za-z0-9]+)", header, re.IGNORECASE)
    if m:
        return m.group(1)
    parts = header.split('_')
    if len(parts) > 1:
        return parts[-1].strip()
    return "unknown_segment"

def trim_header(header):
    """
    Trims the header by returning only the part before the first pipe.
    """
    return header.split("|")[0].strip()

def split_fasta_by_segment(input_fasta, output_dir=None):
    """
    Splits the input FASTA by segment types and writes to files.
    If output_dir is given, writes files there; otherwise, in cwd.
    Output filenames: sequences_<segment>.fasta
    """
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    output_files = {}

    with open(input_fasta, 'r') as infile:
        current_header = None
        current_seq_lines = []

        for line in infile:
            line = line.rstrip()
            if line.startswith(">"):
                if current_header:
                    segment = extract_segment(current_header)
                    seg_key = segment.lower()
                    if seg_key not in output_files:
                        out_name = f"sequences_{seg_key}.fasta"
                        out_path = os.path.join(output_dir or '.', out_name)
                        output_files[seg_key] = open(out_path, 'w')
                    output_files[seg_key].write(trim_header(current_header) + "\n")
                    output_files[seg_key].write("\n".join(current_seq_lines) + "\n")
                current_header = line
                current_seq_lines = []
            else:
                if line:
                    current_seq_lines.append(line)

        # Handle last record
        if current_header:
            segment = extract_segment(current_header)
            seg_key = segment.lower()
            if seg_key not in output_files:
                out_name = f"sequences_{seg_key}.fasta"
                out_path = os.path.join(output_dir or '.', out_name)
                output_files[seg_key] = open(out_path, 'w')
            output_files[seg_key].write(trim_header(current_header) + "\n")
            output_files[seg_key].write("\n".join(current_seq_lines) + "\n")

    for fh in output_files.values():
        fh.close()


def main():
    args = sys.argv[1:]
    if len(args) < 1 or len(args) > 2:
        print("Usage: python split_fasta_by_segment.py <input_fasta_file> [output_dir]")
        sys.exit(1)

    input_fasta = args[0]
    output_dir = args[1] if len(args) == 2 else None
    split_fasta_by_segment(input_fasta, output_dir)
    print("FASTA file has been split by segment type and headers have been trimmed.")

if __name__ == "__main__":
    main()
