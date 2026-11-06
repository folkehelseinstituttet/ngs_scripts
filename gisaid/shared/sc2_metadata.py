"""Shared Python SC2 metadata helpers for accession imports and validation.

The routine submission exporters use R. The optional approval() diagnostic here
uses the JavaScript reference reader, as did the former Python exporter.
"""
from datetime import date
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'fluseq/master_csv/bin'))
from merge_master_csv import read_table

APPROVAL_HELPER = ROOT / 'gisaid/shared/approved_master.cjs'
MASTER = ('N:/Virologi/NGS/1-NGS-Analyser/2-Utvikling/'
          'Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2/master.csv')


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


def isolate_name(key, collection_date):
    try:
        collected = date.fromisoformat(collection_date.strip())
    except ValueError as error:
        raise ValueError('Eligible samples need a valid ISO Prove_Tatt date (YYYY-MM-DD)') from error
    unique = key[4:] if re.fullmatch(r'[0-9]{5,}', key) else key
    if not unique or re.search(r'[\s/>]', unique):
        raise ValueError('Eligible Key cannot form an unambiguous FASTA submission name')
    return f'hCoV-19/Norway/{unique}/{collected.year}'
