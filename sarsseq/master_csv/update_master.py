#!/usr/bin/env python3
"""Update the SC2 master CSV using the shared locked and verified file transaction."""

import argparse
import csv
import json
import os
from pathlib import Path
import posixpath
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
from preview_merge import preview
import update_master_csv as storage
from merge_master_csv import MergeError, read_table

MASTER_SHARE = storage.MASTER_SHARE
MASTER_DIR = (
    'Virologi/NGS/1-NGS-Analyser/2-Utvikling/'
    'Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/SC2'
)
METADATA_NAME = 'NGS_PREP_SC2_report.csv'


def configuration(environ, validation=''):
    config, reason = storage.configuration(
        environ, validation, prefix='SARSSEQ', master_share=MASTER_SHARE,
        master_directory=MASTER_DIR, metadata_name=METADATA_NAME,
    )
    if config is None:
        return config, reason
    if config['master'] and config['metadata']:
        if os.path.samefile(config['master'], config['metadata']):
            raise MergeError('Master and metadata must be separate files')
    elif not config['master'] and not config['metadata']:
        def remote_path(kind):
            remote = config[kind + '_smb']
            return (remote.share.rstrip('/').casefold(),
                    posixpath.normpath((remote.directory + '/' + config[kind + '_name'])
                                       .replace('\\', '/')).casefold())

        if remote_path('master') == remote_path('metadata'):
            raise MergeError('Master and metadata must be separate SMB files')
    return config, reason


def merge_tables(master, metadata, report, workflow, assets=None, nonempty_report=False):
    """Adapt the SARS schema to the shared transaction's merger interface.

    ``assets`` belongs to the Influenza interface; SARS uses its own schema.
    """
    return preview(master, metadata, report, workflow=workflow, nonempty_report=nonempty_report)


def update(config, report, workflow, fasta=None, *, qc_output=None, qc_options=None):
    if qc_output:
        from sars_qc_report import build_report, validate_output
        validate_output(qc_output, (report, fasta, config['master'], config['metadata'],
                                   Path(config['master']).with_name('master.fasta') if config['master'] else None))
        # Catch malformed report data/options before changing either master file.
        build_report(report, workflow=workflow, **(qc_options or {}))
    stats = storage.update(config, report, workflow, fasta=fasta, table_merger=merge_tables)
    if qc_output:
        from sars_qc_report import write_report
        with tempfile.TemporaryDirectory(prefix='sarsseq-qc-master-') as directory:
            master = config['master']
            if master is None:
                master = Path(directory) / 'master.csv'
                config['master_smb'].get(config['master_name'], master)
            write_report(report, qc_output, master, workflow,
                         master_label=Path(config['master']).name if config['master'] else config['master_name'],
                         **(qc_options or {}))
        stats['qc_html'] = str(qc_output)
        stats['qc_json'] = str(Path(qc_output).with_suffix('.json'))
    return stats


def check_access(config):
    """Download/read both CSVs without locks or writes to their source locations."""
    result = {}
    with tempfile.TemporaryDirectory(prefix='sarsseq-access-') as directory:
        for kind in ('master', 'metadata'):
            path = config[kind]
            if path is None:
                path = Path(directory) / (kind + '.csv')
                config[kind + '_smb'].get(config[kind + '_name'], path)
            headers, rows = read_table(path)
            result[kind] = {'columns': len(headers), 'rows': len(rows)}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, help='Exactly one final run report CSV')
    parser.add_argument('--fasta', type=Path, help="Merge this run's multi-FASTA into master.fasta beside master.csv")
    parser.add_argument('--workflow', choices=('fastq', 'fasta'), required=True)
    parser.add_argument('--validation', default='')
    parser.add_argument('--qc-output', type=Path, help='Generate local SARS QC HTML and companion JSON after updating')
    parser.add_argument('--qc-coverage-threshold', type=float, default=80)
    parser.add_argument('--qc-cds-threshold', type=float, default=80)
    parser.add_argument('--qc-mixed-threshold', type=int, default=3)
    parser.add_argument('--qc-smb-share', help='Upload and verify the generated QC files on this SMB share')
    parser.add_argument('--qc-smb-dir', help='Existing destination directory for QC files')
    parser.add_argument('--qc-smb-auth', default='/home/ngs/.smbcreds')
    checks = parser.add_mutually_exclusive_group()
    checks.add_argument('--check-config', action='store_true', help='Check local paths, SMB client and credential-file availability')
    checks.add_argument('--check-access', action='store_true', help='Read and parse both CSVs without updating either source')
    args = parser.parse_args()
    try:
        if (args.qc_smb_share or args.qc_smb_dir) and not (args.qc_output and args.qc_smb_share and args.qc_smb_dir):
            raise MergeError('QC upload requires --qc-output, --qc-smb-share and --qc-smb-dir')
        qc_remote = storage.SMB(args.qc_smb_share, args.qc_smb_dir, args.qc_smb_auth) if args.qc_smb_share else None
        qc_options = dict(coverage_threshold=args.qc_coverage_threshold, cds_threshold=args.qc_cds_threshold,
                          mixed_threshold=args.qc_mixed_threshold)
        if args.qc_output:
            from sars_qc_report import validate_output
            from sars_qc_metrics import thresholds
            thresholds(**qc_options)
            validate_output(args.qc_output, (args.report, args.fasta))
        config, reason = configuration(os.environ, args.validation)
        if config is None:
            if args.check_access:
                raise MergeError(f'Access check needs enabled input locations: {reason}')
            print(f'Master CSV update skipped: {reason}')
            if args.qc_output and not args.check_config:
                if args.report is None or not args.report.is_file():
                    raise MergeError('Final report CSV is missing')
                from sars_qc_report import write_report
                write_report(args.report, args.qc_output, workflow=args.workflow, **qc_options)
                print(f'SARS QC report created without master comparison: {args.qc_output}')
        elif args.check_config:
            print('SC2 master CSV configuration valid; remote access has not been checked')
        elif args.check_access:
            print('SC2 CSV read access verified: ' + json.dumps(check_access(config), sort_keys=True))
        elif args.report is None or not args.report.is_file():
            raise MergeError('Final report CSV is missing')
        else:
            print('SC2 master update: ' + json.dumps(update(config, args.report, args.workflow, args.fasta,
                                                          qc_output=args.qc_output, qc_options=qc_options), sort_keys=True))
        if qc_remote is not None and not (args.check_config or args.check_access):
            # Match Influenza: read back and hash each file before allowing cleanup.
            # Keep the local pair on any failure so publishing can be retried.
            with tempfile.TemporaryDirectory(prefix='sarsseq-qc-upload-') as directory:
                for path in (args.qc_output, args.qc_output.with_suffix('.json')):
                    qc_remote.put_verified(path, path.name, Path(directory) / 'check')
            print('SARS QC HTML and JSON uploaded and verified')
    except (OSError, ValueError, csv.Error, ET.ParseError, subprocess.SubprocessError) as error:
        parser.exit(1, f'SC2 master CSV update or QC generation/publishing failed: {error}\n')


if __name__ == '__main__':
    main()
