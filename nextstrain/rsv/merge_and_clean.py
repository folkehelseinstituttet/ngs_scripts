import sys
import os
import pandas as pd

if len(sys.argv) != 2:
    print("Usage: python merge_and_clean.py [a|b]")
    sys.exit(1)

dir_choice = sys.argv[1]
if dir_choice not in ['a', 'b']:
    print("Invalid argument. Must be 'a' or 'b'.")
    sys.exit(1)

input_dir = f"data/{dir_choice}"
metadata_file = os.path.join(input_dir, "metadata.tsv")
metadata_world_file = os.path.join(input_dir, "metadata_world.tsv.gz")
output_file = os.path.join(input_dir, "metadata_cleaned.tsv")

coverage_columns = ["genome_coverage", "F_coverage", "G_coverage"]

df_main = pd.read_csv(metadata_file, sep="\t", dtype=str)
df_world = pd.read_csv(metadata_world_file, sep="\t", dtype=str, compression="gzip")

df = pd.concat([df_main, df_world], ignore_index=True)

for col in coverage_columns:
    if col not in df.columns:
        df[col] = "0"

for col in coverage_columns:
    df[col] = pd.to_numeric(df[col], errors="coerce")
df[coverage_columns] = df[coverage_columns].fillna(0)

df.to_csv(output_file, sep="\t", index=False)
print(f"Merged and cleaned metadata saved to {output_file}")
