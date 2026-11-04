#!/usr/bin/env python3
"""Create SC2 GISAID metadata and matching FASTA from currently approved master rows."""

import argparse
from collections import Counter, defaultdict
import csv
from datetime import date
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'fluseq/master_csv/bin'))
from merge_master_csv import read_table, repair_metadata_text
from merge_master_fasta import read_fasta

APPROVAL_HELPER = ROOT / 'gisaid/shared/approved_master.cjs'
MASTER = ('N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/'
          'Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2/master.csv')
LABS = 'N:/Virologi/Influensa/ARoh/Influenza/GISAID/Innsender_GISAID.csv'
OUTDIR = 'N:/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/SARS-CoV-2/4-GISAIDsubmisjon'
AUTHORS = 'Bragstad, K; Hungnes, O; Madsen, MP; Rohringer, A; Riis, R; Knutsen, MF'
SUBMITTING_LAB = 'Norwegian Institute of Public Health, Department of Virology'
SUBMITTING_ADDRESS = 'P.O.Box 222 Skoyen, 0213 Oslo, Norway'
COLUMNS = ['submitter', 'fn', 'covv_virus_name', 'covv_type', 'covv_passage',
           'covv_collection_date', 'covv_location', 'covv_host', 'covv_gender',
           'covv_patient_age', 'covv_patient_status', 'covv_specimen', 'covv_seq_technology',
           'covv_assembly_method', 'covv_orig_lab', 'covv_orig_lab_addr', 'covv_subm_lab',
           'covv_subm_lab_addr', 'covv_authors', 'covv_outbreak', 'covv_add_host_info',
           'covv_add_location', 'covv_provider_sample_id', 'covv_last_vaccinated',
           'covv_treatment', 'covv_coverage', 'covv_sampling_strategy']


def approval(master, token=None):
    command = [os.environ.get('GISAID_NODE', 'node'), str(APPROVAL_HELPER),
               '--master', str(master), '--pathogen', 'SC2']
    if token:
        command += ['--expect-token', token]
    result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', timeout=120)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'Sequence Review approval check failed')
    return None if token else json.loads(result.stdout)


def require(headers, required, label):
    missing = set(required) - set(headers)
    if missing:
        raise ValueError(f'{label}: missing columns: ' + ', '.join(sorted(missing)))


def coverage_ok(value):
    try:
        number = float(value.strip().replace(',', '.'))
    except ValueError:
        return False
    return math.isfinite(number) and 0.75 <= number <= 1


def lab_lookup(path):
    headers, rows = read_table(path)
    require(headers, ['Innsender_nr', 'Innsender_navn'], 'Lab lookup')
    labs = {}
    for row in rows:
        code = row['Innsender_nr'].strip()
        if not code:
            continue
        if code in labs:
            raise ValueError('Lab lookup contains duplicate Innsender_nr values')
        addresses = {row.get(name, '').strip() for name in ('Innsender_adresse', 'Lab_address')} - {''}
        if len(addresses) > 1:
            raise ValueError('Lab lookup has conflicting address columns')
        labs[code] = (row['Innsender_navn'].strip(), next(iter(addresses), ''))
    return labs


def match_sequences(selected, identities, records):
    # Match original master identifiers, not manually edited sequence identifiers.
    aliases = defaultdict(set)
    for row in identities:
        for field in ('NGS_LW_ID', 'OriginalName', 'SampleID', 'Key', 'Prove_LW_ID'):
            value = row[field].strip()
            if value and value.upper() not in {'NA', 'N/A', 'NULL', 'NONE', '-'}:
                aliases[value].add(row['review_key'])
    wanted = {review['key'] for _, review in selected}
    matches = defaultdict(list)
    for record_id, (_, sequence) in records.items():
        candidates = aliases.get(record_id, set())
        if candidates & wanted:
            if len(candidates) != 1:
                raise ValueError('A selected FASTA ID matches multiple master samples')
            matches[next(iter(candidates))].append((record_id, sequence))
    if any(len(matches[key]) != 1 for key in wanted):
        raise ValueError('Each eligible sample must match exactly one FASTA record; missing or ambiguous matches found')
    return {key: matches[key][0] for key in wanted}


def isolate_name(key, collection_date):
    try:
        collected = date.fromisoformat(collection_date.strip())
    except ValueError as error:
        raise ValueError('Eligible samples need a valid ISO Prove_Tatt date (YYYY-MM-DD)') from error
    unique = key[4:] if re.fullmatch(r'[0-9]{5,}', key) else key
    if not unique or re.search(r'[\s/>]', unique):
        raise ValueError('Eligible Key cannot form an unambiguous FASTA submission name')
    return f'hCoV-19/Norway/{unique}/{collected.year}'


def metadata_row(row, lab, args, fasta_name):
    name = isolate_name(row['Key'], row['Prove_Tatt'])
    collected = date.fromisoformat(row['Prove_Tatt'].strip())
    repair_metadata_text(row)
    county = row['Pasient_Fylke_Name'].strip()
    if not county or county.upper() in {'NA', 'N/A', 'NULL', 'NONE'}:
        raise ValueError('Eligible samples need Pasient_Fylke_Name')
    gender = row.get('Pasient_Kjnn', row.get('Pasient_Kjonn', '')).upper()
    if row['Prove_Kategori'] == 'P1_':
        sampling = 'Sentinel surveillance (ARI)'
    elif row['Pasient_Status'] == 'Inneliggende':
        sampling = 'Non-sentinel surveillance (hospital)'
    elif row['Prove_Kategori'] == 'P2_' and row['Pasient_Status'] == 'Poliklinisk':
        sampling = 'Non-sentinel surveillance (outpatient)'
    else:
        sampling = ''
    technology = args.sequencing_technology
    if row['NGS_Primer_vers'].startswith('VM.3'):
        technology += ' - Midnight version 3'
    result = dict.fromkeys(COLUMNS, 'Unknown')
    result.update(submitter=args.submitter, fn=fasta_name,
                  covv_virus_name=name,
                  covv_type='betacoronavirus', covv_passage='Clinical Specimen',
                  covv_collection_date=collected.isoformat(), covv_location=f'Europe/Norway/{county}',
                  covv_host='Human', covv_gender=gender if gender in {'M', 'F'} else '',
                  covv_seq_technology=technology, covv_assembly_method=args.assembly_method,
                  covv_orig_lab=lab[0], covv_orig_lab_addr=lab[1],
                  covv_subm_lab=SUBMITTING_LAB, covv_subm_lab_addr=SUBMITTING_ADDRESS,
                  covv_authors=args.authors, covv_coverage=row['NGS_Depth'], covv_sampling_strategy=sampling)
    return result


def export(args):
    master = args.master.resolve()
    fasta = (args.fasta or master.with_name('master.fasta')).resolve()
    snapshot = approval(master)
    require(snapshot['headers'], ['Key', 'NGS_Run_ID', 'GISAID_Kommentar', 'NC_Coverage',
            'Prove_Tatt', 'Pasient_Fylke_Name', 'Prove_Innsender_ID', 'Prove_Kategori',
            'Pasient_Status', 'NGS_Depth', 'NGS_Primer_vers'], 'SC2 master')
    if not {'Pasient_Kjnn', 'Pasient_Kjonn'} & set(snapshot['headers']):
        raise ValueError('SC2 master: missing Pasient_Kjnn/Pasient_Kjonn')
    counts = Counter()
    selected = []
    for row, review in zip(snapshot['rows'], snapshot['approvals']):
        if row['NGS_Run_ID'] != args.run:
            counts['other_run'] += 1
        elif row['GISAID_Kommentar']:
            counts['gisaid_comment'] += 1
        elif not coverage_ok(row['NC_Coverage']):
            counts['coverage'] += 1
        elif not row['Key'].strip():
            counts['missing_key'] += 1
        else:
            selected.append((row, review))
    if not selected:
        raise ValueError('No currently approved samples remain after run, comment, coverage and Key filters')
    keys = [row['Key'] for row, _ in selected]
    if len(keys) != len(set(keys)):
        raise ValueError('Eligible samples must have unique Key values')
    labs_bytes = args.lab_lookup.read_bytes()
    fasta_bytes = fasta.read_bytes()
    # Parse exactly the bytes recorded in the manifest, even if a source writer runs.
    with tempfile.TemporaryDirectory(prefix='sc2-gisaid-inputs-') as directory:
        lab_snapshot = Path(directory) / 'labs.csv'
        fasta_snapshot = Path(directory) / 'master.fasta'
        lab_snapshot.write_bytes(labs_bytes)
        fasta_snapshot.write_bytes(fasta_bytes)
        labs = lab_lookup(lab_snapshot)
        records, duplicates = read_fasta(fasta_snapshot)
    if duplicates:
        raise ValueError('Duplicate FASTA records must be resolved before export')
    sequences = match_sequences(selected, snapshot['identities'], records)
    prefix = args.prefix or 'GISAID SUBMISSION - ' + date.today().strftime('%U-%Y')
    if Path(prefix).name != prefix or prefix in {'.', '..'} or any(c in prefix for c in '\\/:\r\n\0'):
        raise ValueError('--prefix must be a filename without a directory')
    fasta_name = prefix + '.fasta'
    submission, fasta_lines, audit = [], [], []
    for row, review in selected:
        lab = labs.get(row['Prove_Innsender_ID'].strip())
        if not lab or not lab[0]:
            raise ValueError('An eligible sample lacks a matching originating lab name in the CSV lookup')
        if not lab[1]:
            counts['missing_lab_address'] += 1
        metadata = metadata_row(row, lab, args, fasta_name)
        record_id, sequence = sequences[review['key']]
        submission.append(metadata)
        fasta_lines.extend(['>' + metadata['covv_virus_name'], sequence])
        audit.append({**review, 'fasta_id': record_id, 'virus_name': metadata['covv_virus_name']})
    if len({row['covv_virus_name'] for row in submission}) != len(submission):
        raise ValueError('Different eligible samples produce the same virus name')
    csv_text = io.StringIO(newline='')
    writer = csv.DictWriter(csv_text, fieldnames=COLUMNS, lineterminator='\n')
    writer.writeheader()
    writer.writerows(submission)
    payloads = {prefix + '.csv': csv_text.getvalue().encode('utf-8'),
                fasta_name: ('\n'.join(fasta_lines) + '\n').encode('utf-8')}
    manifest = {'format_version': 1, 'pathogen': 'SC2', 'run': args.run, 'samples': len(selected),
                'approval_counts': snapshot['counts'], 'filter_counts': dict(counts),
                'review_snapshot_token': snapshot['token'], 'master_sha256': snapshot['master_sha256'],
                'fasta_sha256': hashlib.sha256(fasta_bytes).hexdigest(),
                'lab_lookup_sha256': hashlib.sha256(labs_bytes).hexdigest(), 'approvals': audit,
                'outputs': {name: hashlib.sha256(data).hexdigest() for name, data in payloads.items()}}
    payloads[prefix + '.manifest.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    approval(master, snapshot['token'])
    if fasta.read_bytes() != fasta_bytes or args.lab_lookup.read_bytes() != labs_bytes:
        raise ValueError('FASTA or lab lookup changed during export; retry')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    paths = [args.output_dir / name for name in payloads]
    if any(path.exists() for path in paths):
        raise ValueError('Submission output already exists; use a new --prefix or output directory')
    created = []
    try:
        for path in paths:
            with path.open('xb') as handle:
                created.append(path)
                handle.write(payloads[path.name])
                handle.flush()
                os.fsync(handle.fileno())
    except BaseException:
        for path in created:
            path.unlink(missing_ok=True)
        raise
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', help='Exact NGS_Run_ID')
    parser.add_argument('submitter', help='GISAID submitter account name')
    parser.add_argument('--master', type=Path, default=Path(MASTER))
    parser.add_argument('--fasta', type=Path, help='Default: master.fasta beside master.csv')
    parser.add_argument('--lab-lookup', type=Path, default=Path(LABS))
    parser.add_argument('--output-dir', type=Path, default=Path(OUTDIR))
    parser.add_argument('--prefix', help='New output filename prefix; default matches the legacy week/year name')
    parser.add_argument('--assembly-method', required=True, help='Verified assembly method for this run')
    parser.add_argument('--sequencing-technology', default='Oxford Nanopore - GridION')
    parser.add_argument('--authors', default=AUTHORS)
    args = parser.parse_args()
    try:
        if any(not value.strip() for value in (args.run, args.submitter, args.assembly_method, args.sequencing_technology, args.authors)):
            raise ValueError('Run, submitter, assembly method, technology and authors must be nonempty')
        result = export(args)
        print(json.dumps({key: result[key] for key in ('samples', 'approval_counts', 'filter_counts')}, sort_keys=True))
        print(f'Submission CSV, FASTA and manifest written to {args.output_dir}')
    except (OSError, ValueError, csv.Error, subprocess.SubprocessError) as error:
        parser.exit(1, f'SC2 GISAID export failed: {error}\n')


if __name__ == '__main__':
    main()
