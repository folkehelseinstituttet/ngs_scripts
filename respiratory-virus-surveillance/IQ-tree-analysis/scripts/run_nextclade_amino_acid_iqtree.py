#!/usr/bin/env python3
"""Build one amino-acid IQ-TREE for every Nextclade CDS translation."""

from __future__ import annotations

import argparse
import csv
import shlex
import subprocess
from pathlib import Path


TRANSLATION_PREFIX = "nextclade.cds_translation."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nextclade-dir", type=Path, required=True)
    parser.add_argument("--accepted-aligned-fasta", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, required=True)
    parser.add_argument("--iqtree-bin", default="iqtree")
    return parser.parse_args()


def fasta_records(path: Path) -> list[tuple[str, str]]:
    records: list[tuple[str, str]] = []
    header: str | None = None
    sequence: list[str] = []
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        if raw.startswith(">"):
            if header is not None:
                records.append((header, "".join(sequence)))
            header = raw[1:].strip()
            sequence = []
        elif raw.strip():
            sequence.append(raw.strip())
    if header is not None:
        records.append((header, "".join(sequence)))
    if not records:
        raise SystemExit(f"No FASTA records found: {path}")
    names = [name for name, _ in records]
    if len(names) != len(set(names)):
        raise SystemExit(f"Duplicate FASTA identifiers found: {path}")
    if any(not name for name in names):
        raise SystemExit(f"Empty FASTA identifier found: {path}")
    return records


def write_fasta(path: Path, records: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for name, sequence in records:
            handle.write(f">{name}\n{sequence}\n")


def iqtree_version(binary: str) -> str:
    completed = subprocess.run([binary, "-version"], capture_output=True, text=True)
    output = (completed.stdout or completed.stderr).strip()
    if completed.returncode or not output:
        raise SystemExit(f"Unable to determine IQ-TREE version using {binary!r}.")
    return output.splitlines()[0]


def main() -> int:
    args = parse_args()
    raw_dir = args.nextclade_dir / ".nextclade_raw"
    accepted = fasta_records(args.accepted_aligned_fasta)
    accepted_ids = [name for name, _ in accepted]
    accepted_set = set(accepted_ids)
    translation_files = sorted(raw_dir.glob(f"{TRANSLATION_PREFIX}*.fasta"), key=lambda p: p.name)
    if not translation_files:
        raise SystemExit(f"No Nextclade CDS translation FASTAs found: {raw_dir}")

    version = iqtree_version(args.iqtree_bin)
    summary_rows: list[dict[str, str]] = []
    for translation_path in translation_files:
        cds = translation_path.name[len(TRANSLATION_PREFIX) : -len(".fasta")]
        if not cds or "/" in cds or "\\" in cds:
            raise SystemExit(f"Invalid CDS name in translation filename: {translation_path.name}")
        translation_records = fasta_records(translation_path)
        translation_by_id = dict(translation_records)
        missing = sorted(accepted_set - set(translation_by_id))
        if missing:
            raise SystemExit(
                f"CDS {cds} translation is missing {len(missing)} accepted sequence(s): "
                + ", ".join(missing[:10])
            )
        selected = [(name, translation_by_id[name]) for name in accepted_ids]
        lengths = {len(sequence) for _, sequence in selected}
        if len(lengths) != 1:
            raise SystemExit(f"CDS {cds} translation alignment has inconsistent lengths: {sorted(lengths)}")
        unique_count = len({sequence for _, sequence in selected})

        cds_dir = args.outdir / cds
        alignment = cds_dir / f"{cds}.amino_acid.aligned.fasta"
        write_fasta(alignment, selected)
        prefix = cds_dir / f"{cds}.amino_acid"
        command = [
            args.iqtree_bin,
            "-s",
            str(alignment),
            "-m",
            "MFP",
            "-nt",
            "AUTO",
            "-pre",
            str(prefix),
            "-redo",
        ]
        # IQ-TREE cannot bootstrap an alignment with fewer than four unique
        # sequences. Still emit an ML tree for low-diversity CDS and record
        # that support values were intentionally omitted.
        support_mode = "alrt1000_bootstrap1000"
        if unique_count >= 4:
            insertion_index = command.index("-nt")
            command[insertion_index:insertion_index] = ["-alrt", "1000", "-B", "1000"]
        else:
            support_mode = "none_low_unique_count"
        run_log = cds_dir / f"{cds}.amino_acid.run.log"
        with run_log.open("w", encoding="utf-8") as log:
            log.write("command\t" + shlex.join(command) + "\n")
            log.write("iqtree_version\t" + version + "\n")
            log.write("sequence_count\t" + str(len(selected)) + "\n")
            log.write("unique_sequence_count\t" + str(unique_count) + "\n")
            log.write("support_mode\t" + support_mode + "\n")
            log.flush()
            completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True)
        treefile = Path(str(prefix) + ".treefile")
        if completed.returncode or not treefile.is_file() or not treefile.stat().st_size:
            raise SystemExit(f"Amino-acid IQ-TREE failed for CDS {cds}; see {run_log}")
        summary_rows.append(
            {
                "cds": cds,
                "source_translation": str(translation_path),
                "alignment": str(alignment),
                "treefile": str(treefile),
                "command": shlex.join(command),
                "iqtree_version": version,
                "sequence_count": str(len(selected)),
                "unique_sequence_count": str(unique_count),
                "alignment_length": str(next(iter(lengths))),
                "support_mode": support_mode,
            }
        )

    summary = args.outdir / "amino_acid_tree_summary.tsv"
    summary.parent.mkdir(parents=True, exist_ok=True)
    with summary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(summary_rows[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(summary_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
