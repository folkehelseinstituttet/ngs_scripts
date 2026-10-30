#!/usr/bin/env python3
"""Wrapper entry point for merging into a mounted or SMB-hosted master CSV."""

import argparse
from contextlib import contextmanager
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from merge_master_csv import (
    MergeError, backup_suffix, digest, merge_files, merge_tables, read_table, write_table,
)


MASTER_SHARE = "//pos1-fhi-svm01.fhi.no/styrt"
MASTER_DIR = (
    "Virologi/NGS/1-NGS-Analyser/2-Utvikling/"
    "Seksjons for Influensa og andre luftveisvirus - NGS analysis database/data/INF"
)


def smb_quote(value):
    value = str(value)
    # smbclient has its own command language, even with subprocess(shell=False).
    if not value or any(character in value for character in '\n\r\x00";*?'):
        raise MergeError("Unsupported character in SMB path")
    return '"' + value + '"'


class SMBError(MergeError):
    def __init__(self, verb, statuses, returncode):
        self.statuses = statuses
        super().__init__(f"SMB {verb} failed ({', '.join(statuses) or 'exit ' + str(returncode)})")


class SMB:
    def __init__(self, share, directory, auth):
        if not share.startswith("//"):
            raise MergeError("SMB share must be a UNC share such as //server/share")
        self.share, self.directory, self.auth = share, directory, auth

    def command(self, verb, *arguments):
        command = verb + " " + " ".join(smb_quote(value) for value in arguments)
        result = subprocess.run(
            ["smbclient", self.share, "-A", self.auth, "-D", self.directory, "-c", command],
            capture_output=True, text=True, timeout=300,
        )
        statuses = re.findall(r"(?:NT_STATUS|DOS_STATUS)_[A-Z0-9_]+", result.stdout + result.stderr)
        if result.returncode or statuses:
            # Avoid including downloaded identifiers, credentials or server listings in logs.
            raise SMBError(verb, statuses, result.returncode)

    def get(self, remote, local):
        self.command("get", remote, local)
        if not Path(local).is_file():
            raise MergeError("SMB get did not create the requested local file")

    def get_if_exists(self, remote, local):
        try:
            self.get(remote, local)
        except SMBError as error:
            # Only this exact status permits initializing a new FASTA. A missing
            # directory, access denial or network failure is never an empty master.
            if error.statuses and set(error.statuses) == {"NT_STATUS_OBJECT_NAME_NOT_FOUND"}:
                return False
            raise
        return True

    def put_verified(self, local, remote, check):
        self.command("put", local, remote)
        self.get(remote, check)
        if digest(local) != digest(check):
            raise MergeError("SMB upload verification failed")

    @contextmanager
    def lock(self, name):
        # mkdir is exclusive across all machines accessing the same share.
        self.command("mkdir", name)
        try:
            yield
        finally:
            self.command("rmdir", name)


def configuration(environ, validation=""):
    mode = environ.get("FLUSEQ_MASTER_UPDATE", "auto").lower()
    if mode not in {"auto", "true", "false"}:
        raise MergeError("FLUSEQ_MASTER_UPDATE must be auto, true, or false")
    if validation:
        return None, "validation run"
    if mode == "false":
        return None, "FLUSEQ_MASTER_UPDATE=false"
    configured = any(environ.get(name) for name in (
        "FLUSEQ_MASTER_CSV", "FLUSEQ_METADATA_CSV", "FLUSEQ_METADATA_SMB_SHARE",
        "FLUSEQ_MASTER_SMB_SHARE", "FLUSEQ_MASTER_SMB_DIR",
    ))
    if mode == "auto" and not configured:
        return None, "set FLUSEQ_MASTER_UPDATE=true to use the default shared directory (see master_csv/README.md)"
    nonempty = environ.get("FLUSEQ_MASTER_NONEMPTY_REPORT", "false").lower()
    if nonempty not in {"true", "false"}:
        raise MergeError("FLUSEQ_MASTER_NONEMPTY_REPORT must be true or false")
    master_name = environ.get("FLUSEQ_MASTER_SMB_NAME", "master.csv")
    metadata_name = environ.get("FLUSEQ_METADATA_SMB_NAME", "NGS_PREP_INF_report.csv")
    for name in (master_name, metadata_name):
        smb_quote(name)
        if "/" in name or "\\" in name or name in {".", ".."}:
            raise MergeError("SMB_NAME must be a filename; configure its directory separately")
    master = environ.get("FLUSEQ_MASTER_CSV") or None
    master_share = environ.get("FLUSEQ_MASTER_SMB_SHARE", MASTER_SHARE)
    master_directory = environ.get("FLUSEQ_MASTER_SMB_DIR", MASTER_DIR)
    metadata = environ.get("FLUSEQ_METADATA_CSV") or None
    metadata_share = environ.get("FLUSEQ_METADATA_SMB_SHARE") or None
    # Until a separate export location is configured, read metadata beside the master.
    if master and not metadata and not metadata_share:
        metadata = str(Path(master).with_name(metadata_name))
    auth = environ.get("FLUSEQ_MASTER_SMB_AUTH", "/home/ngs/.smbcreds")
    metadata_auth = environ.get("FLUSEQ_METADATA_SMB_AUTH", auth)
    for label, path in (("master", master), ("metadata", metadata)):
        if path and not Path(path).is_file():
            raise MergeError(f"Configured {label} CSV does not exist: {path}")
    if not master or not metadata:
        if not shutil.which("smbclient"):
            raise MergeError("smbclient is required for SMB paths")
        for needed, path in ((not master, auth), (not metadata, metadata_auth)):
            if needed and not Path(path).is_file():
                raise MergeError(f"SMB authentication file does not exist: {path}")
    config = {
        "master": master,
        "metadata": metadata,
        "master_smb": None if master else SMB(
            master_share, master_directory, auth,
        ),
        "metadata_smb": None if metadata else SMB(
            metadata_share or master_share,
            environ.get("FLUSEQ_METADATA_SMB_DIR", master_directory), metadata_auth,
        ),
        "master_name": master_name,
        "metadata_name": metadata_name,
        "nonempty_report": nonempty == "true",
    }
    return config, None


def update(config, report, workflow, qc_output=None, qc_options=None, fasta=None):
    if fasta:
        from merge_master_fasta import prepare_fasta
        fasta_records = prepare_fasta(config, fasta)  # Validate and snapshot before changing the CSV.

    def finish(stats, master):
        if fasta:
            from merge_master_fasta import update_fasta
            stats["fasta"] = update_fasta(config, fasta_records)
        if qc_output:
            from report_qc_html import write_report
            write_report(Path(report), qc_output, master, workflow,
                         master_label=Path(config["master"]).name if config["master"] else config["master_name"],
                         **(qc_options or {}))
            stats["qc_html"] = str(qc_output)
        return stats

    with tempfile.TemporaryDirectory(prefix="fluseq-master-") as directory:
        directory = Path(directory)
        metadata = config["metadata"]
        if metadata is None:
            metadata = directory / "metadata.csv"
            config["metadata_smb"].get(config["metadata_name"], metadata)
        if config["master"] is not None:
            stats = merge_files(
                config["master"], metadata, report, workflow, nonempty_report=config["nonempty_report"],
            )
            return finish(stats, config["master"])
        remote, name = config["master_smb"], config["master_name"]
        with remote.lock(name + ".lock"):
            original = directory / "original.csv"
            remote.get(name, original)  # A missing/inaccessible master is never treated as an empty database.
            headers, rows, stats = merge_tables(
                read_table(original), read_table(metadata), read_table(report), workflow,
                nonempty_report=config["nonempty_report"],
            )
            candidate = directory / "candidate.csv"
            write_table(candidate, headers, rows)
            if digest(original) == digest(candidate):
                return finish(dict(stats, written=False), original)
            suffix = backup_suffix()
            backup = name + ".bak." + suffix
            staged = name + ".tmp." + suffix
            check = directory / "check.csv"
            # Verify both backup and candidate before changing the visible master.
            remote.put_verified(original, backup, check)
            remote.put_verified(candidate, staged, check)
            remote.get(name, check)
            if digest(check) != digest(original):
                raise MergeError("Remote master changed during merge; refusing to replace it")
            # SMB rename -f replaces the target on the server without delete/upload gaps.
            remote.command("rename", staged, name, "-f")
            remote.get(name, check)
            if digest(check) != digest(candidate):
                raise MergeError(f"Remote master verification failed; backup is {backup}")
            return finish(dict(stats, written=True, backup=backup), candidate)


def check_identifiers(config, report=None, output=None, workflow="fastq"):
    from diagnose_master_ids import find_conflicts, write_conflicts

    if output:
        protected = {Path(path).resolve() for path in (config["master"], config["metadata"], report) if path}
        if Path(output).resolve() in protected:
            raise MergeError("Identifier report must be separate from master, metadata and run report")
    with tempfile.TemporaryDirectory(prefix="fluseq-identifier-audit-") as directory:
        paths = {}
        for kind in ("master", "metadata"):
            paths[kind] = config[kind]
            if paths[kind] is None:
                paths[kind] = Path(directory) / (kind + ".csv")
                config[kind + "_smb"].get(config[kind + "_name"], paths[kind])
        conflicts = find_conflicts(read_table(paths["master"]), read_table(paths["metadata"]),
                                   read_table(report) if report else None, workflow)
        if output:
            write_conflicts(output, conflicts)
    return conflicts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--fasta", type=Path, help="Merge this run's multi-FASTA into master.fasta beside master.csv")
    parser.add_argument("--workflow", required=True, choices=("fastq", "fasta"))
    parser.add_argument("--validation", default="")
    parser.add_argument("--check-config", action="store_true", help="Validate local configuration before starting analysis")
    parser.add_argument("--check-identifiers", action="store_true", help="Read-only audit of conflicting sequencing identifiers")
    parser.add_argument("--identifier-report", type=Path, help="Write identifier conflict details to this local CSV")
    parser.add_argument("--qc-output", type=Path, help="Write an offline HTML QC report and companion JSON after merging")
    parser.add_argument("--qc-coverage-threshold", type=float, default=80)
    parser.add_argument("--qc-smb-share", help="Upload and verify the generated QC files on this SMB share")
    parser.add_argument("--qc-smb-dir", help="Existing destination directory for QC files")
    parser.add_argument("--qc-smb-auth", default="/home/ngs/.smbcreds")
    args = parser.parse_args()
    try:
        if args.identifier_report and not args.check_identifiers:
            raise MergeError("--identifier-report requires --check-identifiers")
        if args.check_identifiers and (args.check_config or args.fasta or args.qc_output or args.qc_smb_share or args.qc_smb_dir):
            raise MergeError("Run --check-identifiers separately from configuration checks and QC generation/uploads")
        if (args.qc_smb_share or args.qc_smb_dir) and not (args.qc_output and args.qc_smb_share and args.qc_smb_dir):
            raise MergeError("QC upload requires --qc-output, --qc-smb-share and --qc-smb-dir")
        if args.qc_output:
            if not 0 < args.qc_coverage_threshold <= 100:
                raise MergeError("QC coverage threshold must be greater than 0 and at most 100")
            if args.qc_output.suffix.lower() != ".html":
                raise MergeError("QC output must use an .html filename")
        config, reason = configuration(os.environ, args.validation)
        if args.check_identifiers:
            if config is None:
                raise MergeError(f"Identifier check needs configured input paths: {reason}; set FLUSEQ_MASTER_UPDATE=true")
            conflicts = check_identifiers(config, args.report, args.identifier_report, args.workflow)
            sequences = {row["Sequence_ID"] for row in conflicts}
            relevant = {row["Sequence_ID"] for row in conflicts if row["in_current_report"] == "yes"}
            print(f"Identifier check: {len(sequences)} conflicting sequencing IDs (NGS_LW_ID/Sequence_ID). Master and metadata were not changed.")
            if args.report:
                print(f"Conflicting identifiers involving this report: {len(relevant)}")
            if args.identifier_report:
                print(f"Identifier details saved to: {args.identifier_report}")
            else:
                for row in conflicts:
                    print(f"  {row['source']} record {row['record']}: {row['conflict']}")
                if conflicts:
                    print("Use --identifier-report /path/to/conflicts.csv to save the identifiers and keys privately.")
            parser.exit(2 if conflicts else 0)
        if config is None:
            print(f"Master CSV update skipped: {reason}")
            if args.qc_output and not args.check_config:
                if args.report is None or not args.report.is_file():
                    raise MergeError("Final report CSV is missing")
                from report_qc_html import write_report
                write_report(args.report, args.qc_output, workflow=args.workflow,
                             coverage_threshold=args.qc_coverage_threshold)
                print(f"QC report created without master comparison: {args.qc_output}")
        elif args.check_config:
            print("Master CSV update configured; shared-file access will be checked at merge time")
        elif args.report is None or not args.report.is_file():
            raise MergeError("Final report CSV is missing")
        else:
            print("Master CSV update: " + json.dumps(update(
                config, args.report, args.workflow, args.qc_output,
                {"coverage_threshold": args.qc_coverage_threshold}, args.fasta,
            ), sort_keys=True))
        if args.qc_smb_share and not args.check_config:
            remote = SMB(args.qc_smb_share, args.qc_smb_dir, args.qc_smb_auth)
            with tempfile.TemporaryDirectory(prefix="fluseq-qc-upload-") as directory:
                for path in (args.qc_output, args.qc_output.with_suffix(".json")):
                    remote.put_verified(path, path.name, Path(directory) / "check")
            print("QC HTML and JSON uploaded and verified")
    except (OSError, ValueError, csv.Error, ET.ParseError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Master CSV update failed: {error}\n")


if __name__ == "__main__":
    main()
