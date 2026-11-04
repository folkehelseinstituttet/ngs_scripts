"""Display existing SARS surveillance results; no sequence calls are recalculated."""

import math
import re
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import schema
from merge_master_csv import (INDEX, alias_index, fasta_match, identifier, index_rows,
                              sequence_id, sequence_index, transform)

GENES = ('S', 'ORF1a', 'ORF1b', 'E', 'M', 'N', 'ORF3a', 'ORF6', 'ORF7a', 'ORF7b', 'ORF8', 'ORF9b')
MISSING = {'', 'NA', 'N/A', 'NAN', 'NONE', 'NULL', '-'}
NO_EVENTS = {'no mutation', 'no mutations', 'no frameshifts', 'no aadeletions', 'no aainsertions', '0', '[]'}
QPCR_FIELDS = ('PCR_SC2_EXT_Res', 'PCR_SC2_TRI_Res', 'PCR_triplex_SC2_Res')
CT_FIELDS = ('PCR_SC2_EXT_CT', 'PCR_SC2_TRI_CT', 'PCR_triplex_SC2_CT')


def clean(value):
    value = str(value if value is not None else '').strip()
    return '' if value.upper() in MISSING else value


def field(row, *names):
    """First present column wins, even when its cell is missing or invalid."""
    folded = {key.casefold(): value for key, value in row.items()}
    return next((folded[name.casefold()] for name in names if name.casefold() in folded), '')


def number(value, maximum=None):
    text = clean(value)
    if text.count(',') == 1 and '.' not in text:
        text = text.replace(',', '.')
    try:
        parsed = float(text)
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) and parsed >= 0 and (maximum is None or parsed <= maximum) else None


def measurement(row, columns, integer=False):
    """Each column has explicit units; fraction/percent is never guessed by value."""
    folded = {key.casefold(): (key, value) for key, value in row.items()}
    sources, values = {}, []
    invalid = False
    for name, maximum, scale in columns:
        if name.casefold() not in folded:
            continue
        actual, raw = folded[name.casefold()]
        sources[actual] = raw
        parsed = number(raw, maximum)
        if parsed is not None and integer and not parsed.is_integer():
            parsed = None
        invalid |= bool(clean(raw)) and parsed is None
        values.append(None if parsed is None else parsed * scale)
    valid = [value for value in values if value is not None]
    conflict = any(not math.isclose(value, valid[0], abs_tol=1e-6) for value in valid[1:])
    value = values[0] if values else None
    return {'value': int(value) if integer and value is not None else value,
            'sources': sources, 'invalid': invalid, 'conflict': conflict}


def coverage(row):
    metrics = {'Genome': measurement(row, [('coverage', 1, 100), ('NC_Coverage', 1, 100),
                                           ('QC_overall_pct', 100, 1), ('coverage_stats', 1, 100)])}
    cds, problems = {}, []
    raw = clean(field(row, 'cdsCoverage'))
    for part in re.split(r'[;,](?=\s*[A-Za-z][A-Za-z0-9]*\s*:)', raw) if raw else []:
        if ':' not in part:
            problems.append('Malformed cdsCoverage entry')
            continue
        gene, value = (value.strip() for value in part.split(':', 1))
        if gene not in GENES:
            problems.append('Unrecognised cdsCoverage gene')
            continue
        if gene in cds:
            if cds[gene] != value:
                problems.append(f'Conflicting cdsCoverage entries for {gene}')
                cds[gene] = 'INVALID'
        else:
            cds[gene] = value
    for gene in GENES:
        source = {name: value for name, value in row.items() if name.casefold() == f'qc_cds_{gene}'.casefold()}
        if gene in cds:
            source[f'cdsCoverage:{gene}'] = cds[gene]
        metrics[gene] = measurement(source, [(f'QC_cds_{gene}', 1, 100), (f'cdsCoverage:{gene}', 1, 100)])
    return metrics, list(dict.fromkeys(problems))


def indels(row):
    events, availability = [], {}
    for gene in (*GENES, 'Genome'):
        kinds = ('Frameshift',) if gene == 'Genome' else ('Deletion', 'Insertion')
        for kind in kinds:
            columns = (('NC_Genome_frameShifts', 'NC_Genome_Frameshift', 'frameShifts') if gene == 'Genome'
                       else (f'{gene}_aa{kind}s', f'NC_{gene}_{kind}s'))
            raw = field(row, *columns)
            value = clean(raw)
            availability[f'{gene}:{kind}'] = bool(value)
            if not value or value.casefold() in NO_EVENTS:
                continue
            actual = next(name for name in row if name.casefold() in {col.casefold() for col in columns})
            for event in dict.fromkeys(part.strip() for part in re.split(r'[;,]', value) if part.strip()):
                events.append({'region': gene, 'kind': kind, 'event': event, 'column': actual})
    return events, availability


def master_index(rows):
    _, canonical, _ = schema()
    headers = list(dict.fromkeys(name for row in rows for name in row))
    _, transformed = transform((headers, rows), {}, canonical, 'QC master')
    matched = []
    for row in transformed:
        key = identifier(row.get(INDEX)) or sequence_id(row) or identifier(row.get('Key'))
        if key:
            row[INDEX] = key
            matched.append(row)
    return {'rows': index_rows(matched, 'QC master'),
            'sequences': sequence_index(matched, source='QC master'),
            'aliases': alias_index(matched, (INDEX, 'Key', 'OriginalName', 'SampleID'))}


def master_match(row, index, workflow):
    sample = clean(field(row, 'Sample'))
    if workflow == 'fastq':
        key = index['sequences'].get(sample)
    else:
        lookup_row = dict(row)
        lookup_row.setdefault('OriginalName', sample)
        lookup_row.setdefault('SampleID', sample)
        key = fasta_match(lookup_row, index['aliases'], index['sequences'])
    supplied = identifier(field(row, INDEX))
    if supplied and key and supplied != key:
        raise ValueError('Report specimen and sequencing identifiers disagree')
    return index['rows'].get(key or supplied)


def qpcr_evidence(row):
    result = {'status': 'No master match', 'results': {}, 'ct': {}, 'unrecognised': []}
    if row is None:
        return result
    positive = negative = False
    for name in QPCR_FIELDS:
        raw = clean(field(row, name))
        if not raw:
            continue
        result['results'][name] = raw
        normalized = ' '.join(raw.casefold().split())
        if normalized in {'påvist', 'p vist'}:
            positive = True
        elif normalized in {'ikke påvist', 'ikke p vist', 'negative', 'negativ', 'neg', 'not detected'}:
            negative = True
        else:
            result['unrecognised'].append(name)
    for name in CT_FIELDS:
        raw = clean(field(row, name))
        if raw:
            result['ct'][name] = {'raw': raw, 'value': number(raw)}
    result['status'] = ('Unrecognised qPCR result' if result['unrecognised'] else
                        'Conflicting qPCR results' if positive and negative else
                        'Positive qPCR' if positive else 'Negative qPCR' if negative else
                        'Ct only' if result['ct'] else 'qPCR unavailable')
    return result


def thresholds(coverage_threshold=80, cds_threshold=80, mixed_threshold=3):
    for label, value in (('Genome coverage', coverage_threshold), ('CDS coverage', cds_threshold)):
        if number(value, 100) is None or float(value) <= 0:
            raise ValueError(f'{label} threshold must be greater than 0 and at most 100')
    if number(mixed_threshold) is None or float(mixed_threshold) != int(float(mixed_threshold)):
        raise ValueError('Mixed-site threshold must be a non-negative integer')


def summarise_sample(row, master_row=None, coverage_threshold=80, cds_threshold=80, mixed_threshold=3):
    metrics, problems = coverage(row)
    cov = {gene: metric['value'] for gene, metric in metrics.items()}
    low = [gene for gene, value in cov.items() if value is not None and value < (coverage_threshold if gene == 'Genome' else cds_threshold)]
    missing = [gene for gene, value in cov.items() if value is None]
    inconsistent = [gene for gene, metric in metrics.items() if metric['invalid'] or metric['conflict']]
    mixed = measurement(row, [('NC_Genome_MixedSites', None, 1), ('NC_MixedSItes', None, 1),
                              ('qc.mixedSites.totalMixedSites', None, 1)], integer=True)
    nextclade = clean(field(row, 'NC_Genome_QC', 'NC_Genome_Quality', 'qc.overallStatus'))
    raw_qc = field(row, 'NGS_QC_Sum')
    qc_present = any(name.casefold() == 'ngs_qc_sum' for name in row)
    reported = 'Review' if clean(raw_qc) else ('No flags' if qc_present and not raw_qc.strip() else 'Unavailable')
    lineage = clean(field(row, 'Nextclade_pango', 'NC_Pangolin_Short'))
    if lineage.casefold() in {'unassigned', 'unknown', 'unclassified'}:
        lineage = ''
    events, event_availability = indels(row)
    missing_events = [name for name, available in event_availability.items() if not available]
    qpcr = qpcr_evidence(master_row)
    reasons = list(problems)
    if low:
        reasons.append('Low coverage: ' + ', '.join(low))
    if missing:
        reasons.append('Coverage missing or invalid: ' + ', '.join(missing))
    if inconsistent:
        reasons.append('Conflicting or invalid coverage fields: ' + ', '.join(inconsistent))
    if reported != 'No flags':
        reasons.append('Reported QC: ' + (clean(raw_qc) or 'Unavailable'))
    qc_note = clean(field(row, 'QC'))
    if qc_note and qc_note.casefold() not in {'pass', 'passed', 'good', 'no flags', 'ok'}:
        reasons.append('Reported QC note: ' + qc_note)
    if nextclade.casefold() != 'good':
        reasons.append('Nextclade QC: ' + (nextclade or 'Unavailable'))
    high_mixed = mixed['value'] is not None and mixed['value'] > mixed_threshold
    if high_mixed:
        reasons.append(f"Genome mixed sites >{mixed_threshold:g}: {mixed['value']}")
    if mixed['value'] is None:
        reasons.append('Genome mixed-site count unavailable')
    if mixed['invalid'] or mixed['conflict']:
        reasons.append('Conflicting or invalid genome mixed-site fields')
    if events:
        reasons.append('Reported indels / frameshifts: ' + ', '.join(dict.fromkeys(event['region'] for event in events)))
    if missing_events:
        reasons.append('Indel measurements unavailable: ' + ', '.join(missing_events))
    if not lineage:
        reasons.append('Lineage assignment unavailable')
    if qpcr['status'] in {'Conflicting qPCR results', 'Unrecognised qPCR result'}:
        reasons.append(qpcr['status'])
    gisaid = clean(field(row, 'GISAID_Comment', 'GISAID_Kommentar'))
    if gisaid and gisaid.casefold() != 'no flags':
        reasons.append('Reported GISAID comment: ' + gisaid)
    status = 'Review' if reasons else 'No flags'
    if all(value is None for value in cov.values()) and not nextclade and mixed['value'] is None and reported == 'Unavailable':
        status = 'Unavailable'
    return {
        'sample': clean(field(row, 'Sample')), 'master_key': clean((master_row or {}).get(INDEX)),
        'barcode': clean(field(row, 'Barcode')), 'plate_position': clean(field(row, 'PCR-PlatePosition')),
        'lineage': lineage, 'lineage_long': clean(field(row, 'partiallyAliased', 'NC_Pangolin_Long')),
        'clade': clean(field(row, 'clade', 'NC_Clade')), 'clade_who': clean(field(row, 'clade_who')),
        'qc_status': status, 'reported_qc_status': reported, 'reported_qc': raw_qc,
        'qc_note': qc_note, 'review_reasons': reasons, 'coverage': cov, 'coverage_evidence': metrics,
        'low_coverage_regions': low, 'missing_coverage_regions': missing,
        'mixed_sites': mixed, 'nextclade_qc': nextclade,
        'indels': events, 'indel_availability': event_availability, 'qpcr': qpcr,
        'consensus_ct': {'raw': clean(field(row, 'KonsCt')), 'value': number(field(row, 'KonsCt'))},
        'gisaid_comment': gisaid,
        'reported_dr_codes': {key: clean(value) for key, value in row.items() if key in
                              ('DR_Res_Paxlovid', 'DR_Res_Remdesevir', 'DR_Res_mAbs')},
        'flags': {'coverage': bool(low), 'missing': bool(missing), 'mixed': high_mixed,
                  'indels': bool(events), 'lineage': not bool(lineage),
                  'qpcr': qpcr['status'] in {'Conflicting qPCR results', 'Unrecognised qPCR result'},
                  'other': bool(problems or inconsistent or mixed['invalid'] or mixed['conflict']
                                or reported != 'No flags' or nextclade.casefold() != 'good'
                                or (gisaid and gisaid.casefold() != 'no flags')
                                or missing_events
                                or (qc_note and qc_note.casefold() not in {'pass', 'passed', 'good', 'no flags', 'ok'}))},
    }
