#!/usr/bin/env python3
"""
datavalidation.py

Validate metadata rows and remove bad ones WITHOUT renaming any columns.

Validations:
  1) Date columns: must be complete YYYY-MM-DD and parse to a real date.
  2) Name column: must NOT contain invalid characters (default: apostrophe ' and backslash \\),
     because augur/iqtree will fail on those names.

Reads:   .xls/.xlsx/.xlsm/.tsv/.csv
Writes:  .xlsx OR .xls OR .tsv OR .csv

Reports:
  - removed_rows.preview.tsv : key columns + removal reasons
  - removed_rows.full.tsv    : full removed rows + removal reasons
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date as date_cls
from pathlib import Path
from typing import Dict, List, Tuple

import pandas as pd

# Optional dependency for writing .xls
try:
    import xlwt  # type: ignore
except Exception:
    xlwt = None  # handled at runtime

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def read_table(path: Path) -> pd.DataFrame:
    suf = path.suffix.lower()

    if suf in {".tsv", ".tab"}:
        return pd.read_csv(path, sep="\t", dtype=str, keep_default_na=False)
    if suf == ".csv":
        return pd.read_csv(path, dtype=str, keep_default_na=False)

    if suf in {".xlsx", ".xlsm"}:
        return pd.read_excel(path, dtype=str, keep_default_na=False, engine="openpyxl")

    if suf == ".xls":
        # Could be true old .xls OR mislabeled xlsx ("Excel 2007+").
        # Try openpyxl first, then fall back to xlrd.
        try:
            return pd.read_excel(path, dtype=str, keep_default_na=False, engine="openpyxl")
        except Exception:
            return pd.read_excel(path, dtype=str, keep_default_na=False, engine="xlrd")

    raise ValueError(f"Unsupported input type: {suf}. Use .xls/.xlsx/.tsv/.csv")


def validate_full_dates(series: pd.Series) -> Tuple[pd.Series, pd.Series]:
    """
    Returns (parsed_dates, invalid_mask)
    invalid_mask True means invalid/incomplete/missing date.

    Valid format is strictly YYYY-MM-DD and must parse to a real calendar date.
    """
    s = series.astype(str).str.strip()

    pattern_ok = s.apply(lambda x: bool(DATE_RE.match(x)))
    parsed = pd.to_datetime(s.where(pattern_ok), format="%Y-%m-%d", errors="coerce")

    invalid = ~pattern_ok | parsed.isna()

    # Optional sanity bounds
    today = pd.Timestamp(date_cls.today())
    too_old = parsed < pd.Timestamp("1900-01-01")
    too_new = parsed > (today + pd.Timedelta(days=366))
    invalid = invalid | (parsed.notna() & (too_old | too_new))

    return parsed, invalid


def validate_names(series: pd.Series, invalid_pattern: re.Pattern) -> pd.Series:
    """
    Return boolean mask: True = invalid name.
    Invalid if:
      - missing/blank after strip
      - contains invalid characters matching invalid_pattern
    """
    s = series.astype(str).str.strip()
    missing = s.eq("") | s.str.lower().isin({"nan", "none", "na", "n/a", "null", "unknown"})
    has_bad_chars = s.apply(lambda x: bool(invalid_pattern.search(x)))
    return missing | has_bad_chars


def write_xls(df: pd.DataFrame, out_path: Path, sheet_name: str = "metadata") -> None:
    # .xls limit: 65536 rows total including header
    if len(df) + 1 > 65536:
        raise SystemExit(
            f"[ERROR] {len(df)} rows won't fit in .xls (max 65535 data rows). "
            f"Use .xlsx or split the file."
        )
    if xlwt is None:
        raise SystemExit("[ERROR] Writing .xls requires xlwt. Install: conda install -c conda-forge xlwt")

    wb = xlwt.Workbook()
    ws = wb.add_sheet(sheet_name[:31])

    # Header
    for colx, col in enumerate(df.columns):
        ws.write(0, colx, str(col))

    # Rows
    for rowx, row in enumerate(df.itertuples(index=False), start=1):
        for colx, val in enumerate(row):
            if val is None:
                ws.write(rowx, colx, "")
            else:
                sval = str(val).strip()
                ws.write(rowx, colx, "" if sval.lower() == "nan" else sval)

    wb.save(str(out_path))


def write_output(df: pd.DataFrame, out_path: Path, sheet_name: str = "metadata") -> None:
    suf = out_path.suffix.lower()

    if suf in {".tsv", ".tab"}:
        df.to_csv(out_path, sep="\t", index=False)
        return
    if suf == ".csv":
        df.to_csv(out_path, index=False)
        return
    if suf == ".xlsx":
        # Requires openpyxl
        try:
            df.to_excel(out_path, index=False, engine="openpyxl", sheet_name=sheet_name[:31])
        except ModuleNotFoundError as e:
            raise SystemExit(
                "[ERROR] Writing .xlsx requires openpyxl. Install: conda install -c conda-forge openpyxl\n"
                f"Original error: {e}"
            )
        return
    if suf == ".xls":
        write_xls(df, out_path, sheet_name=sheet_name)
        return

    raise SystemExit(f"[ERROR] Unsupported output extension: {suf} (use .xlsx/.xls/.tsv/.csv)")


def add_reason(reasons: List[List[str]], idx: int, reason: str) -> None:
    if reason not in reasons[idx]:
        reasons[idx].append(reason)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="Input metadata file (e.g. data/.../metadata.xls)")
    ap.add_argument("--output", required=True, help="Output file (.xlsx/.xls/.tsv/.csv)")

    ap.add_argument(
        "--date-cols",
        default="Collection_Date,Submission_Date",
        help="Comma-separated date columns to validate (default: Collection_Date,Submission_Date).",
    )
    ap.add_argument(
        "--require-all",
        action="store_true",
        help="Drop row if ANY listed date-col is invalid (strict). "
             "If not set: drop only if ALL listed date-cols are invalid.",
    )

    ap.add_argument(
        "--strain-col",
        default="Isolate_Name",
        help="Column containing isolate/strain name to validate (default: Isolate_Name).",
    )
    ap.add_argument(
        "--invalid-strain-pattern",
        default=r"[\'\\]",
        help=r"Regex of invalid characters for names (default matches apostrophe ' and backslash \).",
    )
    ap.add_argument(
        "--skip-strain-validation",
        action="store_true",
        help="If set, do not validate the strain/name column.",
    )

    ap.add_argument(
        "--report-preview",
        default="removed_rows.preview.tsv",
        help="Key-column preview of removed rows + reasons (TSV).",
    )
    ap.add_argument(
        "--report-full",
        default="removed_rows.full.tsv",
        help="Full removed rows + reasons (TSV).",
    )

    args = ap.parse_args()

    in_path = Path(args.input)
    out_path = Path(args.output)
    preview_path = Path(args.report_preview)
    full_path = Path(args.report_full)

    df = read_table(in_path)
    df.columns = [c.strip() for c in df.columns]
    df = df.reset_index(drop=True)

    # --- DATE VALIDATION ---
    date_cols = [c.strip() for c in args.date_cols.split(",") if c.strip()]
    missing_dates = [c for c in date_cols if c not in df.columns]
    if missing_dates:
        print(f"[ERROR] Missing date column(s): {missing_dates}", file=sys.stderr)
        print(f"Available columns: {list(df.columns)}", file=sys.stderr)
        return 2

    date_invalid_masks: Dict[str, pd.Series] = {}
    for col in date_cols:
        _, inv = validate_full_dates(df[col])
        date_invalid_masks[col] = inv

    if args.require_all:
        date_drop_mask = pd.Series(False, index=df.index)
        for col in date_cols:
            date_drop_mask |= date_invalid_masks[col]
    else:
        date_drop_mask = pd.Series(True, index=df.index)
        for col in date_cols:
            date_drop_mask &= date_invalid_masks[col]

    # --- NAME VALIDATION ---
    name_drop_mask = pd.Series(False, index=df.index)
    name_col = args.strain_col.strip()

    if not args.skip_strain_validation:
        if name_col not in df.columns:
            print(f"[ERROR] Missing name column: {name_col}", file=sys.stderr)
            print(f"Available columns: {list(df.columns)}", file=sys.stderr)
            return 2
        invalid_pat = re.compile(args.invalid_strain-pattern) if False else re.compile(args.invalid_strain_pattern)
        name_drop_mask = validate_names(df[name_col], invalid_pat)

    # --- COMBINE + REASONS ---
    drop_mask = date_drop_mask | name_drop_mask
    reasons: List[List[str]] = [[] for _ in range(len(df))]

    for col in date_cols:
        inv = date_invalid_masks[col]
        for i in inv[inv].index:
            add_reason(reasons, int(i), f"invalid_date:{col}")

    if not args.skip_strain_validation:
        for i in name_drop_mask[name_drop_mask].index:
            add_reason(reasons, int(i), f"invalid_name:{name_col}")

    removed = df.loc[drop_mask].copy()
    kept = df.loc[~drop_mask].copy()

    removed["_removal_reasons"] = [";".join(reasons[i]) for i in removed.index]

    # Reports
    removed.to_csv(full_path, sep="\t", index=False)

    preview_cols: List[str] = []
    for c in [name_col, "Isolate_Id", "Isolate_Name"]:
        if c in removed.columns and c not in preview_cols:
            preview_cols.append(c)
    for c in date_cols:
        if c in removed.columns and c not in preview_cols:
            preview_cols.append(c)
    preview_cols.append("_removal_reasons")
    removed[preview_cols].to_csv(preview_path, sep="\t", index=False)

    # Output cleaned file (same columns as input)
    write_output(kept, out_path)

    # Summary
    print(f"[INFO] Rows in: {len(df)}")
    print(f"[INFO] Rows kept: {len(kept)}")
    print(f"[INFO] Rows removed: {len(removed)}")
    for col in date_cols:
        print(f"[INFO] Invalid '{col}': {int(date_invalid_masks[col].sum())}")
    if not args.skip_strain_validation:
        print(f"[INFO] Invalid names in '{name_col}' (pattern {args.invalid_strain_pattern!r}): {int(name_drop_mask.sum())}")
    print(f"[INFO] Removed rows preview: {preview_path}")
    print(f"[INFO] Removed rows full: {full_path}")
    print(f"[INFO] Wrote cleaned file to: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
