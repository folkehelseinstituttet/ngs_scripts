#!/bin/bash
# Check for an input XLS file
if [ $# -lt 1 ]; then
    echo "Usage: $0 input.xls"
    exit 1
fi

input_xls="$1"
temp_csv="temp.csv"
output_csv="output.csv"
output_tsv="output.tsv"

# Step 1: Convert XLS to CSV using ssconvert (requires Gnumeric)
ssconvert "$input_xls" "$temp_csv"

# Step 2: Process the CSV to fill empty cells with "NA"
# This awk command uses a comma as the field separator, and if a field is empty, it is replaced with "NA"
awk -F',' '{
    for (i = 1; i <= NF; i++) {
        if ($i == "") {
            $i = "NA"
        }
    }
    print
}' OFS=',' "$temp_csv" > "$output_csv"

# Step 3: Convert the CSV to TSV using Python's CSV module to properly handle quoted fields
python - <<EOF
import csv
with open("$output_csv", newline="") as csvfile, open("$output_tsv", "w", newline="") as tsvfile:
    reader = csv.reader(csvfile)
    writer = csv.writer(tsvfile, delimiter="\t")
    for row in reader:
        writer.writerow(row)
EOF

# Cleanup temporary file
rm "$temp_csv"

echo "Conversion complete: CSV file '$output_csv' and TSV file '$output_tsv' have been created."
