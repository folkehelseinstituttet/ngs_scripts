#!/usr/bin/env python3
"""Run Nextclade as a standalone alignment and reporting stage.

This runner deliberately has no IQ-TREE, TreeTime, or metadata integration.
"""

from __future__ import annotations

import argparse
import csv
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


OUTPUT_NAMES = {
    "aligned_nucleotide": "aligned_nucleotide.fasta",
    "translated_amino_acid": "translated_amino_acid.fasta",
    "results_tsv": "nextclade_results.tsv",
    "results_json": "nextclade_results.json",
    "insertions": "insertions.tsv",
    "qc": "qc.tsv",
    "nucleotide_mutations": "nucleotide_mutations.tsv",
    "amino_acid_mutations": "amino_acid_mutations.tsv",
    "log": "nextclade.log",
    "metadata": "run_metadata.tsv",
}


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--fasta", type=Path, required=True)
    p.add_argument("--outdir", type=Path, required=True)
    p.add_argument("--nextclade-dataset")
    p.add_argument("--nextclade-dataset-tag")
    p.add_argument("--nextclade-reference", type=Path)
    p.add_argument("--nextclade-annotation", type=Path)
    p.add_argument("--nextclade-pathogen-json", type=Path)
    p.add_argument("--influenza-type")
    p.add_argument("--segment")
    p.add_argument("--include-failed", action="store_true")
    p.add_argument("--nextclade-bin", default="nextclade")
    return p


def require_file(path: Path, label: str) -> None:
    if not path.is_file() or not path.stat().st_size:
        raise SystemExit(f"{label} not found or empty: {path}")


def validate_args(args: argparse.Namespace) -> None:
    require_file(args.fasta, "Input FASTA")
    if args.nextclade_dataset and (args.nextclade_reference or args.nextclade_annotation):
        raise SystemExit("Use either --nextclade-dataset or custom reference/annotation mode.")
    if args.nextclade_dataset_tag and not args.nextclade_dataset:
        raise SystemExit("--nextclade-dataset-tag requires --nextclade-dataset.")
    if args.nextclade_dataset:
        if args.nextclade_pathogen_json:
            raise SystemExit("--nextclade-pathogen-json is only valid in custom reference mode.")
    elif not (args.nextclade_reference and args.nextclade_annotation):
        raise SystemExit(
            "Provide --nextclade-dataset or both --nextclade-reference and --nextclade-annotation."
        )
    else:
        require_file(args.nextclade_reference, "Nextclade reference FASTA")
        require_file(args.nextclade_annotation, "Nextclade annotation")
        if args.nextclade_pathogen_json:
            require_file(args.nextclade_pathogen_json, "Nextclade pathogen JSON")


def read_fasta_names(path: Path) -> list[str]:
    names = []
    seen = set()
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if raw.startswith(">"):
            name = raw[1:].strip()
            if not name:
                raise SystemExit(f"Empty FASTA header in {path}")
            if name in seen:
                raise SystemExit(f"Duplicate FASTA header: {name}")
            seen.add(name)
            names.append(name)
    if not names:
        raise SystemExit(f"No FASTA records found: {path}")
    return names


def count_fasta_records(path: Path) -> int:
    return sum(1 for line in path.read_text(encoding="utf-8-sig").splitlines() if line.startswith(">"))


def nextclade_version(binary: str) -> str:
    completed = subprocess.run(
        [binary, "--version"],
        capture_output=True,
        text=True,
    )
    if completed.returncode:
        raise SystemExit(f"Unable to determine Nextclade version using {binary!r}.")
    version = (completed.stdout or completed.stderr).strip()
    if not version:
        raise SystemExit(f"Nextclade version command produced no output: {binary}")
    return version.splitlines()[0]


def require_output(path: Path, label: str) -> Path:
    if not path.is_file() or not path.stat().st_size:
        raise SystemExit(f"Nextclade did not produce the required output: {label}: {path}")
    return path


def combine_translation_fastas(raw_dir: Path, target: Path) -> int:
    """Combine one Nextclade translation FASTA per CDS in stable order."""

    translation_files = sorted(
        (
            path
            for path in raw_dir.glob("nextclade.cds_translation.*.fasta")
            if path.is_file() and path.stat().st_size
        ),
        key=lambda path: path.name,
    )
    if not translation_files:
        raise SystemExit("Nextclade did not produce any translated amino-acid FASTA files.")

    with target.open("w", encoding="utf-8") as output:
        for translation in translation_files:
            content = translation.read_text(encoding="utf-8-sig")
            output.write(content)
            if content and not content.endswith("\n"):
                output.write("\n")
    return len(translation_files)


def clear_expected_outputs(raw_dir: Path) -> None:
    """Remove outputs from an earlier run before writing the fixed selection."""

    patterns = (
        "nextclade.aligned.fasta",
        "nextclade.tsv",
        "nextclade.json",
        "nextclade.cds_translation.*.fasta",
    )
    for pattern in patterns:
        for path in raw_dir.glob(pattern):
            if path.is_file():
                path.unlink()


def write_column_extract(source: Path, target: Path, candidates: tuple[str, ...]) -> None:
    with source.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        headers = reader.fieldnames or []
        if "seqName" not in headers:
            raise SystemExit(f"Nextclade TSV does not contain seqName: {source}")
        selected = []
        for candidate in candidates:
            selected.extend(
                header
                for header in headers
                if header.lower() == candidate.lower() and header not in selected
            )
        if not selected:
            target.write_text("seqName\n", encoding="utf-8")
            return
        with target.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=["seqName", *selected], delimiter="\t")
            writer.writeheader()
            for row in reader:
                writer.writerow({key: row.get(key, "") for key in writer.fieldnames})


def read_tsv_summary(path: Path) -> tuple[list[str], int]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return reader.fieldnames or [], sum(1 for _ in reader)


def run_logged(command: list[str], log_path: Path, log, label: str) -> str:
    rendered = shlex.join(command)
    log.write(f"{label}\t{rendered}\n")
    log.flush()
    completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True)
    if completed.returncode:
        raise SystemExit(f"Nextclade failed with exit code {completed.returncode}; see {log_path}")
    return rendered


def main() -> int:
    args = parser().parse_args()
    validate_args(args)
    input_names = read_fasta_names(args.fasta)
    args.outdir.mkdir(parents=True, exist_ok=True)
    raw_dir = args.outdir / ".nextclade_raw"
    raw_dir.mkdir(exist_ok=True)
    clear_expected_outputs(raw_dir)

    version = nextclade_version(args.nextclade_bin)
    dataset_mode = "custom-reference"
    resolved_dataset = ""
    dataset_command = ""
    run_command = ""
    log_path = args.outdir / OUTPUT_NAMES["log"]
    with log_path.open("w", encoding="utf-8") as log:
        dataset_arg = []
        if args.nextclade_dataset:
            dataset_path = Path(args.nextclade_dataset)
            if dataset_path.exists():
                dataset_mode = "local"
                resolved_dataset = str(dataset_path)
                if args.nextclade_dataset_tag:
                    raise SystemExit(
                        "--nextclade-dataset-tag is only valid when --nextclade-dataset is a dataset name."
                    )
                dataset_arg = ["--input-dataset", str(dataset_path)]
            elif args.nextclade_dataset_tag:
                # ``nextclade run`` has no dataset-tag flag in 3.21.2. Download
                # the requested tagged dataset first, then pass its directory.
                dataset_mode = "remote-tagged"
                downloaded_dataset = raw_dir / "dataset"
                if downloaded_dataset.exists():
                    shutil.rmtree(downloaded_dataset)
                download = [
                    args.nextclade_bin,
                    "dataset",
                    "get",
                    "--name",
                    args.nextclade_dataset,
                    "--tag",
                    args.nextclade_dataset_tag,
                    "--output-dir",
                    str(downloaded_dataset),
                ]
                dataset_command = run_logged(download, log_path, log, "dataset")
                resolved_dataset = str(downloaded_dataset)
                dataset_arg = ["--input-dataset", str(downloaded_dataset)]
            else:
                dataset_mode = "remote"
                resolved_dataset = args.nextclade_dataset
                dataset_arg = ["--dataset-name", args.nextclade_dataset]

        command = [
            args.nextclade_bin,
            "run",
            "--output-all",
            str(raw_dir),
            "--output-basename",
            "nextclade",
            "--output-selection",
            "fasta,json,tsv,translations",
            "--in-order",
            "true",
            *dataset_arg,
        ]
        if not args.nextclade_dataset:
            command += [
                "--input-ref",
                str(args.nextclade_reference),
                "--input-annotation",
                str(args.nextclade_annotation),
            ]
            if args.nextclade_pathogen_json:
                command += ["--input-pathogen-json", str(args.nextclade_pathogen_json)]
        command.append(str(args.fasta))
        run_command = run_logged(command, log_path, log, "run")

    aligned = require_output(raw_dir / "nextclade.aligned.fasta", "aligned FASTA")
    results_tsv = require_output(raw_dir / "nextclade.tsv", "results TSV")
    results_json = require_output(raw_dir / "nextclade.json", "results JSON")
    shutil.copyfile(aligned, args.outdir / OUTPUT_NAMES["aligned_nucleotide"])
    shutil.copyfile(results_tsv, args.outdir / OUTPUT_NAMES["results_tsv"])
    shutil.copyfile(results_json, args.outdir / OUTPUT_NAMES["results_json"])
    translation_file_count = combine_translation_fastas(
        raw_dir, args.outdir / OUTPUT_NAMES["translated_amino_acid"]
    )

    headers, result_row_count = read_tsv_summary(results_tsv)
    write_column_extract(
        results_tsv,
        args.outdir / OUTPUT_NAMES["insertions"],
        ("insertions", "aaInsertions"),
    )
    write_column_extract(
        results_tsv,
        args.outdir / OUTPUT_NAMES["qc"],
        tuple(header for header in headers if header.startswith("qc."))
        + ("warnings", "errors", "failedCdses"),
    )
    write_column_extract(
        results_tsv,
        args.outdir / OUTPUT_NAMES["nucleotide_mutations"],
        (
            "substitutions",
            "deletions",
            "insertions",
            "privateNucMutations.labeledSubstitutions",
            "privateNucMutations.unlabeledSubstitutions",
        ),
    )
    write_column_extract(
        results_tsv,
        args.outdir / OUTPUT_NAMES["amino_acid_mutations"],
        (
            "aaSubstitutions",
            "aaDeletions",
            "aaInsertions",
            "privateAaMutations.labeledSubstitutions",
            "privateAaMutations.unlabeledSubstitutions",
        ),
    )

    metadata = {
        "command": run_command,
        "dataset_command": dataset_command,
        "nextclade_version": version,
        "dataset_mode": dataset_mode,
        "nextclade_dataset": args.nextclade_dataset or "",
        "nextclade_dataset_tag": args.nextclade_dataset_tag or "",
        "resolved_dataset": resolved_dataset,
        "input_fasta": str(args.fasta),
        "outdir": str(args.outdir),
        "raw_output_dir": str(raw_dir),
        "nextclade_reference": str(args.nextclade_reference or ""),
        "nextclade_annotation": str(args.nextclade_annotation or ""),
        "nextclade_pathogen_json": str(args.nextclade_pathogen_json or ""),
        "nextclade_bin": args.nextclade_bin,
        "output_selection": "fasta,json,tsv,translations",
        "in_order": "true",
        "influenza_type": args.influenza_type or "",
        "segment": args.segment or "",
        "include_failed": str(args.include_failed).lower(),
        "input_sequence_count": str(len(input_names)),
        "aligned_sequence_count": str(count_fasta_records(aligned)),
        "result_row_count": str(result_row_count),
        "translation_file_count": str(translation_file_count),
    }
    metadata["translation_record_count"] = str(count_fasta_records(args.outdir / OUTPUT_NAMES["translated_amino_acid"]))
    metadata["failed_or_omitted_sequence_count"] = str(max(0, len(input_names) - result_row_count))
    with (args.outdir / OUTPUT_NAMES["metadata"]).open("w", encoding="utf-8") as handle:
        for key, value in metadata.items():
            handle.write(f"{key}\t{value}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
