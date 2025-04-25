#!/usr/bin/env python3
import pandas as pd
import sys
import re

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} input.tsv output.tsv")
    sys.exit(1)

infile, outfile = sys.argv[1], sys.argv[2]

# 1) read
df = pd.read_csv(infile, sep="\t", dtype=str)

# 2) lowercase all column names
df.columns = [c.lower() for c in df.columns]

# 3) rename
df = df.rename(columns={
    "isolate_name": "strain",
    "subtype":      "subvirus_type",
    "collection_date": "date"
})

# 4) clean up virus_type (collapse A / H5N1 → H5N1)
df["subvirus_type"] = df["subvirus_type"].str.replace(r"A\s*/\s*H5N1", "H5N1", regex=True)

# 5) split location → region / country / division
#    strip whitespace, then split on " / ", max 2 splits
loc = df["location"].str.strip().str.split(r"\s*/\s*", n=2, expand=True)
df["region"]   = loc[0].fillna("")
df["country"]  = loc[1].fillna("")
df["division"] = loc[2].fillna("")

# 6) add genoflu column
df["genoflu"] = "unknown"

# 7) fill empties with "NA"
#    first, strip all string columns of whitespace
for col in df.select_dtypes(include="object"):
    df[col] = df[col].str.strip()

#    then replace any blank or NaN with "NA"
df = df.replace(r'^\s*$', "NA", regex=True).fillna("NA")

# 8) write back out
df.to_csv(outfile, sep="\t", index=False)
