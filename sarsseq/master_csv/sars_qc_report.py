#!/usr/bin/env python3
"""Render a self-contained SARS run QC HTML report and companion JSON."""

import argparse
from collections import Counter
import csv
import hashlib
import html
import json
import os
from pathlib import Path
import re
from statistics import median
import tempfile

from sars_qc_metrics import (GENES, clean, field, master_index, master_match,
                             summarise_sample, thresholds)
from merge_master_csv import read_table

VERSION = '1.0.0'
REGIONS = ('Genome', *GENES)
DISPLAY_REGIONS = ('Genome', 'S', 'ORF1a', 'ORF1b')
FINDINGS = {'coverage': 'Low coverage', 'missing': 'Missing coverage', 'mixed': 'High mixed sites',
            'indels': 'Indels / frameshifts', 'lineage': 'No lineage assignment',
            'qpcr': 'qPCR evidence to review', 'other': 'Other QC / unavailable metrics'}


def counts(values):
    return dict(sorted(Counter(values).items(), key=lambda item: (-item[1], item[0])))


def build_report(path, master_rows=None, workflow='fastq', coverage_threshold=80, cds_threshold=80,
                 mixed_threshold=3, master_source=None):
    thresholds(coverage_threshold, cds_threshold, mixed_threshold)
    if workflow not in {'fastq', 'fasta'}:
        raise ValueError('workflow must be fastq or fasta')
    path = Path(path)
    fields, rows = read_table(path)
    identity = 'Sample' if 'Sample' in fields else 'OriginalName' if workflow == 'fasta' else 'Sample'
    if identity not in fields:
        raise ValueError('The report must contain Sample (or OriginalName for legacy FASTA reports)')
    seen = set()
    for row in rows:
        sample = clean(row[identity])
        if not sample:
            raise ValueError('Missing sample identifier in report')
        if sample in seen:
            raise ValueError('Duplicate sample identifier in report')
        seen.add(sample)
        row['Sample'] = sample
    index = master_index(master_rows or [])
    samples = [summarise_sample(row, master_match(row, index, workflow), coverage_threshold,
                               cds_threshold, mixed_threshold) for row in rows]
    metadata = {key: sorted({clean(field(row, *aliases)) for row in rows if clean(field(row, *aliases))})
                for key, aliases in {
                    'RunID': ('RunID', 'NGS_Run_ID'), 'Date': ('Date', 'NGS_Script_dato'),
                    'Instrument ID': ('Instrument ID', 'NGS_Instrument ID'), 'Primer': ('Primer', 'NGS_Primer_vers'),
                    'Release Version': ('Release Version',), 'NGS_Script_vers': ('NGS_Script_vers',),
                }.items()}
    regions = {}
    for region in REGIONS:
        values = [sample['coverage'][region] for sample in samples if sample['coverage'][region] is not None]
        threshold = coverage_threshold if region == 'Genome' else cds_threshold
        regions[region] = {'threshold': threshold, 'passed': sum(value >= threshold for value in values),
                           'low_coverage': sum(value < threshold for value in values),
                           'missing_or_invalid': len(samples) - len(values),
                           'median_coverage': median(values) if values else None}
    notes = []
    if master_rows is None:
        notes.append('No master supplied; qPCR evidence is unavailable.')
    else:
        unmatched = sum(sample['qpcr']['status'] == 'No master match' for sample in samples)
        if unmatched:
            notes.append(f'{unmatched}/{len(samples)} samples have no exact master match.')
    absent_indels = sum(not all(sample['indel_availability'].values()) for sample in samples)
    if absent_indels:
        notes.append(f'{absent_indels}/{len(samples)} samples lack some indel measurements; absence of listed events does not establish a negative result.')
    for key, values in metadata.items():
        if len(values) > 1:
            notes.append(f'Multiple values in {key}: ' + '; '.join(values))
    if not samples:
        notes.append('No sample records in this CSV.')
    review = sum(sample['qc_status'] != 'No flags' for sample in samples)
    return {
        'schema_version': 'sars-qc-1.0', 'generator_version': VERSION,
        'source': {'filename': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        'master_source': master_source, 'workflow': workflow, 'metadata': metadata,
        'assessment': 'Not assessable' if not samples else 'Review required' if review else 'No QC flags detected',
        'warnings': notes,
        'rules': {
            'coverage_threshold_percent': coverage_threshold, 'cds_threshold_percent': cds_threshold,
            'mixed_sites_threshold': mixed_threshold,
            'coverage_units': 'coverage/NC_Coverage/coverage_stats and CDS values are fractions (0–1); QC_overall_pct is percent (0–100).',
            'precedence': 'First present source wins even if missing/invalid; conflicting valid copies are flagged. Current-run measurements only.',
            'denominator': 'All rows in this final report; no controls excluded. Filters do not change run denominators.',
            'lineage': 'A reported nonmissing lineage is assigned; assignment is separate from QC and does not establish run acceptance.',
            'qpcr': 'Detection/Ct context only. No lineage concordance or positive result is inferred from Ct.',
            'review': 'Low/missing coverage, inconsistent fields, reported QC, non-good/missing Nextclade QC, high/missing mixed sites, reported indels, missing indel measurements, missing lineage, conflicting/unrecognised qPCR, or reported GISAID comments.',
            'missing': 'Missing/NA-like measurements remain unavailable. Only an explicitly blank NGS_QC_Sum is a known no-flag summary.',
            'acceptance': 'No laboratory acceptance decision; expected sample counts and control outcomes are not supplied.',
        },
        'unavailable_flu_metrics': ['Influenza segment read counts', 'IRMA noise', 'Reassortment',
                                    'Influenza subtype/qPCR concordance', 'Influenza characterisation rules'],
        'counts': {'samples': len(samples), 'lineage_assigned': sum(bool(s['lineage']) for s in samples),
                   'lineage_unavailable': sum(not s['lineage'] for s in samples), 'review': review,
                   'flags': {flag: sum(s['flags'][flag] for s in samples) for flag in FINDINGS},
                   'assessment': counts(s['qc_status'] for s in samples),
                   'lineages': counts(s['lineage'] or 'Unavailable' for s in samples),
                   'clades': counts(s['clade'] or 'Unavailable' for s in samples),
                   'qpcr': counts(s['qpcr']['status'] for s in samples)},
        'regions': regions, 'samples': samples,
    }


def esc(value):
    return html.escape(str(value), quote=True)


def fmt(value, suffix=''):
    return '—' if value is None else f'{value:.2f}'.rstrip('0').rstrip('.') + suffix


def render(report):
    total = report['counts']['samples']
    ratio = lambda value: f'{value}/{total} ({value / total:.1%})' if total else '0/0 (not assessable)'
    rows, event_rows = [], []
    for sample in report['samples']:
        cells = []
        for region in DISPLAY_REGIONS:
            value = sample['coverage'][region]
            level = 'missing' if value is None else 'review' if region in sample['low_coverage_regions'] else 'good'
            cells.append(f'<td class="metric {level}">{fmt(value, "%")}</td>')
        details = {
            'Master specimen index': sample['master_key'] or 'No master match',
            'Reported QC': sample['reported_qc'] or sample['reported_qc_status'],
            'QC note': sample['qc_note'] or 'Unavailable',
            'Lineage (long)': sample['lineage_long'] or 'Unavailable',
            'WHO label': sample['clade_who'] or 'Unavailable',
            'Barcode / plate': ' / '.join(filter(None, (sample['barcode'], sample['plate_position']))) or 'Unavailable',
            'qPCR results': '; '.join(f'{key}: {value}' for key, value in sample['qpcr']['results'].items()) or 'Unavailable',
            'qPCR Ct': '; '.join(f'{key}: {value["raw"]}' for key, value in sample['qpcr']['ct'].items()) or 'Unavailable',
            'Report consensus Ct': sample['consensus_ct']['raw'] or 'Unavailable',
            'Mixed-site sources': '; '.join(f'{key}: {value}' for key, value in sample['mixed_sites']['sources'].items()) or 'Unavailable',
            'Coverage sources': '; '.join(f'{region} / {key}: {value}' for region, metric in sample['coverage_evidence'].items() for key, value in metric['sources'].items()) or 'Unavailable',
            'Indel availability': '; '.join(f'{key}: {"available" if value else "unavailable"}' for key, value in sample['indel_availability'].items()),
            'GISAID comment': sample['gisaid_comment'] or 'Unavailable / blank',
            'Drug review codes (reported)': '; '.join(f'{key}: {value or "Unavailable"}' for key, value in sample['reported_dr_codes'].items()) or 'Unavailable',
        }
        flags = ' '.join(key for key, present in sample['flags'].items() if present)
        affected = set(sample['low_coverage_regions'] + sample['missing_coverage_regions'] + [event['region'] for event in sample['indels']])
        if sample['flags']['mixed']:
            affected.add('Genome')
        priority = sum(sample['flags'].values())
        export = [sample['sample'], sample['lineage'], sample['clade'], sample['qc_status'], sample['qpcr']['status'],
                  sample['nextclade_qc'], sample['mixed_sites']['value'], *sample['coverage'].values(),
                  ' | '.join(sample['review_reasons'])]
        detail_html = ''.join(f'<dt>{esc(key)}</dt><dd>{esc(value)}</dd>' for key, value in details.items())
        reasons = ''.join(f'<li>{esc(value)}</li>' for value in sample['review_reasons']) or '<li>No assessment flags</li>'
        rows.append(
            f'<tr data-sample="{esc(sample["sample"])}" data-qc="{sample["qc_status"]}" '
            f'data-lineage="{esc(sample["lineage"] or "Unavailable")}" data-qpcr="{sample["qpcr"]["status"]}" '
            f'data-flags="{flags}" data-regions="{esc(" ".join(sorted(affected)))}" '
            f'data-coverage="{esc(" ".join(sample["low_coverage_regions"]))}" '
            f'data-missing="{esc(" ".join(sample["missing_coverage_regions"]))}" '
            f'data-indels="{esc(" ".join(sorted({event["region"] for event in sample["indels"]})))}" '
            f'data-mixed="{"Genome" if sample["flags"]["mixed"] else ""}" '
            f'data-priority="{priority}" data-export="{esc(json.dumps(export, ensure_ascii=False))}">'
            f'<th scope="row">{esc(sample["sample"])}<small>{esc(sample["barcode"])}</small></th>'
            f'<td>{esc(sample["lineage"] or "Unavailable")}<small>{esc(sample["clade"])}</small></td>'
            f'<td>{esc(sample["qpcr"]["status"])}</td><td><span class="badge">{sample["qc_status"]}</span></td>'
            + ''.join(cells) + f'<td>{fmt(sample["mixed_sites"]["value"])}</td><td>{esc(sample["nextclade_qc"] or "Unavailable")}</td>'
            f'<td><details><summary>Details</summary><div class="sample-details"><ul>{reasons}</ul><dl>{detail_html}</dl></div></details></td></tr>')
        for event in sample['indels']:
            values = [sample['sample'], event['region'], event['kind'], event['event'], event['column']]
            event_rows.append(f'<tr data-region="{event["region"]}" data-kind="{event["kind"]}" data-export="{esc(json.dumps(values))}">'
                              + ''.join(f'<td>{esc(value)}</td>' for value in values) + '</tr>')
    region_rows = ''.join(
        f'<tr><th>{region}</th><td>{values["threshold"]:g}%</td><td>{ratio(values["passed"])}</td>'
        f'<td>{ratio(values["low_coverage"])}</td><td>{ratio(values["missing_or_invalid"])}</td>'
        f'<td>{fmt(values["median_coverage"], "%")}</td></tr>' for region, values in report['regions'].items())
    def options(values):
        return ''.join(f'<option>{esc(value)}</option>' for value in values)
    def distribution(values):
        return ''.join(f'<div class="distribution"><span>{esc(key)}</span><b>{value}</b>'
                       f'<progress value="{value}" max="{max(total, 1)}">{value}</progress></div>' for key, value in values.items()) or '<p>No records.</p>'
    payload = json.dumps(report, ensure_ascii=False, allow_nan=False).replace('&', '\\u0026').replace('<', '\\u003c').replace('>', '\\u003e').replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
    replacements = {
        'TITLE': esc(', '.join(report['metadata']['RunID']) or report['source']['filename']),
        'WORKFLOW': report['workflow'].upper(), 'TOTAL': str(total), 'ASSIGNED': ratio(report['counts']['lineage_assigned']),
        'UNASSIGNED': ratio(report['counts']['lineage_unavailable']), 'REVIEW': str(report['counts']['review']),
        'ASSESSMENT': report['assessment'], 'SAMPLE_ROWS': ''.join(rows), 'REGION_ROWS': region_rows,
        'EVENT_ROWS': ''.join(event_rows), 'EVENT_COUNT': str(len(event_rows)),
        'METADATA': ''.join(f'<dt>{esc(key)}</dt><dd>{esc("; ".join(values) or "Unavailable")}</dd>' for key, values in report['metadata'].items()),
        'NOTES': ''.join(f'<li>{esc(value)}</li>' for value in report['warnings']) or '<li>No additional availability notes.</li>',
        'TRIAGE': ''.join(f'<button class="triage" data-finding="{key}"><strong>{report["counts"]["flags"][key]}</strong>{esc(label)}</button>' for key, label in FINDINGS.items()),
        'FINDINGS': ''.join(f'<option value="{key}">{esc(label)}</option>' for key, label in FINDINGS.items()),
        'LINEAGES': options(report['counts']['lineages']), 'QPCR_OPTIONS': options(report['counts']['qpcr']),
        'REGIONS': options(REGIONS), 'QPCR_COUNTS': distribution(report['counts']['qpcr']),
        'LINEAGE_COUNTS': distribution(report['counts']['lineages']), 'CLADE_COUNTS': distribution(report['counts']['clades']),
        'COVERAGE_THRESHOLD': str(report['rules']['coverage_threshold_percent']),
        'CDS_THRESHOLD': str(report['rules']['cds_threshold_percent']), 'MIXED_THRESHOLD': str(report['rules']['mixed_sites_threshold']),
        'RULES': ''.join(f'<li><strong>{esc(key.replace("_", " ").capitalize())}:</strong> {esc(value)}</li>' for key, value in report['rules'].items() if isinstance(value, str)),
        'SOURCE': esc(report['source']['filename']), 'HASH': report['source']['sha256'],
        'MASTER': esc(report['master_source'] or 'Not supplied'), 'VERSION': VERSION, 'JSON': payload,
    }
    template = (Path(__file__).parent / 'templates/sars_qc.html').read_text(encoding='utf-8')
    return re.sub(r'@@([A-Z_]+)@@', lambda match: replacements[match[1]], template)


def validate_output(output, inputs=()):
    output = Path(output)
    if output.suffix.lower() != '.html':
        raise ValueError('QC output must use an .html filename')
    for destination in (output, output.with_suffix('.json')):
        for source in inputs:
            if source and (destination.resolve() == Path(source).resolve()
                           or (destination.exists() and Path(source).exists() and os.path.samefile(destination, source))):
                raise ValueError('QC outputs must be separate from input/master files')


def write_report(path, output, master=None, workflow='fastq', master_label=None, **options):
    path, output = Path(path), Path(output)
    validate_output(output, (path, master))
    report = build_report(path, read_table(master)[1] if master else None, workflow,
                          master_source=(master_label or Path(master).name) if master else None, **options)
    if master:
        report['master_sha256'] = hashlib.sha256(Path(master).read_bytes()).hexdigest()
    contents = ((output, render(report)),
                (output.with_suffix('.json'), json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n'))
    output.parent.mkdir(parents=True, exist_ok=True)
    for destination, content in contents:
        fd, name = tempfile.mkstemp(prefix='.sars-qc-', dir=output.parent)
        temporary = Path(name)
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--outdir', type=Path, default=Path('.'))
    parser.add_argument('--master', type=Path)
    parser.add_argument('--workflow', choices=('fastq', 'fasta'), default='fastq')
    parser.add_argument('--coverage-threshold', type=float, default=80)
    parser.add_argument('--cds-threshold', type=float, default=80)
    parser.add_argument('--mixed-threshold', type=int, default=3)
    args = parser.parse_args()
    try:
        output = args.outdir / f'{args.input.stem}_qc.html'
        report = write_report(args.input, output, args.master, args.workflow, coverage_threshold=args.coverage_threshold,
                              cds_threshold=args.cds_threshold, mixed_threshold=args.mixed_threshold)
        print(f'Created {output} and {output.with_suffix(".json")} ({report["counts"]["samples"]} samples)')
    except (OSError, ValueError, csv.Error) as error:
        parser.exit(1, f'SARS QC report failed: {error}\n')


if __name__ == '__main__':
    main()
