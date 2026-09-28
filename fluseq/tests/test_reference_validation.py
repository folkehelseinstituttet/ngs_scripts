"""Run only the wrapper's offline reference check, never a sequencing pipeline."""

import os
from pathlib import Path
import subprocess

import pytest


WRAPPER = Path(__file__).resolve().parents[1] / "fluseq_wrapper.sh"
TABLE_HEADER = "Subtype;Reference;Type;GISAID_EPI\n"
TABLE_ROW = "H1N1;A/Example/1/2025;human;EPI_ISL_123456\n"
FASTA_HEADER = "A/Example/1/2025|EPI_ISL_123456_HA1"


@pytest.fixture
def bundle(tmp_path):
    root = tmp_path / "reference bundle"
    subtype = root / "human/H1N1"
    subtype.mkdir(parents=True)
    fasta = subtype / "HA1.fasta"
    fasta.write_text(f">{FASTA_HEADER}\nACDE\n", encoding="utf-8")
    table = root / "reference_table.csv"
    table.write_text(TABLE_HEADER + TABLE_ROW, encoding="utf-8")
    return root, table, fasta


def check(bundle, *extra):
    root, table, _ = bundle
    return subprocess.run(
        ["bash", str(WRAPPER), "--check-references", str(root), str(table), *extra],
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_valid_bundle_passes_without_pipeline_activity(bundle, tmp_path, monkeypatch):
    commands = tmp_path / "blocked-commands"
    commands.mkdir()
    for command in ["git", "smbclient", "conda", "nextflow", "docker"]:
        executable = commands / command
        executable.write_text("#!/bin/sh\necho UNEXPECTED_EXTERNAL_COMMAND >&2\nexit 99\n")
        executable.chmod(0o755)
    monkeypatch.setenv("PATH", str(commands) + os.pathsep + os.environ["PATH"])
    result = check(bundle)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "EPI_ISL_123456" in result.stdout
    assert "Validated 1 human FASTA files" in result.stdout
    assert "UNEXPECTED_EXTERNAL_COMMAND" not in result.stderr


def test_original_windows_table_format_is_accepted(bundle):
    _, table, _ = bundle
    table.write_bytes(
        ("\ufeff" + TABLE_HEADER + TABLE_ROW.rstrip() + "\u00a0 \n").replace("\n", "\r\n").encode("utf-8")
    )
    result = check(bundle)
    assert result.returncode == 0, result.stderr


def test_table_without_final_newline_is_accepted(bundle):
    bundle[1].write_text((TABLE_HEADER + TABLE_ROW).rstrip(), encoding="utf-8")
    assert check(bundle).returncode == 0


@pytest.mark.parametrize(
    ("header", "expected_error"),
    [
        ("A/Example/1/2025_HA1", "Missing EPI identifier"),
        ("A/Example/1/2025|EPI_ISL_999999_HA1", "Wrong EPI"),
        ("A/Other/2/2025|EPI_ISL_123456_HA1", "Wrong reference"),
        ("A/Example/1/2025|EPI_ISL_missing_HA1", "Invalid EPI header"),
        ("A/Example/1/2025|EPI_ISL_123456|extra_HA1", "Invalid EPI header"),
        ("A/Example/1/2025|EPI_ISL_123456_PB2", "Wrong segment suffix"),
        ("A/Example/1/2025|EPI_ISL_123456", "Invalid EPI header"),
    ],
)
def test_invalid_header_fails(bundle, header, expected_error):
    bundle[2].write_text(f">{header}\nACDE\n", encoding="utf-8")
    result = check(bundle)
    assert result.returncode == 1
    assert expected_error in result.stderr


@pytest.mark.parametrize(("filename", "suffix"), [("NS1", "NS"), ("SigPep", "SIGPEP"), ("HA1", "HA"), ("M1", "MP")])
def test_existing_segment_aliases_and_underscore_names_pass(bundle, filename, suffix):
    root, table, fasta = bundle
    replacement = fasta.with_name(filename + ".fasta")
    fasta.rename(replacement)
    replacement.write_text(f">A_Example_1_2025|EPI_ISL_123456_{suffix}\nACDE\n", encoding="utf-8")
    result = check((root, table, replacement))
    assert result.returncode == 0, result.stderr


def test_every_record_is_checked(bundle):
    bundle[2].write_text(
        f">{FASTA_HEADER}\nACDE\n>A/Other/2/2025|EPI_ISL_123456_HA1\nACDE\n",
        encoding="utf-8",
    )
    result = check(bundle)
    assert result.returncode == 1
    assert "Wrong reference" in result.stderr


def test_every_fasta_is_checked(bundle):
    bundle[2].with_name("NA.fasta").write_text(
        ">A/Example/1/2025|EPI_ISL_999999_NA\nACDE\n", encoding="utf-8"
    )
    result = check(bundle)
    assert result.returncode == 1
    assert "Wrong EPI" in result.stderr


@pytest.mark.parametrize("content", ["", ">header\n", "ACDE\n", f">{FASTA_HEADER}\n"])
def test_empty_or_malformed_fasta_fails(bundle, content):
    bundle[2].write_text(content, encoding="utf-8")
    assert check(bundle).returncode == 1


@pytest.mark.parametrize(
    ("table_text", "error"),
    [
        (TABLE_HEADER + TABLE_ROW + TABLE_ROW, "Duplicate reference-table entry"),
        (TABLE_HEADER + TABLE_ROW.replace("EPI_ISL_123456", "invalid"), "Invalid GISAID_EPI"),
        ("Subtype;Reference;Type\nH1N1;A/Example/1/2025;human\n", "missing columns"),
        (TABLE_HEADER + TABLE_ROW.replace("H1N1", "../outside"), "Invalid subtype"),
        (TABLE_HEADER + TABLE_ROW.rstrip() + ";extra\n", "Malformed reference-table row"),
        (TABLE_HEADER, "No reference-table entries"),
    ],
)
def test_invalid_table_fails(bundle, table_text, error):
    bundle[1].write_text(table_text, encoding="utf-8")
    result = check(bundle)
    assert result.returncode == 1
    assert error in result.stderr


def test_missing_subtype_directory_fails(bundle):
    bundle[2].parent.rename(bundle[2].parent.with_name("H3N2"))
    result = check(bundle)
    assert result.returncode == 1
    assert "Missing subtype directory" in result.stderr


def test_no_fasta_files_fails(bundle):
    bundle[2].rename(bundle[2].with_suffix(".txt"))
    result = check(bundle)
    assert result.returncode == 1
    assert "No FASTA files" in result.stderr


def test_absent_vaccine_bundle_does_not_block_human_check(bundle):
    with bundle[1].open("a", encoding="utf-8") as handle:
        handle.write(TABLE_ROW.replace(";human;", ";human_vaccine;"))
    assert check(bundle).returncode == 0
    result = check(bundle, "human_vaccine")
    assert result.returncode == 1
    assert "Reference directory not found" in result.stderr


def test_vaccine_type_can_be_checked_explicitly(bundle):
    bundle[1].write_text(TABLE_HEADER + TABLE_ROW.replace(";human;", ";human_vaccine;"), encoding="utf-8")
    (bundle[0] / "human").rename(bundle[0] / "human_vaccine")
    result = check(bundle, "human_vaccine")
    assert result.returncode == 0, result.stderr


def test_unknown_type_is_rejected(bundle):
    result = check(bundle, "unknown")
    assert result.returncode == 2


def test_missing_check_arguments_show_usage_without_starting_wrapper():
    result = subprocess.run(["bash", str(WRAPPER), "--check-references"], capture_output=True, text=True, timeout=15)
    assert result.returncode == 2
    assert "Usage:" in result.stderr


def test_shell_syntax():
    subprocess.run(["bash", "-n", str(WRAPPER)], check=True, capture_output=True, text=True)
