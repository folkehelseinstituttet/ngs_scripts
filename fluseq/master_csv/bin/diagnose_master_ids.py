"""Read-only diagnostics for sequencing identifiers shared by different keys."""

from collections import defaultdict
import os
from pathlib import Path
import tempfile

from merge_master_csv import ASSETS, KEY_SOURCE, MergeError, read_mapping, schema, transform, write_table


COLUMNS = ["NGS_LW_ID", "source", "record", "Key", "Master_Key_Source", "in_current_report", "conflict"]


def find_conflicts(master, metadata, report=None, workflow="fastq"):
    _, canonical = schema()
    mapping = read_mapping(ASSETS / "LABWAREDIRECT.xml", canonical)
    mapping["Key"] = "Metadata_Key"
    _, master_rows = transform(master, {}, canonical, "master")
    _, metadata_rows = transform(metadata, mapping, canonical, "metadata")
    report_ids = None
    if report is not None:
        column = "Sample" if workflow == "fastq" else "OriginalName"
        if column not in report[0]:
            raise MergeError(f"Report requires {column} for identifier diagnostics")
        report_ids = {row[column].strip() for row in report[1]}

    groups = defaultdict(list)
    for source, rows in (("master", master_rows), ("metadata", metadata_rows)):
        for record, row in enumerate(rows, 2):
            sequence = row.get("NGS_LW_ID", "").strip()
            # Match the merger's missing-identifier rules exactly.
            if not sequence or sequence.upper() in {"NA", "NAN", "NONE", "NULL"}:
                continue
            groups[sequence].append({
                "NGS_LW_ID": sequence, "source": source, "record": record,
                "Key": row.get("Key", ""), "Master_Key_Source": row.get(KEY_SOURCE, ""),
            })

    conflicts = []
    for sequence, records in sorted(groups.items()):
        master_records = [row for row in records if row["source"] == "master"]
        master_keys = {row["Key"] for row in master_records}
        metadata_keys = {row["Key"] for row in records if row["source"] == "metadata"}
        reasons = []
        if len(master_keys) > 1:
            reasons.append("multiple Keys within master")
        if len(metadata_keys) > 1:
            reasons.append("multiple RekvNr values within metadata")
        if master_keys and metadata_keys and master_keys != metadata_keys:
            provisional = len(master_records) == 1 and len(metadata_keys) == 1 and (
                master_records[0]["Master_Key_Source"] == "Sample" and master_records[0]["Key"] == sequence
            )
            if not provisional:
                reasons.append("master Key differs from metadata RekvNr")
        if not reasons:
            continue
        involved = "not checked" if report_ids is None else (
            "yes" if (sequence in report_ids if workflow == "fastq" else any(row["Key"] in report_ids for row in records)) else "no"
        )
        conflicts.extend(dict(row, in_current_report=involved, conflict="; ".join(reasons)) for row in records)
    return conflicts


def write_conflicts(path, rows):
    """Write only identifier evidence, with private permissions, to the chosen file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, filename = tempfile.mkstemp(prefix=".identifier-audit-", dir=path.parent)
    os.close(fd)
    temporary = Path(filename)
    try:
        write_table(temporary, COLUMNS, rows)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)
