#!/usr/bin/env python3
"""Merge FASTA records by exact record ID, keeping the latest incoming record."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from merge_master_csv import MergeError, backup_suffix, digest, master_lock


def read_fasta(path):
    """Return ordered ID -> (full header, sequence) records and duplicate count."""
    records = {}
    header = None
    sequence = []
    duplicates = 0
    record_number = 0

    def finish_record():
        nonlocal duplicates, record_number
        if header is None:
            return
        record_number += 1
        if not sequence:
            raise MergeError(f"{Path(path).name}: empty FASTA sequence at record {record_number}")
        identifier = header.split()[0]
        record = (header, "".join(sequence))
        if identifier in records:
            if records[identifier] != record:
                raise MergeError(
                    f"{Path(path).name}: conflicting duplicate FASTA ID at record {record_number}; "
                    "resolve duplicate records before merging"
                )
            duplicates += 1
        else:
            records[identifier] = record

    with open(path, encoding="utf-8-sig") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                finish_record()
                header = line[1:].strip()
                if not header or any(ord(char) < 32 and char != "\t" for char in header):
                    raise MergeError(f"{Path(path).name}: invalid FASTA header at line {line_number}")
                sequence = []
            else:
                if header is None:
                    raise MergeError(f"{Path(path).name}: sequence before the first FASTA header")
                value = "".join(line.split())
                if not re.fullmatch(r"[A-Za-z.*?\-]+", value):
                    raise MergeError(f"{Path(path).name}: invalid FASTA sequence text at line {line_number}")
                sequence.append(value)
    finish_record()
    return records, duplicates


def merge_records(existing, incoming, existing_duplicates=0, input_duplicates=0):
    merged = dict(existing)
    added = updated = unchanged = 0
    for identifier, record in incoming.items():
        if identifier not in existing:
            added += 1
        elif existing[identifier] != record:
            updated += 1
        else:
            unchanged += 1
        merged[identifier] = record
    return merged, {
        "added": added, "updated": updated, "unchanged": unchanged, "total": len(merged),
        "input_duplicates_collapsed": input_duplicates, "master_duplicates_collapsed": existing_duplicates,
    }


def write_fasta(path, records):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        for header, sequence in records.values():
            handle.write(">" + header + "\n")
            for offset in range(0, len(sequence), 80):
                handle.write(sequence[offset:offset + 80] + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def empty_stats(input_duplicates=0):
    return {"added": 0, "updated": 0, "unchanged": 0, "input_duplicates_collapsed": input_duplicates,
            "written": False, "skipped": "run FASTA contains no records"}


def merge_local(master, incoming, input_duplicates=0):
    if not incoming:
        return empty_stats(input_duplicates)
    master = Path(master).resolve()
    with master_lock(master):
        # A missing file is allowed; missing directories and unreadable files still fail.
        try:
            original = digest(master)
        except FileNotFoundError:
            original = None
        existing, duplicates = read_fasta(master) if original is not None else ({}, 0)
        merged, stats = merge_records(existing, incoming, duplicates, input_duplicates)
        if not stats["added"] and not stats["updated"] and not duplicates:
            return dict(stats, written=False)
        fd, filename = tempfile.mkstemp(prefix=".master-fasta-", dir=master.parent)
        os.close(fd)
        candidate = Path(filename)
        try:
            write_fasta(candidate, merged)
            if original is None:
                # Exclusive creation: a concurrent initializer must never be overwritten.
                os.link(candidate, master)
            else:
                if digest(master) != original:
                    raise MergeError("Master FASTA changed during merge; refusing to replace it")
                backup = Path(str(master) + ".bak." + backup_suffix())
                with open(backup, "xb") as target, open(master, "rb") as source:
                    os.fchmod(target.fileno(), master.stat().st_mode & 0o777)
                    shutil.copyfileobj(source, target)
                    target.flush()
                    os.fsync(target.fileno())
                if digest(backup) != original or digest(master) != original:
                    raise MergeError("Master FASTA changed during backup; refusing to replace it")
                shutil.copymode(master, candidate)
                os.replace(candidate, master)
                stats["backup"] = str(backup)
            return dict(stats, written=True, created=original is None)
        finally:
            candidate.unlink(missing_ok=True)


def merge_remote(remote, name, incoming, input_duplicates=0):
    if not incoming:
        return empty_stats(input_duplicates)
    with tempfile.TemporaryDirectory(prefix="fluseq-master-fasta-") as directory:
        directory = Path(directory)
        with remote.lock(name + ".lock"):
            original = directory / "original.fasta"
            exists = remote.get_if_exists(name, original)
            existing, duplicates = read_fasta(original) if exists else ({}, 0)
            merged, stats = merge_records(existing, incoming, duplicates, input_duplicates)
            if not stats["added"] and not stats["updated"] and not duplicates:
                return dict(stats, written=False)
            candidate = directory / "candidate.fasta"
            write_fasta(candidate, merged)
            suffix = backup_suffix()
            staged = name + ".tmp." + suffix
            check = directory / "check.fasta"
            if exists:
                backup = name + ".bak." + suffix
                remote.put_verified(original, backup, check)
                stats["backup"] = backup
            remote.put_verified(candidate, staged, check)
            if exists:
                remote.get(name, check)
                if digest(check) != digest(original):
                    raise MergeError("Remote master FASTA changed during merge; refusing to replace it")
                remote.command("rename", staged, name, "-f")
            else:
                # A normal rename refuses to replace a file created by another writer.
                remote.command("rename", staged, name)
            remote.get(name, check)
            if digest(check) != digest(candidate):
                raise MergeError(
                    "Remote master FASTA verification failed; backup: "
                    + stats.get("backup", "none (new archive)")
                )
            return dict(stats, written=True, created=not exists)


def prepare_fasta(config, fasta):
    if config["master"] is not None:
        master = Path(config["master"]).with_name("master.fasta")
        if Path(fasta).resolve() == master.resolve():
            raise MergeError("Run FASTA must be separate from master.fasta")
    return read_fasta(fasta)


def update_fasta(config, prepared):
    incoming, duplicates = prepared
    if config["master"] is not None:
        master = Path(config["master"]).with_name("master.fasta")
        return merge_local(master, incoming, duplicates)
    return merge_remote(config["master_smb"], "master.fasta", incoming, duplicates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master", required=True, type=Path, help="Existing or new local/mounted master FASTA")
    parser.add_argument("--fasta", required=True, type=Path, help="Completed run multi-FASTA")
    args = parser.parse_args()
    try:
        if args.master.resolve() == args.fasta.resolve():
            raise MergeError("Run FASTA must be separate from master FASTA")
        incoming, duplicates = read_fasta(args.fasta)
        print(json.dumps(merge_local(args.master, incoming, duplicates), sort_keys=True))
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"Master FASTA merge failed: {error}\n")


if __name__ == "__main__":
    main()
