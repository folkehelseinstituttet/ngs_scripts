#!/usr/bin/env python3
import argparse
import sys
import zipfile
from pathlib import Path

import pandas as pd


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--xls", required=True, help="Path to Excel file (.xls or .xlsx; extension may be misleading)")
    p.add_argument("--output", required=True, help="Output CSV path, or /dev/stdout")
    args = p.parse_args()

    xls_path = Path(args.xls)

    # Detect by file content, not extension:
    # - XLSX is a zip container
    # - XLS (old) is OLE2
    is_xlsx = zipfile.is_zipfile(xls_path)

    engine = "openpyxl" if is_xlsx else "xlrd"

    df = pd.read_excel(xls_path, dtype=str, engine=engine).fillna("")

    if args.output == "/dev/stdout":
        df.to_csv(sys.stdout, index=False)
    else:
        df.to_csv(args.output, index=False)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
