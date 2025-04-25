#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if [ $# -lt 1 ]; then
  echo "Usage: $0 input.xls"
  exit 1
fi
infile="$1"

# Derive base name (foo.xls → foo)
base="${infile%.*}"

# Read Excel → fill blanks → write CSV & TSV in one go
python3 - "$infile" <<'PYCODE'
import sys, pandas as pd

infile = sys.argv[1]
df = pd.read_excel(infile, dtype=str)
df.fillna("NA", inplace=True)

base = infile.rsplit('.', 1)[0]
df.to_csv(f"{base}.csv", index=False)
df.to_csv(f"{base}.tsv", sep="\t", index=False)
print(f"Done → {base}.csv, {base}.tsv")
PYCODE
