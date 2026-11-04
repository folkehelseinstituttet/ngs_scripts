#!/usr/bin/env python3
"""Preview a tabular master merge without modifying any source files.

No sequence processing or biological interpretation is performed. A JSON mapping
may explicitly rename report or metadata columns. Unknown columns remain text.
"""
import argparse
import csv
import json
from pathlib import Path
import sys

SHARED = Path(__file__).resolve().parents[2] / 'fluseq' / 'master_csv' / 'bin'
# This script is under sarsseq/master_csv, so the repository is parents[2].
sys.path.insert(0, str(SHARED))
from merge_master_csv import (read_table, transform, prepare_indexes, index_rows,
                              sequence_id, identifier, INDEX, KEY_SOURCE,
                              INDEX_SOURCE, SEQUENCE_COLUMNS, alias_index, fasta_match,
                              repair_metadata_text)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import schema, report_mapping


def preview(master, metadata, report, mappings=None, workflow='fastq', nonempty_report=False):
    mappings = mappings or {}
    if not isinstance(mappings, dict) or set(mappings) - {'master', 'metadata', 'report'}:
        raise ValueError('Mapping must contain only master, metadata and report objects')
    columns, canonical, metadata_map = schema()
    defaults = {'master': {}, 'metadata': metadata_map, 'report': report_mapping(workflow)}
    tables = []
    for label, table in (('master', master), ('metadata', metadata), ('report', report)):
        mapping = mappings.get(label, {})
        if not isinstance(mapping, dict) or not all(isinstance(k, str) and isinstance(v, str) and v for k, v in mapping.items()):
            raise ValueError(f'{label} mappings must be nonempty column-name strings')
        effective = {**defaults[label], **mapping}
        effective = {source: canonical.get(dest.casefold(), dest) for source, dest in effective.items()}
        tables.append(transform(table, effective, canonical, label))
    (mh, mr), (dh, dr), (rh, rr) = tables
    for label, headers in (('metadata', dh), ('report', rh)):
        if {KEY_SOURCE, INDEX_SOURCE}.intersection(headers):
            raise ValueError(f'{label}: master identifier provenance is reserved')
    if not {INDEX, 'Key'}.intersection(mh):
        raise ValueError('master: requires Prove_LW_ID or legacy Key column')
    if not {INDEX, *SEQUENCE_COLUMNS}.intersection(dh):
        raise ValueError('metadata: requires Prove_LW_ID or a sequencing ID column')
    if not rr:
        raise ValueError('report: requires at least one data row')
    existing, meta, sequences, migrated = prepare_indexes(mr, dr)
    aliases = alias_index([*existing.values(), *meta.values()], (INDEX, 'Key', 'OriginalName', 'SampleID'))
    for row in rr:
        supplied = identifier(row.get(INDEX))
        if workflow == 'fasta':
            # SARS emits Sample in both modes; retain it as the original FASTA name.
            if 'OriginalName' not in row:
                row['OriginalName'] = row.get('SampleID', '')
            matched = fasta_match(row, aliases, sequences)
        else:
            matched = sequences.get(sequence_id(row))
        if supplied and matched and supplied != matched:
            raise ValueError('Report specimen and sequencing identifiers disagree')
        key = matched or supplied or sequence_id(row)
        if not key:
            raise ValueError('Report row needs an exact specimen or sequencing identifier')
        if not matched and not supplied:
            if key in existing or key in meta:
                raise ValueError('Fallback identifier collides with an existing specimen')
            row['Master_Index_Source'] = 'Sequence_ID'
        row[INDEX] = key
    incoming = index_rows(rr, 'report')
    added = updated = unchanged = without_metadata = 0
    for key, row in incoming.items():
        old = existing.get(key)
        merged = dict(old or {INDEX: key})
        if key not in meta:
            without_metadata += 1
        merged.update({name: value for name, value in meta.get(key, {}).items() if value.strip()})
        merged.update({name: value for name, value in row.items()
                       if not nonempty_report or value.strip()})
        merged[INDEX] = key
        if old is None:
            added += 1
        elif key not in migrated and all(old.get(name, '') == merged.get(name, '')
                                        for name in old.keys() | merged.keys()):
            unchanged += 1
        else:
            updated += 1
        existing[key] = merged
    # Match Influenza's post-merge repairs, including rows outside this run.
    # Keep the repair count separate from report-row update counts.
    text_repaired = sum(repair_metadata_text(row) for row in existing.values())
    # Check consistency after the merge as well as before it.
    from merge_master_csv import sequence_index
    sequence_index(existing.values(), source='preview')
    headers = list(dict.fromkeys([*columns, *mh, *dh, *rh, INDEX, *(name for row in existing.values() for name in row)]))
    return headers, list(existing.values()), {
        'report_rows': len(incoming), 'total_rows': len(existing), 'reindexed': len(migrated),
        'text_repaired': text_repaired,
        'added': added, 'updated': updated, 'unchanged': unchanged,
        'without_metadata': without_metadata, 'total': len(existing), 'columns': len(headers),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('master', 'metadata', 'report', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--mapping', type=Path, help='JSON with master, metadata and report column-name maps')
    parser.add_argument('--workflow', choices=('fastq', 'fasta'), default='fastq')
    parser.add_argument('--nonempty-report', action='store_true', help='Preserve old values for blank report cells')
    args = parser.parse_args()
    try:
        if args.output.resolve() in {p.resolve() for p in (args.master, args.metadata, args.report)}:
            raise ValueError('Preview output must be separate from all input files')
        maps = json.loads(args.mapping.read_text(encoding='utf-8')) if args.mapping else {}
        if not isinstance(maps, dict) or set(maps) - {'master', 'metadata', 'report'}:
            raise ValueError('Mapping must contain only master, metadata and report objects')
        headers, rows, stats = preview(read_table(args.master), read_table(args.metadata), read_table(args.report),
                                      maps, args.workflow, args.nonempty_report)
        with args.output.open('x', encoding='utf-8-sig', newline='') as handle:
            writer = csv.DictWriter(handle, fieldnames=headers, delimiter=';', lineterminator='\n')
            writer.writeheader()
            writer.writerows(rows)
        print(json.dumps(stats, sort_keys=True))
    except (OSError, ValueError, csv.Error) as error:
        parser.exit(1, f'Preview failed: {error}\n')


if __name__ == '__main__':
    main()
