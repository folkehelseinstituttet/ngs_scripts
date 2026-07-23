#!/usr/bin/env python3
"""Add amino-acid branch mutations to a TreeTime Auspice JSON."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

CODE = {
    "TTT": "F", "TTC": "F", "TTA": "L", "TTG": "L",
    "TCT": "S", "TCC": "S", "TCA": "S", "TCG": "S",
    "TAT": "Y", "TAC": "Y", "TAA": "*", "TAG": "*",
    "TGT": "C", "TGC": "C", "TGA": "*", "TGG": "W",
    "CTT": "L", "CTC": "L", "CTA": "L", "CTG": "L",
    "CCT": "P", "CCC": "P", "CCA": "P", "CCG": "P",
    "CAT": "H", "CAC": "H", "CAA": "Q", "CAG": "Q",
    "CGT": "R", "CGC": "R", "CGA": "R", "CGG": "R",
    "ATT": "I", "ATC": "I", "ATA": "I", "ATG": "M",
    "ACT": "T", "ACC": "T", "ACA": "T", "ACG": "T",
    "AAT": "N", "AAC": "N", "AAA": "K", "AAG": "K",
    "AGT": "S", "AGC": "S", "AGA": "R", "AGG": "R",
    "GTT": "V", "GTC": "V", "GTA": "V", "GTG": "V",
    "GCT": "A", "GCC": "A", "GCA": "A", "GCG": "A",
    "GAT": "D", "GAC": "D", "GAA": "E", "GAG": "E",
    "GGT": "G", "GGC": "G", "GGA": "G", "GGG": "G",
}
NUC_MUTATION_RE = re.compile(r"^([A-Za-z.\-?])([0-9]+)([A-Za-z.\-?])$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Add inferred amino-acid branch mutations to an Auspice JSON.")
    parser.add_argument("--auspice", type=Path, required=True, help="Auspice JSON to update in place.")
    parser.add_argument("--ancestral-sequences", type=Path, required=True, help="TreeTime ancestral_sequences.fasta.")
    parser.add_argument("--gene", default="HA", help="Gene/protein key to add under branch_attrs.mutations. Default: HA.")
    parser.add_argument("--frame", type=int, default=0, choices=(0, 1, 2), help="Coding frame offset. Default: 0.")
    parser.add_argument("--report", type=Path, required=True, help="TSV report of inferred amino-acid branch mutations.")
    return parser.parse_args()


def read_fasta(path: Path) -> list[tuple[str, str]]:
    records = []
    header = None
    parts = []
    with path.open("r", encoding="utf-8-sig") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            if line.startswith(">"):
                if header is not None:
                    records.append((header, "".join(parts).upper()))
                header = line[1:].strip()
                parts = []
            else:
                parts.append(line)
    if header is not None:
        records.append((header, "".join(parts).upper()))
    if not records:
        raise SystemExit(f"No FASTA records found: {path}")
    return records


def translate_codon(seq: str, codon_index: int, frame: int) -> str:
    start = frame + (codon_index * 3)
    codon = seq[start:start + 3].replace("U", "T")
    if len(codon) != 3:
        return ""
    return CODE.get(codon, "X")


def aa_mutations(parent_seq: str, child_seq: str, frame: int) -> list[str]:
    codon_count = min((len(parent_seq) - frame) // 3, (len(child_seq) - frame) // 3)
    mutations = []
    for codon_index in range(codon_count):
        parent_aa = translate_codon(parent_seq, codon_index, frame)
        child_aa = translate_codon(child_seq, codon_index, frame)
        if not parent_aa or not child_aa or parent_aa == child_aa:
            continue
        if parent_aa in {"X", "*"} or child_aa in {"X", "*"}:
            continue
        mutations.append(f"{parent_aa}{codon_index + 1}{child_aa}")
    return mutations


def root_sequence(records: list[tuple[str, str]], root_name: str) -> tuple[str, str]:
    exact = [(header, seq) for header, seq in records if header == root_name]
    if len(exact) == 1:
        return exact[0]
    if records[0][0] == root_name:
        return records[0]
    raise SystemExit(
        f"Could not identify the root ancestral sequence for Auspice root {root_name!r}. "
        "Expected a matching record in ancestral_sequences.fasta."
    )


def apply_nuc_mutations(parent_seq: str, mutations: list[str]) -> tuple[str, int, int]:
    child = list(parent_seq)
    malformed = 0
    parent_base_mismatches = 0
    for mutation in mutations:
        match = NUC_MUTATION_RE.match(mutation)
        if not match:
            malformed += 1
            continue
        old, pos_text, new = match.groups()
        pos = int(pos_text) - 1
        if pos < 0 or pos >= len(child):
            malformed += 1
            continue
        current = child[pos].upper()
        old = old.upper()
        new = new.upper()
        if old not in {"N", "?", "."} and current not in {old, "N", "?", "."}:
            parent_base_mismatches += 1
        child[pos] = new
    return "".join(child), malformed, parent_base_mismatches


def main() -> None:
    args = parse_args()
    data = json.loads(args.auspice.read_text(encoding="utf-8"))
    records = read_fasta(args.ancestral_sequences)
    root_name = data["tree"].get("name", "")
    root_header, root_seq = root_sequence(records, root_name)

    total_mutations = 0
    branch_count = 0
    malformed_nuc_mutations = 0
    parent_base_mismatches = 0
    report_rows = []

    def walk(node: dict, parent_seq: str) -> None:
        nonlocal total_mutations, branch_count, malformed_nuc_mutations, parent_base_mismatches
        for child in node.get("children", []) or []:
            mutation_attrs = child.setdefault("branch_attrs", {}).setdefault("mutations", {})
            child_seq, malformed, mismatches = apply_nuc_mutations(parent_seq, mutation_attrs.get("nuc", []))
            malformed_nuc_mutations += malformed
            parent_base_mismatches += mismatches
            mutations = aa_mutations(parent_seq, child_seq, args.frame)
            mutation_attrs[args.gene] = mutations
            label_attrs = child.setdefault("branch_attrs", {}).setdefault("labels", {})
            if mutations:
                label_attrs["aa"] = f"{args.gene}: {', '.join(mutations)}"
                branch_count += 1
                total_mutations += len(mutations)
                for mutation in mutations:
                    report_rows.append((child.get("name", ""), args.gene, mutation))
            else:
                label_attrs.pop("aa", None)
            walk(child, child_seq)

    data["tree"].setdefault("branch_attrs", {}).setdefault("mutations", {}).setdefault(args.gene, [])
    walk(data["tree"], root_seq)

    meta = data.setdefault("meta", {})
    display_defaults = meta.setdefault("display_defaults", {})
    display_defaults.setdefault("branch_label", "aa")
    meta.setdefault("genome_annotations", {})
    meta["genome_annotations"].setdefault(
        args.gene,
        {
            "start": args.frame + 1,
            "end": len(root_seq),
            "strand": "+",
            "type": "CDS",
            "seqid": "nuc",
        },
    )

    args.auspice.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("node\tgene\taa_mutation\n")
        for node, gene, mutation in report_rows:
            handle.write(f"{node}\t{gene}\t{mutation}\n")
        handle.write(f"# root_sequence\t{root_header}\n")
        handle.write(f"# branches_with_aa_mutations\t{branch_count}\n")
        handle.write(f"# aa_mutation_count\t{total_mutations}\n")
        handle.write(f"# malformed_nuc_mutation_count\t{malformed_nuc_mutations}\n")
        handle.write(f"# parent_base_mismatch_count\t{parent_base_mismatches}\n")

    print(f"Added {total_mutations} {args.gene} amino-acid mutations across {branch_count} branches.")
    if malformed_nuc_mutations or parent_base_mismatches:
        print(
            "Warnings: "
            f"{malformed_nuc_mutations} malformed/out-of-range nucleotide mutations; "
            f"{parent_base_mismatches} parent-base mismatches."
        )


if __name__ == "__main__":
    main()
