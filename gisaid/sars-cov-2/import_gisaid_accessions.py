#!/usr/bin/env python3
"""Import SC2 GISAID accessions into a mounted/UNC master CSV, with lock and backup."""

import argparse
from collections import defaultdict
from contextlib import nullcontext
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'shared'))
from sc2_metadata import MASTER, isolate_name
from merge_master_csv import read_table, write_table, digest, master_lock, backup_suffix

ID = 'GISAID_Isolate_ID'
NAME = 'GISAID_Isolate_Name'
ALIASES = {
    'name': ('Virus name', 'covv_virus_name', 'Isolate_Name', NAME),
    'accession': ('Accession ID', 'covv_accession_id', 'Isolate_Id', ID),
    'key': ('Submitting_Sample_Id',),
}


def read_exports(paths):
    result = []
    for path in paths:
        headers, rows = read_table(path)
        fields = {kind: [name for name in aliases if name in headers] for kind, aliases in ALIASES.items()}
        if not fields['accession'] or not (fields['name'] or fields['key']):
            raise ValueError('Export requires Accession ID plus Virus name or Submitting_Sample_Id columns')
        for row in rows:
            normalized = {}
            for kind, names in fields.items():
                values = {row[name].strip() for name in names} - {''}
                if len(values) > 1:
                    raise ValueError('Export has conflicting aliases for ' + kind)
                normalized[kind] = next(iter(values), '')
            result.append(normalized)
    return result


def merge_accessions(table, exports, manifest=None):
    headers, original_rows = table
    if 'Key' not in headers:
        raise ValueError('Master CSV requires Key')
    rows = [dict(row) for row in original_rows]
    keys, names, fasta_ids = defaultdict(set), defaultdict(set), defaultdict(set)
    for index, row in enumerate(rows):
        key = row['Key'].strip()
        if key:
            keys[key].add(index)
        if row.get(NAME, '').strip():
            names[row[NAME].strip()].add(index)
        if key:
            try:
                names[isolate_name(key, row.get('Prove_Tatt', ''))].add(index)
            except ValueError:
                pass  # Stored names or explicit submitting IDs can still match.
        for field in ('NGS_LW_ID', 'OriginalName', 'SampleID', 'Key', 'Prove_LW_ID'):
            value = row.get(field, '').strip()
            if value and value.upper() not in {'NA', 'N/A', 'NULL', 'NONE', '-'}:
                fasta_ids[value].add(index)
    if any(len(matches) > 1 for matches in keys.values()):
        raise ValueError('Master CSV contains duplicate nonempty Key values')
    if manifest is not None:
        if (not isinstance(manifest, dict) or manifest.get('format_version') != 1
                or manifest.get('pathogen') != 'SC2' or not isinstance(manifest.get('approvals'), list)):
            raise ValueError('Expected an SC2 submission manifest with format_version 1')
        seen = set()
        for record in manifest['approvals']:
            if (not isinstance(record, dict) or not all(isinstance(record.get(k), str) and record[k].strip()
                                                       for k in ('virus_name', 'fasta_id'))):
                raise ValueError('Malformed submission manifest identity')
            if record['virus_name'] in seen:
                raise ValueError('Duplicate virus name in submission manifest')
            seen.add(record['virus_name'])
            matches = fasta_ids.get(record['fasta_id'], set())
            if len(matches) > 1:
                raise ValueError('Manifest FASTA ID matches multiple master samples')
            if matches:
                prior = names.get(record['virus_name'], set())
                if prior and prior != matches:
                    raise ValueError('Manifest identity conflicts with master virus-name mapping')
                names[record['virus_name']].update(matches)

    stats = dict(export_rows=len(exports), matched_rows=0, skipped_unmatched=0,
                 skipped_missing_identifier=0, updated_samples=0, values_added=0)
    touched = set()
    for record in exports:
        if not record['name'] and not record['key']:
            stats['skipped_missing_identifier'] += 1
            continue
        by_key = keys.get(record['key'], set()) if record['key'] else set()
        by_name = names.get(record['name'], set()) if record['name'] else set()
        if len(by_name) > 1 or (by_key and by_name and by_key != by_name):
            raise ValueError('Returned identifiers match conflicting master samples')
        if record['key'] and not by_key:
            if by_name:
                raise ValueError('Returned submitting ID disagrees with the matched virus name')
            stats['skipped_unmatched'] += 1
            continue
        matches = by_key or by_name
        if not matches:
            stats['skipped_unmatched'] += 1
            continue
        target = next(iter(matches))
        stats['matched_rows'] += 1
        if record['accession'] and not re.fullmatch(r'EPI_ISL_[0-9]+', record['accession']):
            raise ValueError('Invalid accession ID for a matched sample; expected EPI_ISL_<digits>')
        if record['name'] and not re.fullmatch(r'hCoV-19/[^/\s]+/[^/\s]+/[0-9]{4}', record['name']):
            raise ValueError('Invalid virus name for a matched sample')
        for column, value in ((ID, record['accession']), (NAME, record['name'])):
            if not value:
                continue
            old = rows[target].get(column, '').strip()
            if old and old != value:
                raise ValueError('Conflicting existing or returned value for ' + column)
            if not old:
                rows[target][column] = value
                stats['values_added'] += 1
                touched.add(target)
    owners = {}
    for index, row in enumerate(rows):
        accession = row.get(ID, '').strip()
        if accession:
            if accession in owners and owners[accession] != index:
                raise ValueError('The same GISAID accession is assigned to multiple master samples')
            owners[accession] = index
    stats['updated_samples'] = len(touched)
    output_headers = list(headers)
    if touched:
        for column in (ID, NAME):
            if column not in output_headers:
                output_headers.append(column)
        rows = [{column: row.get(column, '') for column in output_headers} for row in rows]
    return output_headers, rows, stats


def import_accessions(master, exports, manifest=None, dry_run=False):
    master = Path(master).resolve()
    if not master.is_file():
        raise ValueError('Master CSV does not exist')
    inputs = [Path(path).resolve() for path in exports]
    if manifest:
        inputs.append(Path(manifest).resolve())
    if any(path == master or os.path.samefile(master, path) for path in inputs):
        raise ValueError('Import sources must be separate from the master CSV')
    records = read_exports(exports)
    mapping = json.loads(Path(manifest).read_text(encoding='utf-8-sig')) if manifest else None
    with nullcontext() if dry_run else master_lock(master):
        original = master.read_bytes()
        original_hash = hashlib.sha256(original).hexdigest()
        with tempfile.TemporaryDirectory(prefix='sc2-accessions-') as directory:
            snapshot = Path(directory) / 'master.csv'
            snapshot.write_bytes(original)
            headers, rows, stats = merge_accessions(read_table(snapshot), records, mapping)
        if digest(master) != original_hash:
            raise ValueError('Master changed during import; no replacement made')
        if dry_run or not stats['values_added']:
            return dict(stats, written=False, dry_run=dry_run)
        fd, filename = tempfile.mkstemp(prefix='.' + master.name + '.', suffix='.tmp', dir=master.parent)
        os.close(fd)
        candidate = Path(filename)
        try:
            write_table(candidate, headers, rows)
            if read_table(candidate) != (headers, rows):
                raise ValueError('Candidate CSV validation failed')
            candidate_hash = digest(candidate)
            if digest(master) != original_hash:
                raise ValueError('Master changed during import; no replacement made')
            backup = Path(str(master) + '.bak.' + backup_suffix())
            with backup.open('xb') as handle:
                shutil.copymode(master, backup)
                handle.write(original)
                handle.flush()
                os.fsync(handle.fileno())
            if digest(backup) != original_hash or digest(master) != original_hash:
                raise ValueError('Backup verification or concurrent-master check failed; no replacement made')
            shutil.copymode(master, candidate)
            os.replace(candidate, master)
            if digest(master) != candidate_hash:
                raise ValueError(f'Master readback verification failed after replacement; backup: {backup}')
            return dict(stats, written=True, backup=str(backup), dry_run=False)
        finally:
            candidate.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exports', type=Path, nargs='+', help='GISAID metadata TSV or CSV exports')
    parser.add_argument('--master', type=Path, default=Path(MASTER))
    parser.add_argument('--manifest', type=Path, help='Optional SC2 submission manifest for original FASTA-ID matching')
    parser.add_argument('--dry-run', action='store_true', help='Report proposed changes without locks, backups or writes')
    args = parser.parse_args()
    try:
        print(json.dumps(import_accessions(**vars(args)), sort_keys=True))
    except (OSError, ValueError, csv.Error) as error:
        parser.exit(1, f'SC2 accession import failed: {error}\n')


if __name__ == '__main__':
    main()
