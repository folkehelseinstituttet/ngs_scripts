#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 input.xls"
  exit 1
fi
in="$1"

# Read Excel → fill blanks → write CSV & TSV in one go
python3 - <<'PYCODE'
import sys, pandas as pd

# Read as strings so blank cells become NaN
df = pd.read_excel(sys.argv[1], dtype=str)
df.fillna("NA", inplace=True)

df.to_csv("output.csv", index=False)
df.to_csv("output.tsv", sep="\t", index=False)
print("Done → output.csv, output.tsv")
PYCODE
