#!/usr/bin/env python3
"""Render human run QC and master-CSV qPCR comparisons as a standalone HTML report.

Extended from nf-core-fluseq's report_qc_html.py; Python standard library only.
"""

import argparse
import csv
import hashlib
import html
import json
import re
from collections import Counter
from pathlib import Path
from statistics import median

from merge_master_csv import read_table
from qc_metrics import clean, number, lookup, complete_subtype, mixed_sites, indels, master_index, master_match, compare_qpcr

VERSION = "2.0.0"
SEGMENTS = ("HA", "NA", "MP", "NP", "NS", "PA", "PB1", "PB2")
PROTEINS = ("HA1", "HA2", "NA", "M1", "M2", "NP", "NS", "PA", "PB1", "PB2")
SUBTYPES = {
    "H3N2": "A/H3N2",
    "H1N1": "A/H1N1",
    "VIC": "B/Victoria",
    "VICVIC": "B/Victoria",
    "YAM": "B/Yamagata",
    "YAMYAM": "B/Yamagata",
}


def coverage(row, segment):
    aliases = ("Coverage-MP", "Coverage-M") if segment == "MP" else (f"Coverage-{segment}",)
    for column in aliases + (f"NGS_Coverage_{'M' if segment == 'MP' else segment}",):
        if clean(row.get(column)):
            return number(row[column], 100)
    return None


def counts(values):
    return dict(sorted(Counter(values).items(), key=lambda item: (-item[1], item[0])))


def read_csv(path, workflow="fastq"):
    raw = path.read_bytes()
    fields, rows = read_table(path)
    identity = "OriginalName" if workflow == "fasta" else "Sample"
    if identity not in fields:
        raise ValueError(f"The input CSV must contain a {identity} column.")
    identifiers = set()
    for row in rows:
        sample = clean(row[identity])
        if not sample:
            raise ValueError(f"Missing {identity} in report.")
        if sample in identifiers:
            raise ValueError(f"Duplicate {identity} in report; one row per sample is required.")
        identifiers.add(sample)
        row["Sample"] = sample
    return fields, rows, hashlib.sha256(raw).hexdigest()


def summarise_sample(row, fields, master_row=None, coverage_threshold=80, mixed_threshold=4, noise_threshold=0.09,
                     qpcr_column=None):
    cov = {seg: coverage(row, seg) for seg in SEGMENTS}
    raw_qc = clean(row.get("NGS_QC_Sum"))
    # Only an explicitly empty summary is a known no-flag result. NA is unavailable.
    qc_available = "NGS_QC_Sum" in fields and (not row["NGS_QC_Sum"].strip() or bool(raw_qc))
    reported_qc = "Review" if raw_qc else ("No flags" if qc_available else "Unavailable")
    reasons = []
    if raw_qc:
        reasons.append(f"Reported QC: {raw_qc}")
    if not qc_available:
        reasons.append("NGS QC summary unavailable")
    low = [seg for seg, value in cov.items() if value is not None and value < coverage_threshold]
    missing = [seg for seg, value in cov.items() if value is None]
    if low:
        reasons.append(f"Coverage below {coverage_threshold:g}%: " + ", ".join(low))
    if missing:
        reasons.append("Coverage missing or invalid: " + ", ".join(missing))
    nextclade = {protein: clean(row.get(f"Nextclade QC {protein}")) for protein in PROTEINS}
    concerning = [f"{protein}: {value}" for protein, value in nextclade.items() if value and value.lower() != "good"]
    absent = [protein for protein, value in nextclade.items() if not value]
    if concerning:
        reasons.append("Nextclade QC: " + "; ".join(concerning))
    if absent:
        reasons.append("Nextclade QC unavailable: " + ", ".join(absent))
    gisaid = clean(row.get("GISAID_Comment"))
    if gisaid and gisaid.lower() != "no flags":
        reasons.append("Reported GISAID comment: " + gisaid)
    subtype_raw = clean(row.get("Subtype"))
    subtype = SUBTYPES.get(subtype_raw, subtype_raw) or "Unavailable"
    final_columns = ("Sekvens_Resultat", "NGS_Sekvens_Resultat")
    has_final = any(column in fields for column in final_columns)
    sequence_result = clean(lookup(row, *final_columns))
    called = complete_subtype(sequence_result)
    if not has_final and all(cov[seg] is not None and cov[seg] >= 30 for seg in ("HA", "NA")):
        called = complete_subtype(subtype_raw)
    if not called:
        reasons.append("No final subtype call")
    qpcr = compare_qpcr(master_row, called, qpcr_column)
    if qpcr["status"] in {"Mismatch", "Multiple qPCR calls", "Unrecognised qPCR result"}:
        reasons.append("qPCR comparison: " + qpcr["status"])
    mixed = {seg: mixed_sites(row, seg) for seg in SEGMENTS}
    high_mixed = [seg for seg, data in mixed.items() if data["value"] is not None and data["value"] > mixed_threshold]
    inconsistent_mixed = [seg for seg, data in mixed.items() if data["conflict"] or data["invalid"]]
    if high_mixed:
        reasons.append(f"Mixed sites >{mixed_threshold}: " + ", ".join(f"{seg} ({mixed[seg]['value']})" for seg in high_mixed))
    if inconsistent_mixed:
        reasons.append("Conflicting or invalid mixed-site fields: " + ", ".join(inconsistent_mixed))
    events, indel_assessed = indels(row)
    if events:
        reasons.append("Reported indels / frameshifts: " + ", ".join(sorted({event["segment"] for event in events})))
    noise = number(lookup(row, "IRMA_noise", "NGS_IRMA_noise"))
    if noise is not None and noise > noise_threshold:
        reasons.append(f"IRMA noise >{noise_threshold:g}: {noise:g}")
    subclade = clean(row.get("Subclade_Nomenclature_Subclade")) or clean(row.get("subclade"))
    fraction = number(row.get("Subclade_Nomenclature_Subclade_Match_Fraction"), 1)
    char_fraction = number(row.get("Characterisation_Subclade_Match_Fraction"), 1)
    char_status = clean(row.get("Characterisation_Status"))
    provisional = bool(
        (fraction is not None and fraction < 1)
        or (char_fraction is not None and char_fraction < 1)
        or clean(row.get("Subclade_Nomenclature_Closest_Subclade_Missing_Mutations"))
        or clean(row.get("Characterisation_Missing_Subclade_Mutations"))
        or "review" in char_status.lower()
        or clean(row.get("Characterisation_Result")).lower().startswith("provisional:")
    )
    if provisional:
        reasons.append("Provisional or incomplete characterisation evidence")
    if subclade:
        call_status = "Provisional" if provisional else ("Exact rule match" if fraction == 1 else "Match not assessed")
    else:
        call_status = "Unavailable"
    conclusion = clean(row.get("Conclusion"))
    resistance = {
        key[len("DR_Res_"):]: clean(value) or "Unavailable"
        for key, value in row.items()
        if key.startswith("DR_Res_")
    }
    flags = {
        "mismatch": qpcr["status"] == "Mismatch", "mixed": bool(high_mixed),
        "coverage": bool(low), "missing": bool(missing), "indels": bool(events),
        "noise": noise is not None and noise > noise_threshold, "failed": not bool(called),
        "other": bool(raw_qc or concerning or (gisaid and gisaid.lower() != "no flags") or provisional
                      or inconsistent_mixed or qpcr["status"] in {"Multiple qPCR calls", "Unrecognised qPCR result"}),
    }
    status = "Review" if reasons else "No flags"
    if not qc_available and not called and all(value is None for value in cov.values()):
        status = "Unavailable"
    return {
        "sample": clean(row["Sample"]),
        "barcode": clean(row.get("Barcode")),
        "sequence_id": clean(row.get("SequenceID")),
        "plate_position": clean(row.get("PCR-PlatePosition")),
        "qc_status": status,
        "reported_qc_status": reported_qc,
        "reported_qc": raw_qc,
        "review_reasons": reasons,
        "coverage": cov,
        "segment_reads": {seg: number(row.get(f"DEPTH_{seg}")) for seg in SEGMENTS},
        "nextclade_qc": nextclade,
        "missing_nextclade_qc": absent,
        "subtype": subtype,
        "raw_subtype": subtype_raw,
        "sequence_result": sequence_result,
        "called_subtype": called,
        "outcome": "Called" if called else "No call",
        "qpcr": qpcr,
        "master_key": clean(lookup(master_row or {}, "Prove_LW_ID")),
        "mixed_sites": mixed,
        "high_mixed_segments": high_mixed,
        "low_coverage_segments": low,
        "missing_coverage_segments": missing,
        "indels": events,
        "indel_assessed_segments": indel_assessed,
        "noise": noise,
        "flags": flags,
        "subclade": subclade,
        "subclade_status": call_status,
        "subclade_match_fraction": fraction,
        "characterisation_status": char_status,
        "reference_virus": clean(row.get("Characterisation_Reference_Virus")),
        "characterisation_provisional": provisional,
        "reassortment_conclusion": conclusion,
        "resistance_codes": resistance,
        "irma": {key[len("IRMA_"):]: number(value) for key, value in row.items() if key.startswith("IRMA_")},
    }


def build_report(path, master_rows=None, workflow="fastq", coverage_threshold=80, mixed_threshold=4,
                 noise_threshold=0.09, qpcr_column=None, master_source=None):
    if number(str(coverage_threshold), 100) is None or coverage_threshold <= 0:
        raise ValueError("Coverage threshold must be greater than 0 and at most 100")
    if number(str(mixed_threshold)) is None or int(mixed_threshold) != mixed_threshold:
        raise ValueError("Mixed-site threshold must be a non-negative integer")
    if number(str(noise_threshold)) is None:
        raise ValueError("Noise threshold must be finite and non-negative")
    fields, rows, digest = read_csv(path, workflow)
    index = master_index(master_rows or [], workflow)
    samples = [summarise_sample(row, fields, master_match(row, index, workflow), coverage_threshold, mixed_threshold,
                                noise_threshold, qpcr_column) for row in rows]
    metadata = {
        column: sorted({clean(row.get(column)) for row in rows if clean(row.get(column))})
        for column in ("RunID", "Instrument ID", "Date", "Release Version")
    }
    warnings = []
    if master_rows is None:
        warnings.append("Master CSV was not supplied; qPCR comparison is unavailable.")
    else:
        unmatched = sum(s["qpcr"]["status"] == "No master match" for s in samples)
        if unmatched:
            warnings.append(f"{unmatched}/{len(samples)} samples have no exact master-CSV identifier match.")
    if not any(column in fields for column in ("Sekvens_Resultat", "NGS_Sekvens_Resultat")):
        warnings.append("Final sequence-result column is absent. Calls use recognised Subtype with HA and NA coverage ≥30%.")
    for label, count in (
        ("IRMA noise", sum(s["noise"] is None for s in samples)),
        ("mixed-site counts for at least one segment", sum(any(v["value"] is None for v in s["mixed_sites"].values()) for s in samples)),
        ("indel measurements for at least one segment", sum(len(s["indel_assessed_segments"]) < len(SEGMENTS) for s in samples)),
    ):
        if count:
            warnings.append(f"{count}/{len(samples)} samples lack {label}; missing values are not a negative finding.")
    for column, values in metadata.items():
        if len(values) > 1:
            warnings.append(f"Multiple values in {column}: " + "; ".join(values))
        missing = sum(not clean(row.get(column)) for row in rows)
        if missing:
            warnings.append(f"{column} unavailable for {missing}/{len(rows)} samples.")
    if "NGS_QC_Sum" not in fields:
        warnings.append("NGS_QC_Sum column is absent; reported QC is unavailable.")
    if not samples:
        warnings.append("The CSV contains no sample records.")

    segment_summary = {}
    for seg in SEGMENTS:
        values = [s["coverage"][seg] for s in samples if s["coverage"][seg] is not None]
        reads = [s["segment_reads"][seg] for s in samples if s["segment_reads"][seg] is not None]
        segment_summary[seg] = {
            "passed": sum(value >= coverage_threshold for value in values),
            "low_coverage": sum(value < coverage_threshold for value in values),
            "missing_or_invalid": len(samples) - len(values),
            "median_coverage": median(values) if values else None,
            "median_segment_reads": median(reads) if reads else None,
            "segment_reads_available": len(reads),
        }
    reported = counts(s["reported_qc_status"] for s in samples)
    assessed = counts(s["qc_status"] for s in samples)
    status = (
        "Review required" if warnings or any(s["qc_status"] != "No flags" for s in samples) else "No QC flags detected"
    )
    if not samples:
        status = "Not assessable"
    subtype_counts = counts(s["subtype"] for s in samples)
    provisional = sum(s["characterisation_provisional"] for s in samples)
    text = [
        f"{len(samples)} samples are represented in the CSV: {reported.get('No flags', 0)} have no reported NGS QC flags, "
        f"{reported.get('Review', 0)} have reported flags, and {reported.get('Unavailable', 0)} have unavailable NGS QC summaries.",
        "Raw subtypes before final result gating: "
        + (", ".join(f"{key} ({value})" for key, value in subtype_counts.items()) or "none")
        + ".",
        f"{provisional} samples have provisional or incomplete characterisation evidence. "
        f"{sum(bool(s['missing_nextclade_qc']) for s in samples)} samples lack at least one expected Nextclade QC value.",
    ]
    return {
        "schema_version": "2.0",
        "generator_version": VERSION,
        "source": {"filename": path.name, "sha256": digest},
        "master_source": master_source,
        "workflow": workflow,
        "metadata": metadata,
        "assessment": status,
        "warnings": warnings,
        "summary_text": text,
        "rules": {
            "coverage_threshold_percent": coverage_threshold,
            "mixed_sites_threshold": mixed_threshold,
            "noise_threshold": noise_threshold,
            "qpcr_positive": "Explicit subtype labels" if qpcr_column else "Påvist (case-insensitive, whitespace trimmed)",
            "qpcr_source": qpcr_column or "PCR_H1_Res, PCR_H3_Res, PCR_H5_Res, PCR_Bvic_Res, PCR_Byam_Res",
            "denominator": "All sample rows in the final run report, including no-call rows; no controls excluded",
            "subtype_success": "Recognised final Sekvens_Resultat; raw Subtype alone cannot override an empty final result",
            "reported_qc": "NGS_QC_Sum from the source CSV; no mutation calls are recalculated",
            "review": "Reported flags, unavailable NGS summary, low/missing/invalid coverage, "
            "non-good/missing Nextclade QC, qPCR mismatch/ambiguous result, no final subtype call, "
            "high mixed sites/noise, indels/frameshifts, provisional characterisation or reported GISAID comments",
            "run_acceptance": "Control outcomes, expected sample count and laboratory acceptance rules are not supplied",
        },
        "counts": {
            "samples": len(samples),
            "called": sum(bool(s["called_subtype"]) for s in samples),
            "failed": sum(not s["called_subtype"] for s in samples),
            "flags": {flag: sum(s["flags"][flag] for s in samples) for flag in (
                "mismatch", "mixed", "coverage", "missing", "indels", "noise", "failed", "other")},
            "qpcr": counts(s["qpcr"]["status"] for s in samples),
            "reported_qc": reported,
            "assessment": assessed,
            "subtypes": subtype_counts,
            "provisional_characterisation": provisional,
            "characterisation_status": counts(s["characterisation_status"] or "Unavailable" for s in samples),
            "subclades": counts(
                f"{s['subtype']} · {s['subclade'] or 'Unavailable'} · {s['subclade_status']}" for s in samples
            ),
        },
        "segments": segment_summary,
        "samples": samples,
    }


def esc(value):
    return html.escape(str(value), quote=True)


def fmt(value, suffix="", precision=2):
    return "—" if value is None else f"{value:,.{precision}f}".rstrip("0").rstrip(".") + suffix


def badge(value):
    color = {"No flags": "good", "Called": "good", "Match": "good", "Mismatch": "bad",
             "No call": "bad", "Review": "review", "Unavailable": "missing"}.get(value, "missing")
    return f'<span class="badge {color}">{esc(value)}</span>'


def distribution(items):
    total = sum(items.values()) or 1
    return (
        "".join(
            f'<div class="distribution"><span>{esc(key)}</span><b>{value}</b>'
            f'<progress value="{value}" max="{total}">{value}/{total}</progress></div>'
            for key, value in items.items()
        )
        or "<p>No records.</p>"
    )


def render(report, template):
    samples = report["samples"]
    total = len(samples)
    rules = report["rules"]
    threshold = rules["coverage_threshold_percent"]
    mixed_threshold = rules["mixed_sites_threshold"]
    noise_threshold = rules["noise_threshold"]
    def ratio(count):
        return f"{count}/{total} ({count / total:.1%})" if total else "0/0 (not assessable)"
    run = ", ".join(report["metadata"]["RunID"]) or Path(report["source"]["filename"]).stem
    rows = []
    event_rows = []
    for sample in samples:
        cells = []
        for seg in SEGMENTS:
            value = sample["coverage"][seg]
            level = "missing" if value is None else ("good" if value >= threshold else "review")
            mixed = sample["mixed_sites"][seg]["value"]
            mixed_level = "missing" if mixed is None else ("review" if mixed > mixed_threshold else "good")
            title = (
                f"{seg}: coverage {fmt(value, '%')}; mixed sites {fmt(mixed)}; IRMA reads {fmt(sample['segment_reads'][seg])}"
            )
            cells.append(
                f'<td class="metric {level}" title="{esc(title)}" data-coverage="{esc(fmt(value, "%"))}" '
                f'data-level="{level}" data-mixed-level="{mixed_level}" data-mixed="{esc(fmt(mixed))}" '
                f'data-reads="{esc(fmt(sample["segment_reads"][seg]))}">{esc(fmt(value, "%"))}</td>'
            )
        reasons = "".join(f"<li>{esc(reason)}</li>" for reason in sample["review_reasons"])
        info = {
            "Reported NGS QC": sample["reported_qc"] or sample["reported_qc_status"],
            "Sequence result": sample["sequence_result"] or "Unavailable",
            "Raw subtype (before result gating)": sample["raw_subtype"] or "Unavailable",
            "Master index (Prove_LW_ID)": sample["master_key"] or "No master match",
            "qPCR evidence": "; ".join(f"{key}: {value}" for key, value in sample["qpcr"]["evidence"].items()) or "Unavailable",
            "Mixed-site source counts": "; ".join(
                f"{column}: {value}" for data in sample["mixed_sites"].values() for column, value in data["sources"].items()
            ) or "Unavailable",
            "Indels / frameshifts": "; ".join(f"{e['segment']} {e['kind']}: {e['event']}" for e in sample["indels"]) or (
                "No reported events; assessed segments: " + (", ".join(sample["indel_assessed_segments"]) or "none")),
            "Nextclade QC": "; ".join(f"{key}: {value or 'Unavailable'}" for key, value in sample["nextclade_qc"].items()),
            "Barcode / plate": " / ".join(filter(None, [sample["barcode"], sample["plate_position"]])) or "Unavailable",
            "Sequence ID": sample["sequence_id"] or "Unavailable",
            "Characterisation": sample["characterisation_status"] or "Unavailable",
            "Reference-virus category": sample["reference_virus"] or "Unavailable",
            "Subclade evidence": sample["subclade_status"],
            "Subclade": sample["subclade"] or "Unavailable",
            "Reassortment screen (reported)": sample["reassortment_conclusion"] or "Unavailable",
            "Drug lookup codes (reported)": "; ".join(
                f"{key}: {value}" for key, value in sample["resistance_codes"].items()
            )
            or "Unavailable",
            "IRMA read flow": "; ".join(f"{key}: {fmt(value, precision=5)}" for key, value in sample["irma"].items())
            or "Unavailable",
        }
        detail = "".join(f"<dt>{esc(key)}</dt><dd>{esc(value)}</dd>" for key, value in info.items())
        flag_segments = {
            "mixed": sample["high_mixed_segments"], "coverage": sample["low_coverage_segments"],
            "missing": sample["missing_coverage_segments"], "indels": sorted({e["segment"] for e in sample["indels"]}),
        }
        affected = sorted(set(segment for segments in flag_segments.values() for segment in segments))
        attributes = " ".join(f'data-{key}="{esc(" ".join(segments))}"' for key, segments in flag_segments.items())
        flags = " ".join(key for key, present in sample["flags"].items() if present)
        mixed_label = ", ".join(f"{seg}: {sample['mixed_sites'][seg]['value']}" for seg in sample["high_mixed_segments"])
        priority = sum(weight for key, weight in (("mismatch", 100), ("failed", 50), ("indels", 20), ("mixed", 10), ("noise", 5)) if sample["flags"][key])
        priority += int(sample["qc_status"] != "No flags")
        export = [sample["sample"], sample["outcome"], sample["called_subtype"], sample["qpcr"]["expected"],
                  sample["qpcr"]["status"], mixed_label, sample["noise"], *sample["coverage"].values(),
                  " | ".join(sample["review_reasons"])]
        rows.append(
            f'<tr data-qc="{esc(sample["qc_status"])}" data-subtype="{esc(sample["subtype"])}" '
            f'data-qpcr="{esc(sample["qpcr"]["status"])}" data-flags="{flags}" data-segments="{" ".join(affected)}" '
            f'data-sample="{esc(sample["sample"])}" data-priority="{priority}" data-noise="{sample["noise"] if sample["noise"] is not None else -1}" '
            f'data-export="{esc(json.dumps(export, ensure_ascii=False))}" {attributes}>'
            f'<th scope="row">{esc(sample["sample"])}<small>{esc(sample["barcode"] or sample["plate_position"])}</small></th>'
            f'<td>{badge(sample["outcome"])}<small>{esc(sample["called_subtype"] or "No final subtype")}</small></td>'
            f'<td>{esc(sample["qpcr"]["expected"] or "—")}<small>{badge(sample["qpcr"]["status"])}</small></td>'
            f'<td>{badge(sample["qc_status"])}<small>{esc(mixed_label and "Mixed " + mixed_label)}</small></td>{"".join(cells)}'
            f'<td class="{"review" if sample["flags"]["noise"] else ""}">{fmt(sample["noise"], precision=5)}</td>'
            f'<td><details><summary>Details</summary><div class="sample-details">'
            f'<strong>{esc(sample["sample"])}</strong><ul>{reasons}</ul><dl>{detail}</dl></div></details></td></tr>'
        )
        for event in sample["indels"]:
            event_export = [sample["sample"], event["segment"], event["kind"], event["event"], "; ".join(event["columns"])]
            event_rows.append(
                f'<tr data-segment="{event["segment"]}" data-kind="{event["kind"]}" data-export="{esc(json.dumps(event_export))}">'
                + "".join(f"<td>{esc(value)}</td>" for value in event_export) + "</tr>"
            )
    segment_rows = "".join(
        f'<tr><th scope="row">{seg}</th><td><div class="stack" aria-label="Coverage outcomes for {seg}">'
        + "".join(f'<span class="{level}" style="width:{(values[key] / total * 100) if total else 0:.3f}%" title="{esc(label)}: {ratio(values[key])}"></span>'
                  for key, level, label in (("passed", "good", "Pass"), ("low_coverage", "review", "Low coverage"), ("missing_or_invalid", "missing", "Missing")))
        + f'</div></td><td>{ratio(values["passed"])}</td><td>{ratio(values["low_coverage"])}</td>'
        f'<td>{ratio(values["missing_or_invalid"])}</td><td>{fmt(values["median_coverage"], "%")}</td>'
        f'<td>{fmt(values["median_segment_reads"])}</td><td>{values["segment_reads_available"]}/{len(samples)}</td></tr>'
        for seg, values in report["segments"].items()
    )
    reported = report["counts"]["reported_qc"]
    finding_labels = {"mismatch": "qPCR mismatch", "mixed": f"Mixed sites >{mixed_threshold}",
                      "coverage": f"Coverage <{threshold:g}%", "missing": "Missing coverage",
                      "indels": "Indels / frameshifts", "noise": f"IRMA noise >{noise_threshold:g}",
                      "failed": "No subtype call", "other": "Other reported QC"}
    replacements = {
        "TITLE": esc(run),
        "ASSESSMENT": esc(report["assessment"]),
        "RUN_META": esc(
            " · ".join(
                " / ".join(report["metadata"][key]) or f"{key} unavailable"
                for key in ("Instrument ID", "Date", "Release Version")
            )
        ),
        "TOTAL": str(len(samples)),
        "CALLED": ratio(report["counts"]["called"]),
        "FAILED": ratio(report["counts"]["failed"]),
        "REVIEW": str(sum(s["qc_status"] != "No flags" for s in samples)),
        "WORKFLOW": esc(report["workflow"].upper()),
        "COVERAGE_THRESHOLD": f"{threshold:g}",
        "MIXED_THRESHOLD": str(mixed_threshold),
        "NOISE_THRESHOLD": f"{noise_threshold:g}",
        "TRIAGE": "".join(f'<button type="button" class="triage" data-finding="{key}"><strong>{report["counts"]["flags"][key]}</strong>{esc(label)}</button>' for key, label in finding_labels.items()),
        "FINDING_OPTIONS": "".join(f'<option value="{key}">{esc(label)}</option>' for key, label in finding_labels.items()),
        "SEGMENT_OPTIONS": "".join(f'<option>{seg}</option>' for seg in SEGMENTS),
        "QPCR_OPTIONS": "".join(f'<option>{esc(key)}</option>' for key in report["counts"]["qpcr"]),
        "QPCR_COUNTS": distribution(report["counts"]["qpcr"]),
        "QPCR_SOURCE": esc(rules["qpcr_source"]),
        "QPCR_RULE": esc("Positive = " + rules["qpcr_positive"] + "."),
        "INDEL_ROWS": "".join(event_rows),
        "INDEL_COUNT": str(len(event_rows)),
        "MASTER_SOURCE": esc(report["master_source"] or "Not supplied"),
        "NO_FLAGS": str(reported.get("No flags", 0)),
        "FLAGGED": str(reported.get("Review", 0)),
        "UNAVAILABLE": str(reported.get("Unavailable", 0)),
        "SUMMARY": "".join(f"<li>{esc(line)}</li>" for line in report["summary_text"]),
        "WARNINGS": "".join(f'<p class="notice">{esc(value)}</p>' for value in report["warnings"]),
        "SUBTYPES": distribution(report["counts"]["subtypes"]),
        "CHARACTERISATION": distribution(report["counts"]["characterisation_status"]),
        "SUBCLADES": distribution(report["counts"]["subclades"]),
        "SEGMENT_ROWS": segment_rows,
        "SAMPLE_ROWS": "".join(rows),
        "SEGMENT_HEADERS": "".join(f'<th scope="col">{seg}</th>' for seg in SEGMENTS),
        "SUBTYPE_OPTIONS": "".join(
            f'<option value="{esc(key)}">{esc(key)}</option>' for key in report["counts"]["subtypes"]
        ),
        "ASSESSED_COUNTS": esc(
            ", ".join(f"{value} {key.lower()}" for key, value in report["counts"]["assessment"].items())
        ),
        "SOURCE": esc(report["source"]["filename"]),
        "SHA256": report["source"]["sha256"],
        "VERSION": VERSION,
    }
    # Substitute once, so user-supplied text resembling a placeholder stays literal.
    return re.sub(r"@@([A-Z_0-9]+)@@", lambda match: replacements[match[1]], template)


def write_report(path, output, master=None, workflow="fastq", master_label=None, **options):
    """Write a report from current-run measurements and a read-only master snapshot."""
    master_rows = read_table(master)[1] if master else None
    report = build_report(path, master_rows, workflow,
                          master_source=(master_label or Path(master).name) if master else None, **options)
    if master:
        report["master_sha256"] = hashlib.sha256(Path(master).read_bytes()).hexdigest()
    template = Path(__file__).parent / "templates" / "report_qc.html"
    page = render(report, template.read_text(encoding="utf-8"))
    summary = json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    output = Path(output)
    if output.suffix.lower() != ".html":
        raise ValueError("QC output must use an .html filename")
    inputs = {Path(path).resolve()}
    if master:
        inputs.add(Path(master).resolve())
    if output.resolve() in inputs or output.with_suffix(".json").resolve() in inputs:
        raise ValueError("QC outputs must be separate from input files")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Prepare both contents before replacing either output.
    import os
    import tempfile
    for destination, content in ((output, page), (output.with_suffix(".json"), summary)):
        fd, name = tempfile.mkstemp(prefix=".qc-", dir=destination.parent)
        temporary = Path(name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Final human FASTQ or FASTA report CSV")
    parser.add_argument("--outdir", type=Path, default=Path("."))
    parser.add_argument("--master", type=Path, help="Local or mounted master CSV; read only")
    parser.add_argument("--workflow", choices=("fastq", "fasta"), default="fastq")
    parser.add_argument("--coverage-threshold", type=float, default=80)
    parser.add_argument("--mixed-threshold", type=int, default=4)
    parser.add_argument("--noise-threshold", type=float, default=0.09)
    parser.add_argument("--qpcr-column", help="Use an explicit subtype-result column instead of the PCR assay result fields")
    parser.add_argument("--version", action="version", version=VERSION)
    args = parser.parse_args()
    try:
        output = args.outdir / f"{args.input.stem}_qc.html"
        report = write_report(args.input, output, args.master, args.workflow,
                              coverage_threshold=args.coverage_threshold, mixed_threshold=args.mixed_threshold,
                              noise_threshold=args.noise_threshold, qpcr_column=args.qpcr_column)
    except (OSError, UnicodeError, ValueError, csv.Error) as error:
        parser.exit(2, f"QC report error: {error}\n")
    print(f"Created {output} and {output.with_suffix('.json')} ({report['counts']['samples']} samples)")


if __name__ == "__main__":
    main()
