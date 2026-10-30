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
INDEX = "Prove_LW_ID"
INDEX_SOURCE = "Master_Index_Source"
SEQUENCE_COLUMNS = ("NGS_LW_ID", "Sequence_ID", "SequenceID", "SampleID")


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
    for column in (INDEX_SOURCE, *SEQUENCE_COLUMNS, "OriginalName"):
        canonical[column.casefold()] = column
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
        for key in ("Key", INDEX, *SEQUENCE_COLUMNS, "OriginalName"):
            if key in output:
                output[key] = output[key].strip()
        converted.append(output)
    return list(dict.fromkeys(targets.values())), converted


def identifier(value):
    value = (value or "").strip()
    return "" if value.upper() in {"NA", "N/A", "NAN", "NONE", "NULL", "-"} else value


def sequence_id(row):
    """Sample maps to NGS_LW_ID in FASTQ; SampleID is the FASTA fallback."""
    return next((value for column in SEQUENCE_COLUMNS if (value := identifier(row.get(column)))), "")


def provisional(row):
    return row.get(INDEX_SOURCE) == "Sequence_ID"


def fill_index(row, label, number):
    key = identifier(row.get(INDEX))
    if not key:
        key = sequence_id(row)
        if not key:
            raise MergeError(f"{label}: missing {INDEX} and sequencing ID at row {number}")
        row[INDEX_SOURCE] = "Sequence_ID"
    row[INDEX] = key
    if provisional(row) and key != sequence_id(row):
        raise MergeError(f"{label}: provisional {INDEX} must equal its sequencing ID at row {number}")


def index_rows(rows, label):
    indexed = {}
    for number, row in enumerate(rows, 2):
        key = identifier(row.get(INDEX))
        if not key:
            raise MergeError(f"{label}: missing {INDEX} at row {number}")
        if key in indexed:
            raise MergeError(f"{label}: duplicate {INDEX} at row {number}; resolve the duplicate rows first")
        indexed[key] = row
    return indexed


def sequence_index(*tables, source="input"):
    indexed = {}
    first_records = {}
    for rows in tables:
        for record, row in enumerate(rows, 2):
            sequence = sequence_id(row)
            if not sequence:
                continue
            key = row[INDEX]
            if sequence in indexed and indexed[sequence] != key:
                raise MergeError(
                    f"{source}: sequencing ID (NGS_LW_ID/Sequence_ID) maps to multiple {INDEX} values "
                    f"(records {first_records[sequence]} and {record}); "
                    "run update_master_csv.py --check-identifiers to locate the conflicting rows"
                )
            indexed[sequence] = key
            first_records.setdefault(sequence, record)
    return indexed


def alias_index(rows, columns):
    """Retain ambiguous aliases so only a lookup using that alias fails."""
    aliases = {}
    for row in rows:
        for column in columns:
            value = identifier(row.get(column))
            if value:
                aliases.setdefault(value, set()).add(row[INDEX])
    return aliases


def exact_alias(aliases, value, label):
    matches = aliases.get(identifier(value), set())
    if len(matches) > 1:
        raise MergeError(f"{label}: ambiguous identifier matches multiple {INDEX} values")
    return next(iter(matches), None)


def prepare_indexes(master_rows, metadata_rows):
    """Migrate missing indexes and reconcile explicitly marked fallbacks."""
    for number, row in enumerate(metadata_rows, 2):
        fill_index(row, "metadata", number)
    meta = index_rows(metadata_rows, "metadata")
    meta_sequences = sequence_index(metadata_rows, source="metadata")
    legacy = alias_index(metadata_rows, (INDEX, "Key"))
    reindexed = set()
    for number, row in enumerate(master_rows, 2):
        missing = not identifier(row.get(INDEX))
        if missing or provisional(row):
            if not missing:
                fill_index(row, "master", number)
            match = meta_sequences.get(sequence_id(row))
            if match is None:
                matches = {key for column in ("Key", "OriginalName")
                           if (key := exact_alias(legacy, row.get(column), f"master row {number}")) is not None}
                if len(matches) > 1:
                    raise MergeError(f"master: legacy identifiers disagree at row {number}")
                match = next(iter(matches), None)
            if match is not None and not provisional(meta[match]):
                row[INDEX] = match
                row[INDEX_SOURCE] = INDEX
                reindexed.add(match)
            else:
                if match is not None and not sequence_id(row):
                    # Old FASTA-only rows may have just Key. Retain the matched
                    # sequencing ID as evidence for their new fallback index.
                    column = next(column for column in SEQUENCE_COLUMNS if identifier(meta[match].get(column)))
                    row[column] = meta[match][column]
                fill_index(row, "master", number)
                if missing:
                    reindexed.add(row[INDEX])
    existing = index_rows(master_rows, "master")
    master_sequences = sequence_index(master_rows, source="master")
    for sequence, key in meta_sequences.items():
        old_key = master_sequences.get(sequence)
        if old_key is None:
            continue
        if provisional(meta[key]) and not provisional(existing[old_key]):
            # Missing metadata must never downgrade a known specimen identifier.
            meta[key][INDEX] = old_key
            meta[key][INDEX_SOURCE] = INDEX
        elif old_key != key:
            raise MergeError(
                f"Sequencing ID maps to multiple {INDEX} values (master differs from metadata); "
                "run update_master_csv.py --check-identifiers to locate the conflicting rows"
            )
    meta = index_rows(metadata_rows, "metadata")
    by_sequence = sequence_index(master_rows, metadata_rows, source="master and metadata")
    return existing, meta, by_sequence, reindexed


def fasta_match(row, aliases, sequences):
    name = exact_alias(aliases, row.get("OriginalName"), "FASTA OriginalName")
    sequence = sequences.get(sequence_id(row))
    sample = exact_alias(aliases, row.get("SampleID"), "FASTA SampleID")
    matches = {key for key in (name, sequence, sample) if key is not None}
    if len(matches) > 1:
        raise MergeError("FASTA identifiers disagree; resolve the sample identifiers first")
    return next(iter(matches), None)


def merge_tables(master, metadata, report, workflow, assets=ASSETS, nonempty_report=False):
    columns, canonical = schema(assets)
    metadata_map = read_mapping(Path(assets) / "LABWAREDIRECT.xml", canonical)
    metadata_map["Key"] = "Metadata_Key"  # LabWare's Key is not RekvNr in the supplied XML.
    report_map = read_mapping(Path(assets) / ("FLUSEQ.xml" if workflow == "fastq" else "FLUSEQFASTA.xml"), canonical)
    # Both spellings are emitted by the current report writers.
    report_map.update({"Coverage-M": "NGS_Coverage_M", "Coverage-MP": "NGS_Coverage_M"})
    if workflow == "fasta":
        report_map["OriginalName"] = "OriginalName"
    master_headers, master_rows = transform(master, {}, canonical, "master")
    metadata_headers, metadata_rows = transform(metadata, metadata_map, canonical, "metadata")
    report_headers, report_rows = transform(report, report_map, canonical, "report")
    for reserved in (KEY_SOURCE, INDEX_SOURCE):
        if reserved in metadata_headers or reserved in report_headers:
            raise MergeError(f"{reserved} is reserved for master identifier provenance")
    if not {INDEX, "Key"}.intersection(master_headers):
        raise MergeError(f"master: required column {INDEX} is absent (legacy Key header also accepted)")
    if not {INDEX, *SEQUENCE_COLUMNS}.intersection(metadata_headers):
        raise MergeError(f"metadata: requires {INDEX} or a sequencing ID column")
    required = "Sample" if workflow == "fastq" else "OriginalName"
    if required not in report[0] or not report_rows:
        raise MergeError(f"report: requires {required} and at least one data row")
    existing, meta, by_sequence, reindexed = prepare_indexes(master_rows, metadata_rows)
    aliases = alias_index([*existing.values(), *meta.values()], (INDEX, "Key", "OriginalName", "SampleID"))
    for number, row in enumerate(report_rows, 2):
        if not identifier(row.get("NGS_LW_ID" if workflow == "fastq" else "OriginalName")):
            raise MergeError(f"report: missing {required} at row {number}")
        key = by_sequence.get(sequence_id(row)) if workflow == "fastq" else fasta_match(row, aliases, by_sequence)
        supplied = identifier(row.get(INDEX))
        if supplied and key is not None and supplied != key:
            raise MergeError(f"report: {INDEX} and report identifier disagree at row {number}")
        if key is None:
            key = supplied or sequence_id(row)
            if not key:
                raise MergeError(f"report: missing {INDEX} and sequencing ID at row {number}")
            if not supplied and (key in existing or key in meta):
                raise MergeError(f"report: provisional sequencing ID collides with an unrelated {INDEX} at row {number}")
            if not supplied:
                row[INDEX_SOURCE] = "Sequence_ID"
        row[INDEX] = key
    incoming = index_rows(report_rows, "report")
    # Apart from index migration, only report samples are updated or inserted.
    # Metadata-only rows must not create entries for unanalysed samples.
    added = updated = unchanged = without_metadata = 0
    for key, row in incoming.items():
        old = existing.get(key)
        merged = dict(old or {INDEX: key})
        if key in meta:
            merged.update({name: value for name, value in meta[key].items() if value.strip()})
        else:
            without_metadata += 1
        merged.update({name: value for name, value in row.items() if not nonempty_report or value.strip()})
        merged[INDEX] = key  # A blank report cell must never erase the index.
        if old is None:
            added += 1
        elif key not in reindexed and all(
            old.get(name, "") == merged.get(name, "") for name in old.keys() | merged.keys()
        ):
            unchanged += 1
        else:
            updated += 1
        existing[key] = merged
    for number, row in enumerate(existing.values(), 2):
        fill_index(row, "merged master", number)
    index_rows(existing.values(), "merged master")
    sequence_index(existing.values(), source="merged master")
    headers = list(dict.fromkeys(columns + master_headers + metadata_headers + report_headers))
    if any(INDEX_SOURCE in row for row in existing.values()) and INDEX_SOURCE not in headers:
        headers.append(INDEX_SOURCE)
    return headers, list(existing.values()), {
        "added": added, "updated": updated, "unchanged": unchanged,
        "without_metadata": without_metadata, "total": len(existing), "columns": len(headers),
        "reindexed": len(reindexed),
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
