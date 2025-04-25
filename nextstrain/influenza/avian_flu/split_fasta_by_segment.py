#!/usr/bin/env python3
import sys
import re

def extract_segment(header):
    """
    Extracts the segment type from a FASTA header string.
    
    If the header contains one or more '|' characters (as in:
    ">A/chicken/USA/004840-004/2025|HA|EPI_ISL_19756143"), this
    function returns the second field (e.g. "HA").
    """
    parts = header.split("|")
    if len(parts) >= 2:
        return parts[1].strip()
    
    # Fallback to regex if no '|' delimiters are found
    m = re.search(r"segment[:=]\s*([A-Za-z0-9]+)", header, re.IGNORECASE)
    if m:
        return m.group(1)
    
    # Fallback: if headers are in the format >ID_segment, take the part after the last underscore
    parts = header.split('_')
    if len(parts) > 1:
        return parts[-1].strip()
    
    # If no segment can be determined, return a default value
    return "unknown_segment"

def trim_header(header):
    """
    Trims the header by returning only the part before the first pipe.
    """
    return header.split("|")[0].strip()

def split_fasta_by_segment(input_fasta):
    """
    Processes the input FASTA file.
    - Reads each record (header and sequence).
    - Extracts the segment type from the header.
    - Trims the header (removes everything after the first pipe).
    - Writes each record to a segment‐specific output file.
    
    Output files are named following the format:
      sequences_segment.fasta  (segment is in lowercase)
    """
    # Dictionary to hold open output file handles, keyed by lowercase segment type.
    output_files = {}

    try:
        with open(input_fasta, 'r') as infile:
            current_header = None
            current_seq_lines = []

            for line in infile:
                line = line.rstrip()
                if line.startswith(">"):
                    # Process the previous record if exists
                    if current_header:
                        segment = extract_segment(current_header)
                        segment_lower = segment.lower()
                        if segment_lower not in output_files:
                            out_filename = f"sequences_{segment_lower}.fasta"
                            output_files[segment_lower] = open(out_filename, 'w')
                        # Write the trimmed header and the sequence
                        output_files[segment_lower].write(trim_header(current_header) + "\n")
                        output_files[segment_lower].write("\n".join(current_seq_lines) + "\n")
                    
                    # Begin a new record
                    current_header = line
                    current_seq_lines = []
                else:
                    # Collect sequence lines
                    if line:  # ignore empty lines
                        current_seq_lines.append(line)
            
            # Process the last record if present
            if current_header:
                segment = extract_segment(current_header)
                segment_lower = segment.lower()
                if segment_lower not in output_files:
                    out_filename = f"sequences_{segment_lower}.fasta"
                    output_files[segment_lower] = open(out_filename, 'w')
                output_files[segment_lower].write(trim_header(current_header) + "\n")
                output_files[segment_lower].write("\n".join(current_seq_lines) + "\n")
    finally:
        # Close all the open output files
        for f in output_files.values():
            f.close()

def main():
    # Check command-line usage
    if len(sys.argv) != 2:
        print("Usage: python split_fasta_by_segment.py <input_fasta_file>")
        sys.exit(1)
    
    input_fasta = sys.argv[1]
    split_fasta_by_segment(input_fasta)
    print("FASTA file has been split by segment type and headers have been trimmed.")

if __name__ == "__main__":
    main()
