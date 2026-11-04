#!/usr/bin/env python3
"""Inspect CSV column names without printing or writing patient records."""

import argparse
import csv
import json
from pathlib import Path


def read_headers(path):
    """Read a single CSV header, detecting common delimiters and encodings."""
    path = Path(path)
    with path.open("rb") as handle:
        prefix = handle.read(4)
    if prefix.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings = ("utf-16",)
    else:
        encodings = ("utf-8-sig", "cp1252")
    for encoding in encodings:
        try:
            with path.open(encoding=encoding, newline="") as handle:
                first_line = handle.readline()
            break
        except UnicodeDecodeError:
            continue
    else:
        raise ValueError(f"Cannot decode CSV header: {path}")
    candidates = [(len(next(csv.reader([first_line], delimiter=delimiter), [])), delimiter)
                  for delimiter in (";", ",", "\t")]
    _, delimiter = max(candidates, key=lambda candidate: candidate[0])
    with path.open(encoding=encoding, newline="") as handle:
        fields = [value.strip() for value in next(csv.reader(handle, delimiter=delimiter), [])]
    if not fields or any(not value for value in fields):
        raise ValueError(f"CSV header has empty column names: {path}")
    if len({value.casefold() for value in fields}) != len(fields):
        raise ValueError(f"CSV header has duplicate column names: {path}")
    return fields


def inspect(paths):
    headers = {name: read_headers(path) for name, path in paths.items() if path is not None}
    lowered = {name: {field.casefold() for field in fields} for name, fields in headers.items()}
    overlap = {}
    names = list(headers)
    for index, left in enumerate(names):
        for right in names[index + 1:]:
            overlap[f"{left}_and_{right}"] = [field for field in headers[left]
                                              if field.casefold() in lowered[right]]
    return {"columns": headers, "shared_columns": overlap}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for label in ("report", "metadata", "master"):
        parser.add_argument("--" + label, type=Path, help=f"Path to the {label} CSV")
    args = parser.parse_args()
    paths = vars(args)
    if not any(paths.values()):
        parser.error("provide at least one CSV path")
    try:
        print(json.dumps(inspect(paths), ensure_ascii=False, indent=2))
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
