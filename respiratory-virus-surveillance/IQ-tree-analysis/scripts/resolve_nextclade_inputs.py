#!/usr/bin/env python3

import argparse
import csv
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import Optional


ID_CANDIDATES = [
    "sample_id",
    "sequence_name",
    "strain",
    "sample",
    "name",
    "taxon",
    "id",
    "accession",
    "key",
]
TYPE_CANDIDATES = [
    "influenza_type",
    "virus_type",
    "type",
    "flu_type",
]
SEGMENT_CANDIDATES = [
    "segment",
    "gene",
    "genome_segment",
    "genomic_segment",
]
SUBTYPE_CANDIDATES = [
    "subtype",
    "lineage",
    "virus_subtype",
    "ha_subtype",
]
NA_VALUES = {"", "na", "n/a", "nan", "none", "null", "missing", "unknown", "unk"}
SEGMENT_MAP = {
    "PB2": "PB2",
    "PB1": "PB1",
    "PA": "PA",
    "HA": "HA",
    "NP": "NP",
    "NA": "NA",
    "M": "M",
    "MP": "M",
    "MATRIX": "M",
    "NS": "NS",
    "NONSTRUCTURAL": "NS",
}
SEGMENT_PATTERNS = {
    "PB2": [r"\bpb[ _-]?2\b"],
    "PB1": [r"\bpb[ _-]?1\b"],
    "PA": [r"\bpa\b", r"\bpolymerase[ _-]?acidic\b"],
    "HA": [r"\bha\b", r"\bhemagglutinin\b"],
    "NP": [r"\bnp\b", r"\bnucleoprotein\b"],
    "NA": [r"\bna\b", r"\bneuraminidase\b"],
    "M": [r"\bmp\b", r"\bmatrix\b", r"\bsegment[ _-]?7\b", r"\bm_segment\b"],
    "NS": [r"\bns\b", r"\bnonstructural\b", r"\bsegment[ _-]?8\b"],
}


def fail(message: str):
    raise SystemExit(message)


def normalize_header(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value


def choose_delimiter(path: Path) -> str:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            line = raw_line.strip("\n\r")
            if line.strip():
                counts = {delim: line.count(delim) for delim in ("\t", ";", ",")}
                best = max(counts, key=counts.get)
                if counts[best] > 0:
                    return best
                break
    fail(
        "Could not detect the metadata delimiter. Expected a tab-, semicolon-, or comma-delimited file with a header row."
    )


def detect_column(headers, preferred_names, column_kind):
    normalized_headers = [normalize_header(header) for header in headers]
    exact_positions = []
    for preferred in preferred_names:
        if preferred in normalized_headers:
            exact_positions.append((preferred, normalized_headers.index(preferred)))

    if exact_positions:
        _, selected_idx = exact_positions[0]
        return headers[selected_idx]

    fuzzy_indexes = []
    if column_kind == "id":
        for idx, normalized in enumerate(normalized_headers):
            if normalized.endswith("_id") or normalized in {"identifier", "sample_identifier"}:
                fuzzy_indexes.append(idx)
    elif column_kind == "segment":
        for idx, normalized in enumerate(normalized_headers):
            if normalized.endswith("segment") or normalized.endswith("_segment") or normalized == "gene":
                fuzzy_indexes.append(idx)
    elif column_kind == "type":
        for idx, normalized in enumerate(normalized_headers):
            if normalized.endswith("_type") or normalized in {"type", "virus"}:
                fuzzy_indexes.append(idx)
    elif column_kind == "subtype":
        for idx, normalized in enumerate(normalized_headers):
            if normalized.endswith("subtype") or normalized == "lineage":
                fuzzy_indexes.append(idx)

    if len(fuzzy_indexes) == 1:
        return headers[fuzzy_indexes[0]]

    return None


def read_fasta_names(path: Path):
    names = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                header = line[1:].strip()
                if not header:
                    fail(f"Encountered an empty FASTA header at line {line_number} in {path}")
                names.append(header)
    if not names:
        fail(f"No FASTA headers found in {path}")
    return set(names)


def read_metadata_rows(path: Path, metadata_format: str):
    if metadata_format != "default":
        fail(
            f"Nextclade input validation currently supports '--metadata-format default' only, not '{metadata_format}'."
        )

    delimiter = choose_delimiter(path)
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        headers = reader.fieldnames or []
        if not headers:
            fail("Metadata file is missing a header row.")
        rows = list(reader)
    if not rows:
        fail("Metadata file contains a header row but no data rows.")
    return headers, rows


def normalize_influenza_type(value: str):
    if value is None:
        return None
    raw = value.strip()
    if raw.lower() in NA_VALUES:
        return None
    lower = raw.lower()
    compact = re.sub(r"[^a-z0-9]+", "", lower)
    if compact in {"a", "influenzaa", "typea", "flua"}:
        return "A"
    if compact in {"b", "influenzab", "typeb", "flub"}:
        return "B"
    if compact in {"c", "influenzac", "typec", "fluc"}:
        return "C"
    if compact in {"d", "influenzad", "typed", "flud"}:
        return "D"
    match = re.search(r"(?:influenza|flu)[ _-]*([abcd])\b", lower)
    if match:
        return match.group(1).upper()
    match = re.match(r"([abcd])[\s/_(-]", lower)
    if match:
        return match.group(1).upper()
    if re.search(r"\bh\d+n\d+\b", lower):
        return "A"
    if "victoria" in lower or "yamagata" in lower:
        return "B"
    return None


def normalize_segment(value: str):
    if value is None:
        return None
    raw = value.strip()
    if raw.lower() in NA_VALUES:
        return None
    upper = re.sub(r"[^A-Za-z0-9]+", "", raw).upper()
    return SEGMENT_MAP.get(upper)


def normalize_subtype_hint(value: str):
    if value is None:
        return None
    raw = value.strip()
    if raw.lower() in NA_VALUES:
        return None
    upper = raw.upper()
    match = re.search(r"H\d+N\d+", upper)
    if match:
        return match.group(0)
    if "VICTORIA" in upper:
        return "B/VICTORIA"
    if "YAMAGATA" in upper:
        return "B/YAMAGATA"
    return None


def collect_unique(rows, header, normalizer):
    if header is None:
        return set()
    values = set()
    for row in rows:
        normalized = normalizer((row.get(header, "") or "").strip())
        if normalized is not None:
            values.add(normalized)
    return values


def resolve_analysis_target(rows, headers, fasta_names, explicit_type, explicit_segment):
    id_header = detect_column(headers, ID_CANDIDATES, "id")
    if id_header is None:
        fail("Could not identify the metadata identifier column while validating Nextclade inputs.")

    matched_rows = []
    for row in rows:
        record_id = (row.get(id_header, "") or "").strip()
        if record_id and record_id in fasta_names:
            matched_rows.append(row)

    if not matched_rows:
        fail("Could not match any metadata rows to FASTA headers while validating Nextclade inputs.")

    type_header = detect_column(headers, TYPE_CANDIDATES, "type")
    segment_header = detect_column(headers, SEGMENT_CANDIDATES, "segment")
    subtype_header = detect_column(headers, SUBTYPE_CANDIDATES, "subtype")

    metadata_types = collect_unique(matched_rows, type_header, normalize_influenza_type)
    metadata_segments = collect_unique(matched_rows, segment_header, normalize_segment)
    metadata_subtypes = collect_unique(matched_rows, subtype_header, normalize_subtype_hint)

    normalized_explicit_type = normalize_influenza_type(explicit_type) if explicit_type else None
    if explicit_type and normalized_explicit_type is None:
        fail(f"Could not normalize --influenza-type value '{explicit_type}'. Use A, B, C, or D.")
    normalized_explicit_segment = normalize_segment(explicit_segment) if explicit_segment else None
    if explicit_segment and normalized_explicit_segment is None:
        fail(
            f"Could not normalize --segment value '{explicit_segment}'. Supported influenza segments are PB2, PB1, PA, HA, NP, NA, M, and NS."
        )

    if len(metadata_types) > 1:
        fail(
            "Matched metadata rows contain multiple influenza types: "
            + ", ".join(sorted(metadata_types))
            + ". Split the analysis or pass a metadata file for a single type."
        )
    if len(metadata_segments) > 1:
        fail(
            "Matched metadata rows contain multiple segments: "
            + ", ".join(sorted(metadata_segments))
            + ". Split the analysis or pass a metadata file for a single segment."
        )

    metadata_type = next(iter(metadata_types)) if metadata_types else None
    metadata_segment = next(iter(metadata_segments)) if metadata_segments else None

    if normalized_explicit_type and metadata_type and normalized_explicit_type != metadata_type:
        fail(
            f"--influenza-type resolved to {normalized_explicit_type}, but matched metadata rows resolve to {metadata_type}."
        )
    if normalized_explicit_segment and metadata_segment and normalized_explicit_segment != metadata_segment:
        fail(f"--segment resolved to {normalized_explicit_segment}, but matched metadata rows resolve to {metadata_segment}.")

    analysis_type = normalized_explicit_type or metadata_type
    analysis_segment = normalized_explicit_segment or metadata_segment

    if analysis_type is None:
        fail(
            "Could not resolve the influenza type from matched metadata rows. Provide --influenza-type explicitly for Nextclade mode."
        )
    if analysis_segment is None:
        fail(
            "Could not resolve the segment from matched metadata rows. Provide --segment explicitly for Nextclade mode."
        )

    subtype_hint = next(iter(metadata_subtypes)) if len(metadata_subtypes) == 1 else None
    return {
        "id_header": id_header,
        "matched_record_count": str(len(matched_rows)),
        "analysis_influenza_type": analysis_type,
        "analysis_segment": analysis_segment,
        "analysis_subtype_hint": subtype_hint or "",
        "metadata_type_column": type_header or "",
        "metadata_segment_column": segment_header or "",
        "metadata_subtype_column": subtype_header or "",
    }


def read_single_fasta_header(path: Path):
    header = None
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                count += 1
                if count == 1:
                    header = line[1:].strip()
                if count > 1:
                    fail(f"Reference FASTA must contain exactly one sequence: {path}")
            elif header is None:
                fail(f"Reference FASTA contains sequence data before the first header at line {line_number}: {path}")
    if header is None:
        fail(f"Reference FASTA did not contain a sequence header: {path}")
    return header


def count_gff_cds(path: Path):
    cds_count = 0
    with path.open("r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 3 and parts[2].upper() == "CDS":
                cds_count += 1
    if cds_count == 0:
        fail(f"Genome annotation does not contain any CDS features: {path}")
    return cds_count


def build_descriptor_text(parts):
    return " ".join(part for part in parts if part)


def infer_hints_from_text(text: str):
    lower = text.lower()
    type_hits = set()
    if re.search(r"(?:influenza|flu)[ _-]*a\b", lower) or re.search(r"\bh\d+n\d+\b", lower) or re.search(r"\ba[/_-]?h\d+n\d+\b", lower):
        type_hits.add("A")
    if re.search(r"(?:influenza|flu)[ _-]*b\b", lower) or "victoria" in lower or "yamagata" in lower:
        type_hits.add("B")
    if re.search(r"(?:influenza|flu)[ _-]*c\b", lower):
        type_hits.add("C")
    if re.search(r"(?:influenza|flu)[ _-]*d\b", lower):
        type_hits.add("D")

    segment_hits = set()
    for segment, patterns in SEGMENT_PATTERNS.items():
        if any(re.search(pattern, lower) for pattern in patterns):
            segment_hits.add(segment)

    subtype_hint = None
    match = re.search(r"\bh\d+n\d+\b", lower)
    if match:
        subtype_hint = match.group(0).upper()
    elif "victoria" in lower:
        subtype_hint = "B/VICTORIA"
    elif "yamagata" in lower:
        subtype_hint = "B/YAMAGATA"

    return {
        "dataset_influenza_type": next(iter(type_hits)) if len(type_hits) == 1 else "",
        "dataset_segment": next(iter(segment_hits)) if len(segment_hits) == 1 else "",
        "dataset_subtype_hint": subtype_hint or "",
    }


def choose_zip_member(names, target_name):
    matches = [name for name in names if PurePosixPath(name).name == target_name]
    if not matches:
        return None
    matches.sort(key=lambda item: (len(PurePosixPath(item).parts), item))
    return matches[0]


def read_local_dataset(dataset_path: Path):
    descriptor = {
        "nextclade_input_mode": "local-dataset",
        "dataset_label": str(dataset_path),
        "dataset_tag": "",
    }

    if dataset_path.is_dir():
        pathogen_path = dataset_path / "pathogen.json"
        if not pathogen_path.is_file():
            fail(f"Nextclade dataset directory is missing pathogen.json: {dataset_path}")
        with pathogen_path.open("r", encoding="utf-8") as handle:
            pathogen = json.load(handle)
        ref_name = pathogen.get("files", {}).get("reference", "reference.fasta")
        ref_path = dataset_path / ref_name
        if not ref_path.is_file():
            fallback = dataset_path / "reference.fasta"
            ref_path = fallback if fallback.is_file() else ref_path
        ref_header = read_single_fasta_header(ref_path) if ref_path.is_file() else ""
        text = build_descriptor_text(
            [
                dataset_path.name,
                ref_name,
                ref_header,
                *(str(value) for value in (pathogen.get("attributes") or {}).values()),
                str(pathogen.get("name", "") or ""),
                str(pathogen.get("tag", "") or ""),
                str(pathogen.get("version", "") or ""),
            ]
        )
        descriptor["dataset_tag"] = str(pathogen.get("tag", "") or pathogen.get("version", "") or "")
    elif dataset_path.is_file() and dataset_path.suffix.lower() == ".zip":
        with zipfile.ZipFile(dataset_path) as zf:
            names = zf.namelist()
            pathogen_member = choose_zip_member(names, "pathogen.json")
            if pathogen_member is None:
                fail(f"Nextclade dataset zip is missing pathogen.json: {dataset_path}")
            pathogen = json.loads(zf.read(pathogen_member).decode("utf-8"))
            ref_name = pathogen.get("files", {}).get("reference", "reference.fasta")
            pathogen_parent = PurePosixPath(pathogen_member).parent
            ref_member = str(pathogen_parent / ref_name)
            if ref_member not in names:
                fallback = choose_zip_member(names, PurePosixPath(ref_name).name)
                ref_member = fallback or ref_member
            ref_header = ""
            if ref_member in names:
                with zf.open(ref_member) as handle:
                    text_bytes = handle.read().decode("utf-8")
                temp_lines = [line.strip() for line in text_bytes.splitlines() if line.strip()]
                headers = [line[1:].strip() for line in temp_lines if line.startswith(">")]
                if len(headers) != 1:
                    fail(f"Reference FASTA inside dataset zip must contain exactly one sequence: {dataset_path}")
                ref_header = headers[0]
            text = build_descriptor_text(
                [
                    dataset_path.name,
                    ref_name,
                    ref_header,
                    *(str(value) for value in (pathogen.get("attributes") or {}).values()),
                    str(pathogen.get("name", "") or ""),
                    str(pathogen.get("tag", "") or ""),
                    str(pathogen.get("version", "") or ""),
                ]
            )
            descriptor["dataset_tag"] = str(pathogen.get("tag", "") or pathogen.get("version", "") or "")
    else:
        fail(
            f"Local Nextclade dataset path must be a directory or a .zip archive, not: {dataset_path}"
        )

    descriptor.update(infer_hints_from_text(text))
    return descriptor


def read_custom_reference(reference_path: Path, annotation_path: Path, pathogen_json_path: Optional[Path]):
    ref_header = read_single_fasta_header(reference_path)
    cds_count = count_gff_cds(annotation_path)
    text_parts = [reference_path.name, annotation_path.name, ref_header]
    if pathogen_json_path is not None and pathogen_json_path.is_file():
        with pathogen_json_path.open("r", encoding="utf-8") as handle:
            pathogen = json.load(handle)
        text_parts.extend(str(value) for value in (pathogen.get("attributes") or {}).values())
        text_parts.append(str(pathogen.get("name", "") or ""))

    descriptor = {
        "nextclade_input_mode": "custom-reference",
        "dataset_label": str(reference_path),
        "dataset_tag": "",
        "custom_reference_cds_count": str(cds_count),
    }
    descriptor.update(infer_hints_from_text(build_descriptor_text(text_parts)))
    return descriptor


def read_dataset_name(dataset_name: str, dataset_tag: Optional[str]):
    descriptor = {
        "nextclade_input_mode": "dataset-name",
        "dataset_label": dataset_name,
        "dataset_tag": dataset_tag or "",
    }
    descriptor.update(infer_hints_from_text(build_descriptor_text([dataset_name, dataset_tag or ""])))
    return descriptor


def validate_descriptor(descriptor, analysis_type, analysis_segment, analysis_subtype_hint):
    descriptor_type = descriptor.get("dataset_influenza_type", "")
    descriptor_segment = descriptor.get("dataset_segment", "")
    descriptor_subtype = descriptor.get("dataset_subtype_hint", "")
    mode = descriptor["nextclade_input_mode"]
    label = descriptor["dataset_label"]

    if mode in {"local-dataset", "dataset-name"}:
        if not descriptor_type:
            fail(
                f"Could not validate the influenza type for Nextclade {mode} '{label}'. Use a dataset whose name or pathogen attributes identify the type, or use custom reference mode with explicit --influenza-type and --segment."
            )
        if not descriptor_segment:
            fail(
                f"Could not validate the segment for Nextclade {mode} '{label}'. Use a dataset whose name or pathogen attributes identify the segment, or use custom reference mode with explicit --influenza-type and --segment."
            )

    if descriptor_type and descriptor_type != analysis_type:
        fail(
            f"Nextclade input '{label}' resolves to influenza type {descriptor_type}, but the matched analysis target resolves to {analysis_type}."
        )
    if descriptor_segment and descriptor_segment != analysis_segment:
        fail(
            f"Nextclade input '{label}' resolves to segment {descriptor_segment}, but the matched analysis target resolves to {analysis_segment}."
        )
    if analysis_subtype_hint and descriptor_subtype and descriptor_subtype != analysis_subtype_hint:
        fail(
            f"Nextclade input '{label}' resolves to subtype hint {descriptor_subtype}, but the matched analysis target resolves to {analysis_subtype_hint}."
        )


def main():
    parser = argparse.ArgumentParser(description="Resolve and validate Nextclade dataset/reference inputs for influenza analyses.")
    parser.add_argument("--fasta", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--metadata-format", default="default")
    parser.add_argument("--nextclade-dataset")
    parser.add_argument("--nextclade-dataset-tag")
    parser.add_argument("--nextclade-reference")
    parser.add_argument("--nextclade-annotation")
    parser.add_argument("--nextclade-pathogen-json")
    parser.add_argument("--influenza-type")
    parser.add_argument("--segment")
    parser.add_argument("--report")
    args = parser.parse_args()

    fasta_path = Path(args.fasta)
    metadata_path = Path(args.metadata)
    if not fasta_path.is_file():
        fail(f"FASTA file not found: {fasta_path}")
    if not metadata_path.is_file():
        fail(f"Metadata file not found: {metadata_path}")

    dataset = args.nextclade_dataset or ""
    reference = args.nextclade_reference or ""
    annotation = args.nextclade_annotation or ""
    pathogen_json = args.nextclade_pathogen_json or ""

    if dataset:
        if reference or annotation:
            fail("Use either --nextclade-dataset or --nextclade-reference/--nextclade-annotation, not both.")
        if pathogen_json:
            fail("--nextclade-pathogen-json is only supported with --nextclade-reference/--nextclade-annotation.")
    else:
        if reference or annotation:
            if not (reference and annotation):
                fail("--nextclade-reference and --nextclade-annotation must be provided together.")
        else:
            fail(
                "Nextclade mode requires either --nextclade-dataset or both --nextclade-reference and --nextclade-annotation."
            )

    fasta_names = read_fasta_names(fasta_path)
    headers, metadata_rows = read_metadata_rows(metadata_path, args.metadata_format)
    resolved = resolve_analysis_target(
        metadata_rows,
        headers,
        fasta_names,
        args.influenza_type,
        args.segment,
    )

    if dataset:
        dataset_path = Path(dataset)
        if dataset_path.exists():
            if args.nextclade_dataset_tag:
                fail("--nextclade-dataset-tag is only valid when --nextclade-dataset is a dataset name, not a local dataset path.")
            descriptor = read_local_dataset(dataset_path)
        else:
            descriptor = read_dataset_name(dataset, args.nextclade_dataset_tag)
    else:
        reference_path = Path(reference)
        annotation_path = Path(annotation)
        pathogen_json_path = Path(pathogen_json) if pathogen_json else None
        if not reference_path.is_file():
            fail(f"Nextclade reference FASTA not found: {reference_path}")
        if not annotation_path.is_file():
            fail(f"Nextclade genome annotation not found: {annotation_path}")
        if pathogen_json_path is not None and not pathogen_json_path.is_file():
            fail(f"Nextclade pathogen JSON not found: {pathogen_json_path}")
        descriptor = read_custom_reference(reference_path, annotation_path, pathogen_json_path)

    validate_descriptor(
        descriptor,
        resolved["analysis_influenza_type"],
        resolved["analysis_segment"],
        resolved["analysis_subtype_hint"],
    )

    result = {
        **resolved,
        **descriptor,
        "validation_status": "ok",
    }
    lines = [f"{key}\t{value}" for key, value in result.items() if value != ""]
    output = "\n".join(lines)
    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(output + "\n", encoding="utf-8")
    print(output)


if __name__ == "__main__":
    main()
