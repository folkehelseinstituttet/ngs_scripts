"""Exercise identifier diagnostics without changing source files or SMB data."""

import importlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


BIN = Path(__file__).resolve().parents[1] / "master_csv/bin"


@pytest.fixture
def diagnostics(monkeypatch):
    monkeypatch.syspath_prepend(str(BIN))
    return importlib.import_module("diagnose_master_ids")


def table(*rows):
    return list(dict.fromkeys(key for row in rows for key in row)), list(rows)


@pytest.mark.parametrize(("master", "metadata", "reason"), [
    (table({"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}, {"Key": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ-A"}),
     table({"RekvNr": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}), "multiple Prove_LW_ID values within master"),
    (table({"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}),
     table({"RekvNr": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}, {"RekvNr": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ-A"}),
     "multiple Prove_LW_ID values within metadata"),
    (table({"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}), table({"RekvNr": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ-A"}),
     "master Prove_LW_ID differs from metadata Prove_LW_ID"),
])
def test_conflicts_identify_both_sources_and_preserve_keys(diagnostics, master, metadata, reason):
    rows = diagnostics.find_conflicts(master, metadata, table({"Sample": "SEQ-A"}))
    assert {row["NGS_LW_ID"] for row in rows} == {"SEQ-A"}
    assert {row["Prove_LW_ID"] for row in rows} == {"0001", "0002"}
    assert all(reason in row["conflict"] for row in rows)
    assert all(row["in_current_report"] == "yes" for row in rows)


def test_conflict_outside_current_report_is_still_visible(diagnostics):
    rows = diagnostics.find_conflicts(table({"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "OLD"}),
                                     table({"RekvNr": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "OLD"}), table({"Sample": "CURRENT"}))
    assert len(rows) == 2
    assert all(row["in_current_report"] == "no" for row in rows)


def test_valid_provisional_rekey_is_not_a_conflict(diagnostics):
    rows = diagnostics.find_conflicts(table({"Prove_LW_ID": "SEQ-A", "NGS_LW_ID": "SEQ-A", "Master_Index_Source": "Sequence_ID"}),
                                     table({"RekvNr": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}))
    assert rows == []


def test_unmarked_sample_key_is_not_assumed_provisional(diagnostics):
    rows = diagnostics.find_conflicts(table({"Prove_LW_ID": "SEQ-A", "NGS_LW_ID": "SEQ-A"}),
                                     table({"RekvNr": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}))
    assert len(rows) == 2


def test_fasta_report_membership_uses_original_name(diagnostics):
    rows = diagnostics.find_conflicts(table({"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}),
                                     table({"RekvNr": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ-A"}),
                                     table({"OriginalName": "0002"}), workflow="fasta")
    assert all(row["in_current_report"] == "yes" for row in rows)


def test_cli_diagnostic_is_read_only_and_keeps_ids_out_of_logs(diagnostics, tmp_path):
    master = tmp_path / "master.csv"
    master.write_text("Key;Prove_LW_ID;NGS_LW_ID\nlegacy1;0001;SEQ-A\n")
    metadata = tmp_path / "NGS_PREP_INF_report.csv"
    metadata.write_text("RekvNr;Prove_LW_ID;NGS_LW_ID\nlegacy2;0002;SEQ-A\n")
    report = tmp_path / "run.csv"
    report.write_text("Sample\nSEQ-A\n")
    before = [path.read_bytes() for path in (master, metadata, report)]
    output = tmp_path / "conflicts.csv"
    env = {key: value for key, value in os.environ.items() if not key.startswith("FLUSEQ_")}
    env["FLUSEQ_MASTER_CSV"] = str(master)
    result = subprocess.run([sys.executable, str(BIN / "update_master_csv.py"), "--workflow", "fastq",
        "--check-identifiers", "--report", str(report), "--identifier-report", str(output)],
        env=env, capture_output=True, text=True)
    assert result.returncode == 2, result.stderr
    assert "1 conflicting" in result.stdout
    assert "SEQ-A" not in result.stdout + result.stderr
    assert [path.read_bytes() for path in (master, metadata, report)] == before
    assert not list(tmp_path.glob("*.bak.*")) and not list(tmp_path.glob("*.lock"))
    _, rows = importlib.import_module("merge_master_csv").read_table(output)
    assert {row["Prove_LW_ID"] for row in rows} == {"0001", "0002"}
    assert output.stat().st_mode & 0o777 == 0o600


def test_remote_diagnostic_only_downloads(diagnostics, tmp_path, monkeypatch):
    updater = importlib.import_module("update_master_csv")
    master = tmp_path / "master.csv"
    master.write_text("Key;Prove_LW_ID;NGS_LW_ID\nlegacy1;0001;SEQ-A\n")
    metadata = tmp_path / "metadata.csv"
    metadata.write_text("RekvNr;Prove_LW_ID;NGS_LW_ID\nlegacy2;0002;SEQ-A\n")
    commands = []

    def command(remote, verb, *args):
        commands.append(verb)
        assert verb == "get"  # No locks, upload, rename or delete.
        shutil.copyfile(tmp_path / args[0], args[1])

    monkeypatch.setattr(updater.SMB, "command", command)
    remote = updater.SMB("//mock/share", "data", "mock-auth")
    config = {"master": None, "metadata": None, "master_smb": remote, "metadata_smb": remote,
              "master_name": "master.csv", "metadata_name": "metadata.csv"}
    rows = updater.check_identifiers(config)
    assert len(rows) == 2
    assert commands == ["get", "get"]


def test_diagnostic_output_cannot_replace_inputs(diagnostics, tmp_path):
    updater = importlib.import_module("update_master_csv")
    master = tmp_path / "master.csv"
    master.write_text("Key\n")
    with pytest.raises(ValueError, match="must be separate"):
        updater.check_identifiers({"master": str(master), "metadata": None}, output=master)
    assert master.read_text() == "Key\n"


def test_merge_error_now_identifies_the_source(diagnostics):
    merger = importlib.import_module("merge_master_csv")
    with pytest.raises(ValueError, match=r"master:.*records 2 and 3"):
        merger.sequence_index([{"Key": "legacy1", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ-A"}, {"Key": "legacy2", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ-A"}],
                              source="master")
