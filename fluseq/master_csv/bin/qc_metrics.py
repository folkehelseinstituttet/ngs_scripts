"""Read existing run QC and qPCR results without recalculating sequence calls."""

import math
import re

from merge_master_csv import (
    INDEX, MergeError, alias_index, fasta_match, identifier, index_rows, schema,
    sequence_id, sequence_index, transform,
)

SEGMENT_PROTEINS = {
    "HA": ("HA", "HA1", "HA2"), "NA": ("NA",),
    "MP": ("M", "MP", "M1", "M2", "MP1", "MP2"),
    "NP": ("NP",), "NS": ("NS",), "PA": ("PA",), "PB1": ("PB1",), "PB2": ("PB2",),
}
MISSING = {"", "NA", "NAN", "NONE", "NULL", "N/A", "-"}
POSITIVE = {"påvist"}
NEGATIVE = {"negativ", "negative", "neg", "ikke påvist", "not detected"}
ASSAYS = {"H1": "A/H1", "H3": "A/H3", "H5": "A/H5", "Bvic": "B/Victoria", "Byam": "B/Yamagata"}


def clean(value):
    value = str(value if value is not None else "").strip()
    return "" if value.upper() in MISSING else value


def number(value, maximum=None):
    text = clean(value)
    # LabWare exports can use a decimal comma. Do not interpret thousands separators.
    if text.count(",") == 1 and "." not in text:
        text = text.replace(",", ".")
    try:
        value = float(text)
    except ValueError:
        return None
    if not math.isfinite(value) or value < 0 or (maximum is not None and value > maximum):
        return None
    return value


def lookup(row, *names):
    by_name = {name.casefold(): value for name, value in row.items()}
    for name in names:
        value = by_name.get(name.casefold())
        if clean(value):
            return value
    return ""


def subtype(value):
    """Normalize explicit subtype labels; arbitrary result text is not a call."""
    text = clean(value).upper().replace("INFLUENSA", "").replace("INFLUENZA", "")
    text = re.sub(r"[\s()/ _-]", "", text)
    aliases = {"VIC": "B/Victoria", "VICVIC": "B/Victoria", "BVIC": "B/Victoria",
               "BVICTORIA": "B/Victoria", "VICTORIA": "B/Victoria",
               "YAM": "B/Yamagata", "YAMYAM": "B/Yamagata", "BYAM": "B/Yamagata",
               "BYAMAGATA": "B/Yamagata", "YAMAGATA": "B/Yamagata"}
    if text in aliases:
        return aliases[text]
    match = re.fullmatch(r"A?(H\d{1,2})(N\d{1,2})?(?:PDM(?:09|2009)?)?", text)
    if match:
        return "A/" + match[1] + (match[2] or "")
    return text if text in {"A", "B"} else ""


def complete_subtype(value):
    value = subtype(value)
    return value if re.fullmatch(r"A/H\d{1,2}N\d{1,2}|B/(?:Victoria|Yamagata)", value) else ""


def mixed_sites(row, segment):
    names = [f"Nextclade Mixed Sites {protein}" for protein in SEGMENT_PROTEINS[segment]]
    names.append(f"NC_MixedSites_{'M' if segment == 'MP' else segment}")
    observed = {name: number(lookup(row, name)) for name in names if clean(lookup(row, name))}
    valid = [value for value in observed.values() if value is not None and value.is_integer()]
    # HA1/HA2 and M1/M2 are copies of the segment count in nextclade_converter.py.
    # A conflict remains visible; the maximum is a conservative review value.
    return {
        "value": int(max(valid)) if valid else None,
        "conflict": len(set(valid)) > 1,
        "invalid": any(value is None or not value.is_integer() for value in observed.values()),
        "sources": {name: clean(lookup(row, name)) for name in observed},
    }


def indels(row):
    events = []
    assessed = {segment: set() for segment in SEGMENT_PROTEINS}
    for segment, proteins in SEGMENT_PROTEINS.items():
        for kind, prefix, master_suffix in (
            ("Deletion", "aaDeletions", "Deletion"),
            ("Insertion", "aaInsertions", "Insertion"),
            ("Frameshift", "frameShifts", "Frameshift"),
        ):
            found = {}
            for protein in proteins:
                for column in (f"{prefix} {protein}", f"NC_{protein}_{master_suffix}"):
                    value = clean(lookup(row, column))
                    if not value:
                        continue
                    assessed[segment].add(kind)
                    if value.casefold() in {f"no {prefix}".casefold(), "0", "[]"}:
                        continue
                    # Repeated protein columns can contain the same whole-segment list.
                    for event in re.split(r"[;,]", value):
                        event = event.strip()
                        if event:
                            found.setdefault(event, []).append(column)
            for event, columns in found.items():
                events.append({"segment": segment, "kind": kind, "event": event, "columns": columns})
    return events, sorted(segment for segment, kinds in assessed.items() if len(kinds) == 3)


def master_index(rows, workflow):
    _, canonical = schema()
    headers = list(dict.fromkeys(name for row in rows for name in row))
    _, rows = transform((headers, rows), {}, canonical, "QC master")
    matched = []
    seen = set()
    for row in rows:
        # Reading an old master for QC remains supported; this never writes it.
        key = identifier(row.get(INDEX)) or sequence_id(row) or identifier(row.get("Key"))
        if not key:
            continue
        row[INDEX] = key
        sequence = sequence_id(row)
        if workflow == "fastq" and sequence and sequence in seen:
            raise MergeError("Master CSV has duplicate sequencing identifiers; qPCR matching is ambiguous")
        seen.add(sequence)
        matched.append(row)
    return {
        "rows": index_rows(matched, "QC master"),
        "sequences": sequence_index(matched, source="QC master"),
        "aliases": alias_index(matched, (INDEX, "Key", "OriginalName", "SampleID")),
    }


def master_match(row, index, workflow):
    key = (index["sequences"].get(row["Sample"]) if workflow == "fastq"
           else fasta_match(row, index["aliases"], index["sequences"]))
    return index["rows"].get(key)


def compare_qpcr(master_row, called, column=None):
    result = {"status": "No master match", "expected": "", "evidence": {}, "unrecognised": []}
    if master_row is None:
        return result
    expected = []
    if column:
        raw = clean(lookup(master_row, column))
        result["evidence"][column] = raw or "Unavailable"
        value = subtype(raw)
        if value:
            expected.append(value)
        elif raw:
            result["unrecognised"].append(column)
    else:
        for assay, label in ASSAYS.items():
            name = f"PCR_{assay}_Res"
            raw = clean(lookup(master_row, name))
            if not raw:
                continue
            result["evidence"][name] = raw
            if raw.casefold() in POSITIVE:
                expected.append(label)
            elif raw.casefold() not in NEGATIVE:
                result["unrecognised"].append(name)
    result["expected"] = "; ".join(expected)
    if result["unrecognised"]:
        result["status"] = "Unrecognised qPCR result"
    elif len(expected) > 1:
        result["status"] = "Multiple qPCR calls"
    elif not expected:
        result["status"] = "No positive subtype qPCR" if result["evidence"] else "qPCR unavailable"
    elif not called:
        result["status"] = "No sequence call"
    else:
        expected = expected[0]
        compatible = called == expected or (
            re.fullmatch(r"A/H\d{1,2}", expected) and called.startswith(expected + "N")
        ) or expected in {"A", "B"} and called.startswith(expected + "/")
        result["status"] = ("Type only" if expected in {"A", "B"} else "Match") if compatible else "Mismatch"
    return result
