#!/usr/bin/env python3
"""Read-only SC2 deployment validation against a completed run report."""

import argparse
import csv
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from preview_merge import preview, read_table
from sars_qc_report import build_report
from merge_master_fasta import read_fasta

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'gisaid/sars-cov-2'))
from sc2_gisaid_csv import approval, lab_lookup


def validate(report, workflow, master=None, metadata=None, fasta=None, lab=None, reviews=False):
    if (master is None) != (metadata is None):
        raise ValueError('Supply both --master and --metadata for a merge validation')
    if reviews and master is None:
        raise ValueError('--reviews requires --master and --metadata')
    required = ['gisaid/shared/approval.R', 'gisaid/shared/approved_master.cjs',
                'gisaid/shared/sequence_review_core.cjs', 'sarsseq/master_csv/templates/sars_qc.html',
                'gisaid/sars-cov-2/import_gisaid_accessions.py']
    if any(not (ROOT / path).is_file() for path in required):
        raise ValueError('Incomplete code checkout: a required shared/template/importer file is missing')
    source = read_table(report)
    result = {'workflow': workflow, 'report': {'columns': len(source[0]), 'samples': len(source[1])},
              'writes': False, 'python': sys.version.split()[0]}
    master_table = read_table(master) if master else None
    projected_rows = None
    if master_table is not None:
        meta_table = read_table(metadata)
        _, projected_rows, stats = preview(master_table, meta_table, source, workflow=workflow)
        result['merge_preview'] = stats
    qc = build_report(report, master_rows=projected_rows, workflow=workflow)
    result['qc_context'] = 'previewed master' if projected_rows is not None else 'run only'
    result['qc_counts'] = qc['counts']
    if fasta:
        records, duplicates = read_fasta(fasta)
        if not records or duplicates:
            raise ValueError('Run FASTA must contain records with unique IDs')
        result['fasta_records'] = len(records)
    if lab:
        result['lab_codes'] = len(lab_lookup(lab))
    if reviews:
        result['approval_counts'] = approval(master)['counts']
    if shutil.which('bash'):
        for wrapper in ('sarsseq_wrapper.sh', 'sarsseq_fasta_wrapper.sh', 'master_csv/wrapper_integration.sh'):
            subprocess.run(['bash', '-n', str(ROOT / 'sarsseq' / wrapper)], check=True, capture_output=True, text=True)
        result['wrapper_syntax'] = 'passed'
    else:
        result['wrapper_syntax'] = 'not checked: bash is unavailable on this host'
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--workflow', required=True, choices=['fastq', 'fasta'])
    parser.add_argument('--master', type=Path)
    parser.add_argument('--metadata', type=Path)
    parser.add_argument('--fasta', type=Path, help='Optional completed run FASTA to parse')
    parser.add_argument('--lab', type=Path, help='Optional Innsender_GISAID.csv to validate')
    parser.add_argument('--reviews', action='store_true', help='Also validate the current solution approval store')
    args = parser.parse_args()
    try:
        print(json.dumps(validate(**vars(args)), sort_keys=True))
    except (OSError, ValueError, csv.Error, subprocess.SubprocessError) as error:
        parser.exit(1, f'SC2 deployment validation failed: {error}\n')


if __name__ == '__main__':
    main()
