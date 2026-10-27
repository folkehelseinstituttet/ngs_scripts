#!/usr/bin/env python3
"""Merge final report CSVs and LabWare metadata into the master, using import XMLs.

No biological interpretation or numeric/date conversion is performed. All cells
remain text. See docs/master_csv.md for identifier and update rules.
"""

import argparse
import base64
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
import uuid
import xml.etree.ElementTree as ET
from contextlib import contextmanager
from datetime import datetime, timezone


ASSETS = Path(__file__).resolve().parents[1] / "assets" / "master_csv"
KEY_SOURCE = "Master_Key_Source"


class MergeError(ValueError):
    """An input cannot be merged without guessing or losing data."""


def read_table(path, encoding="auto"):
    data = Path(path).read_bytes()
    if encoding == "auto":
        if data.startswith((b"\xff\xfe", b"\xfe\xff")):
            encoding = "utf-16"
        else:
            try:
                data.decode("utf-8-sig")
                encoding = "utf-8-sig"
            except UnicodeDecodeError:
                encoding = "cp1252"
    text = data.decode(encoding).lstrip("\ufeff")
    # Inspect the parsed header only; commas/semicolons in quoted cells are data.
    candidates = []
    for delimiter in (";", ",", "\t"):
        header = next(csv.reader(io.StringIO(text), delimiter=delimiter), [])
        candidates.append((len(header), delimiter))
    delimiter = max(candidates, key=lambda candidate: candidate[0])[1]
    reader = csv.reader(io.StringIO(text, newline=""), delimiter=delimiter, strict=True)
    header = [name.strip() for name in next(reader, [])]
    if not header or any(not name for name in header):
        raise MergeError(f"{Path(path).name}: missing or empty column names")
    if len(set(name.casefold() for name in header)) != len(header):
        raise MergeError(f"{Path(path).name}: duplicate column names")
    rows = []
    for values in reader:
        if not values or not any(value.strip() for value in values):
            continue
        if len(values) != len(header):
            raise MergeError(f"{Path(path).name}: wrong number of cells near line {reader.line_num}")
        rows.append(dict(zip(header, values)))
    return header, rows


def schema(assets=ASSETS):
    columns = (Path(assets) / "columns.txt").read_text(encoding="utf-8").splitlines()
    canonical = {column.casefold(): column for column in columns}
    canonical[KEY_SOURCE.casefold()] = KEY_SOURCE
    # Preserve the exact spellings requested for the existing master export.
    for alias in ("Pasient_Kjonn", "Pasient_Kjønn"):
        canonical[alias.casefold()] = "Pasient_Kjnn"
    for alias in ("Prove_Manad", "Prove_Maanad", "Prove_Månad"):
        canonical[alias.casefold()] = "Prove_M nad"
    return columns, canonical


def read_mapping(path, canonical):
    decode = lambda value: base64.b64decode(value, validate=True).decode("utf-8")
    mapping = {}
    for binding in ET.parse(path).getroot().findall("./Bindings/Binding"):
        parse = binding.find("Parse")
        default = binding.find("Default")
        if (
            binding.get("IsLink") not in {"0", "1"}
            or parse is None
            or parse.get("IsRegex") != "0"
            or decode(parse.get("Parsing", "")) != "[DATA]"
            or decode(parse.get("Decoration", "")) != "[DATA]"
            or default is None
            or default.get("HasDefault") != "0"
        ):
            raise MergeError(f"Unsupported transformation in {Path(path).name}")
        source = decode(binding.find("Src").get("Id"))
        dest = decode(binding.find("Dest").get("Id"))
        if dest == "__Key__":
            dest = "Key"
        elif dest == "__None__":
            dest = source  # New master retains fields ignored by the old importer.
        dest = canonical.get(dest.casefold(), dest)
        if source in mapping and mapping[source] != dest:
            raise MergeError(f"Conflicting mapping in {Path(path).name}: {source}")
        mapping[source] = dest
    return mapping


def transform(table, mapping, canonical, label):
    headers, rows = table
    targets = {name: mapping.get(name, canonical.get(name.casefold(), name)) for name in headers}
    converted = []
    for number, row in enumerate(rows, 2):
        output = {}
        for name, value in row.items():
            dest = targets[name]
            previous = output.get(dest, "")
            if previous.strip() and value.strip() and previous != value:
                raise MergeError(f"{label}: conflicting columns for {dest} at row {number}")
            if value.strip() or dest not in output:
                output[dest] = value
        for key in ("Key", "NGS_LW_ID"):
            if key in output:
                output[key] = output[key].strip()
        converted.append(output)
    return list(dict.fromkeys(targets.values())), converted


def index_rows(rows, label):
    indexed = {}
    for number, row in enumerate(rows, 2):
        key = row.get("Key", "")
        if not key or key.upper() in {"NA", "NAN", "NONE", "NULL"}:
            raise MergeError(f"{label}: missing Key at row {number}")
        if key in indexed:
            raise MergeError(f"{label}: duplicate Key at row {number}")
        indexed[key] = row
    return indexed


def sequence_index(*tables):
    indexed = {}
    for rows in tables:
        for row in rows:
            sequence = row.get("NGS_LW_ID", "").strip()
            if not sequence or sequence.upper() in {"NA", "NAN", "NONE", "NULL"}:
                continue
            key = row["Key"]
            if sequence in indexed and indexed[sequence] != key:
                raise MergeError("NGS_LW_ID maps to multiple master Keys; resolve the identifiers first")
            indexed[sequence] = key
    return indexed


def resolve_report_keys(existing, metadata_rows, report_rows, workflow):
    """Resolve sequencing IDs, including provisional rows awaiting metadata."""
    by_sequence = sequence_index(existing.values())
    metadata_sequences = sequence_index(metadata_rows)
    if workflow == "fastq":
        relevant_sequences = {row.get("NGS_LW_ID", "") for row in report_rows}
    else:
        report_keys = {row.get("Key", "") for row in report_rows}
        relevant_sequences = {row.get("NGS_LW_ID", "") for row in metadata_rows if row["Key"] in report_keys}
    replacements = {}
    resolved_keys = set()
    for sequence, key in metadata_sequences.items():
        old_key = by_sequence.get(sequence)
        if old_key is None:
            continue
        old = existing[old_key]
        if old.get(KEY_SOURCE) != "Sample":
            if old_key != key:
                raise MergeError("NGS_LW_ID maps to multiple master Keys; resolve the identifiers first")
            continue
        if old_key != sequence:
            raise MergeError("Provisional master Key must equal its NGS_LW_ID")
        if sequence not in relevant_sequences:
            continue
        if key != old_key and key in existing:
            raise MergeError("Provisional sample resolves to an existing master Key; resolve the duplicate rows first")
        replacements[old_key] = dict(old, Key=key, **{KEY_SOURCE: "RekvNr"})
        resolved_keys.add(key)
    # Keep unrelated samples and the existing row order intact.
    existing = {
        replacements[key]["Key"] if key in replacements else key: replacements.get(key, row)
        for key, row in existing.items()
    }
    by_sequence.update(metadata_sequences)
    return existing, by_sequence, resolved_keys


def merge_tables(master, metadata, report, workflow, assets=ASSETS, nonempty_report=False):
    columns, canonical = schema(assets)
    metadata_map = read_mapping(Path(assets) / "LABWAREDIRECT.xml", canonical)
    metadata_map["Key"] = "Metadata_Key"  # LabWare's Key is not RekvNr in the supplied XML.
    report_map = read_mapping(Path(assets) / ("FLUSEQ.xml" if workflow == "fastq" else "FLUSEQFASTA.xml"), canonical)
    # Both spellings are emitted by the current report writers.
    report_map.update({"Coverage-M": "NGS_Coverage_M", "Coverage-MP": "NGS_Coverage_M"})
    master_headers, master_rows = transform(master, {}, canonical, "master")
    metadata_headers, metadata_rows = transform(metadata, metadata_map, canonical, "metadata")
    report_headers, report_rows = transform(report, report_map, canonical, "report")
    if KEY_SOURCE in metadata_headers or KEY_SOURCE in report_headers:
        raise MergeError(f"{KEY_SOURCE} is reserved for master key provenance")
    if "Key" not in master_headers:
        raise MergeError("master: required column Key is absent")
    if "RekvNr" not in metadata[0]:
        raise MergeError("metadata: required column RekvNr is absent (LABWAREDIRECT key)")
    required = "Sample" if workflow == "fastq" else "OriginalName"
    if required not in report[0] or not report_rows:
        raise MergeError(f"report: requires {required} and at least one data row")
    existing = index_rows(master_rows, "master")
    meta = index_rows(metadata_rows, "metadata")
    existing, by_sequence, resolved_keys = resolve_report_keys(existing, metadata_rows, report_rows, workflow)
    provisional_keys = set()
    if workflow == "fastq":
        for number, row in enumerate(report_rows, 2):
            sequence = row.get("NGS_LW_ID", "")
            if not sequence or sequence.upper() in {"NA", "NAN", "NONE", "NULL"}:
                raise MergeError(f"report: missing Sample at row {number}")
            key = by_sequence.get(sequence)
            if key is None:
                key = sequence
                if key in existing or key in meta:
                    raise MergeError(f"report: provisional Sample key collides with an unrelated Key at row {number}")
                row[KEY_SOURCE] = "Sample"
                provisional_keys.add(key)
            elif existing.get(key, {}).get(KEY_SOURCE) == "Sample" and existing[key].get("NGS_LW_ID") != sequence:
                raise MergeError(f"report: Sample maps to an unrelated provisional Key at row {number}")
            if row.get("Key", key) != key:
                raise MergeError(f"report: Key and Sample disagree at row {number}")
            row["Key"] = key
    incoming = index_rows(report_rows, "report")
    # Only samples in this report are changed or inserted. Metadata-only rows
    # must not create entries for samples that have not been analysed.
    added = updated = unchanged = without_metadata = 0
    for key, row in incoming.items():
        old = existing.get(key)
        merged = dict(old or {"Key": key})
        if key in meta and merged.get(KEY_SOURCE) != "Sample":
            merged.update({name: value for name, value in meta[key].items() if value.strip()})
        else:
            without_metadata += 1
        merged.update({name: value for name, value in row.items() if not nonempty_report or value.strip()})
        if old is None:
            added += 1
        elif key not in resolved_keys and all(
            old.get(name, "") == merged.get(name, "") for name in old.keys() | merged.keys()
        ):
            unchanged += 1
        else:
            updated += 1
        existing[key] = merged
    sequence_index(existing.values())
    headers = list(dict.fromkeys(columns + master_headers + metadata_headers + report_headers))
    if provisional_keys and KEY_SOURCE not in headers:
        headers.append(KEY_SOURCE)
    return headers, list(existing.values()), {
        "added": added, "updated": updated, "unchanged": unchanged,
        "without_metadata": without_metadata, "total": len(existing), "columns": len(headers),
    }


def write_table(path, headers, rows):
    with open(path, "w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, delimiter=";", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        handle.flush()
        os.fsync(handle.fileno())


def digest(path):
    checksum = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def backup_suffix():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "." + uuid.uuid4().hex


@contextmanager
def master_lock(master):
    lock = Path(str(master) + ".lock")
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError as error:
        raise MergeError(f"Master is locked: {lock}; check for an active writer before removing a stale lock") from error
    try:
        yield
    finally:
        lock.rmdir()


def merge_files(master, metadata, report, workflow, output=None, assets=ASSETS, nonempty_report=False, encoding="auto"):
    master, metadata, report = (Path(path).resolve() for path in (master, metadata, report))
    output = Path(output).resolve() if output else master
    if master in (metadata, report) or output in (metadata, report):
        raise MergeError("Output/master must be separate from report and metadata")
    # A separate output is a preview and never overwrites an existing file.
    if output != master and output.exists():
        raise MergeError("Preview output already exists; choose a new path")
    with master_lock(master):
        original = digest(master)
        headers, rows, stats = merge_tables(
            read_table(master, encoding), read_table(metadata, encoding), read_table(report, encoding),
            workflow, assets, nonempty_report,
        )
        fd, temporary = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
        os.close(fd)
        temporary = Path(temporary)
        try:
            write_table(temporary, headers, rows)
            if digest(master) != original:
                raise MergeError("Master changed during merge; refusing to replace it")
            if output == master:
                if digest(temporary) == original:
                    return dict(stats, written=False)
                backup = Path(str(master) + ".bak." + backup_suffix())
                with open(backup, "xb") as target, open(master, "rb") as source:
                    os.fchmod(target.fileno(), master.stat().st_mode & 0o777)
                    shutil.copyfileobj(source, target)
                    target.flush()
                    os.fsync(target.fileno())
                if digest(backup) != original or digest(master) != original:
                    raise MergeError("Master changed during backup; refusing to replace it")
                shutil.copymode(master, temporary)
                os.replace(temporary, master)
                stats["backup"] = str(backup)
            else:
                # Exclusive creation prevents a racing preview from being lost.
                with open(output, "xb") as target, open(temporary, "rb") as source:
                    shutil.copyfileobj(source, target)
                    target.flush()
                    os.fsync(target.fileno())
            return dict(stats, written=True)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master", type=Path, required=True, help="Existing master CSV (header-only is supported)")
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--workflow", choices=("fastq", "fasta"), required=True)
    parser.add_argument("--output", type=Path, help="Write a new preview file instead of updating master")
    parser.add_argument("--assets", type=Path, default=ASSETS)
    parser.add_argument("--encoding", default="auto", help="Input encoding; auto tries UTF-8, UTF-16 BOM, then CP1252")
    parser.add_argument("--nonempty-report", action="store_true", help="Preserve old analysis values when new cells are blank")
    args = parser.parse_args()
    try:
        stats = merge_files(**vars(args))
    except (OSError, ValueError, csv.Error, ET.ParseError) as error:
        parser.exit(1, f"Master merge failed: {error}\n")
    print(json.dumps(stats, sort_keys=True))


if __name__ == "__main__":
    main()
