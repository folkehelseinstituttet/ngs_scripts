"""Exercise the standalone base-R historical import with synthetic CSV data."""

import csv
import io
import importlib
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "master_csv/bin/backfill_master_once.R"
pytestmark = pytest.mark.skipif(shutil.which("Rscript") is None, reason="Rscript is not installed")
HEADER = ["Key", "Prove_LW_ID", "NGS_LW_ID", "NGS_Coverage_HA", "Pasient_Alder",
          "Pasient_Fylke_Name", "PCR_H1_Res", "Prove_M nad", "Prove_Sesong", "Note", "Metadata_Key",
          "Master_Key_Source", "Master_Index_Source"]


def write_csv(path, headers, rows, encoding="utf-8-sig", delimiter=";"):
    text = io.StringIO(newline="")
    writer = csv.DictWriter(text, fieldnames=headers, delimiter=delimiter)
    writer.writeheader()
    writer.writerows(rows)
    path.write_bytes(text.getvalue().encode(encoding))
    return path


def run_backfill(tmp_path, master_rows, metadata_rows, history_rows, *, metadata_headers=None,
                 history_headers=None, encoding="utf-8-sig", delimiter=";", extra=(), header=None):
    master = write_csv(tmp_path / "master.csv", header or HEADER, master_rows, encoding, delimiter)
    metadata = write_csv(tmp_path / "metadata.csv", metadata_headers or list(metadata_rows[0]),
                         metadata_rows, encoding, delimiter)
    history = write_csv(tmp_path / "history.csv", history_headers or list(history_rows[0]),
                        history_rows, encoding, delimiter)
    before = [p.read_bytes() for p in (master, metadata, history)]
    output = tmp_path / "preview.csv"
    result = subprocess.run(["Rscript", str(SCRIPT), "--master", str(master), "--metadata", str(metadata),
                             "--results", str(history), "--output", str(output), *extra],
                            capture_output=True, text=True, timeout=30)
    assert [p.read_bytes() for p in (master, metadata, history)] == before
    return result, output


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        return reader.fieldnames, list(reader)


@pytest.mark.parametrize("encoding", ["utf-8-sig", "cp1252", "utf-16"])
@pytest.mark.parametrize("delimiter", [";", ",", "\t"])
def test_metadata_joins_header_order_and_missing_values(tmp_path, encoding, delimiter):
    result, output = run_backfill(tmp_path, [], [
        {"Key": "meta-0001", "RekvNr": "old-key", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1",
         "Pasient_Alder": "04", "Prove_Maanad": "01", "Note": "metadata"},
        {"Key": "meta-0002", "RekvNr": "unused", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ2"},
    ], [{"Key": "old-key", "NGS_LW_ID": "SEQ1", "NGS_Coverage_HA": "0", "Pasient_Alder": "",
         "Note": 'Æøå; quoted "text"\nsecond line'}], encoding=encoding, delimiter=delimiter)
    assert result.returncode == 0, result.stderr
    headers, rows = read_csv(output)
    assert headers == HEADER
    assert len(rows) == 1
    assert rows[0]["Prove_LW_ID"] == "0001"
    assert rows[0]["Metadata_Key"] == "meta-0001"
    assert rows[0]["Key"] == "old-key"
    assert rows[0]["Pasient_Alder"] == "04"
    assert rows[0]["Prove_M nad"] == "01"
    assert rows[0]["NGS_Coverage_HA"] == "0"
    assert rows[0]["PCR_H1_Res"] == ""
    assert rows[0]["Note"] == 'Æøå; quoted "text"\nsecond line'
    assert output.read_bytes().startswith(b"\xef\xbb\xbf")


@pytest.mark.parametrize("overwrite", [False, True])
def test_existing_rows_preserved_or_explicitly_updated(tmp_path, overwrite):
    result, output = run_backfill(tmp_path, [
        {"Key": "old-key", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1", "NGS_Coverage_HA": "99", "Note": "newer"},
        {"Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ2", "Note": "unrelated"},
    ], [{"RekvNr": "old-key", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1", "Pasient_Alder": "04"}],
        [{"Key": "old-key", "NGS_LW_ID": "SEQ1", "NGS_Coverage_HA": "80", "Note": ""}],
        extra=["--overwrite-existing"] if overwrite else [])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert len(rows) == 2
    assert rows[0]["NGS_Coverage_HA"] == ("80" if overwrite else "99")
    assert rows[0]["Note"] == "newer"
    assert rows[0]["Pasient_Alder"] == "04"
    assert rows[1]["Note"] == "unrelated"


def test_fallback_and_literal_missing_text(tmp_path):
    result, output = run_backfill(tmp_path, [], [{"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}],
                                  [{"Prove_LW_ID": "NA", "NGS_LW_ID": "SEQ9", "Note": "NA"}])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert rows[0]["Prove_LW_ID"] == "SEQ9"
    assert rows[0]["Master_Index_Source"] == "Sequence_ID"
    assert rows[0]["Note"] == "NA"
    assert "without metadata: 1" in result.stderr


@pytest.mark.parametrize("master_row", [
    {"Key": "old-key", "Note": "keep"},
    {"Prove_LW_ID": "SEQ1", "NGS_LW_ID": "SEQ1", "Master_Index_Source": "Sequence_ID", "Note": "keep"},
])
def test_legacy_and_provisional_master_indexes_repaired(tmp_path, master_row):
    result, output = run_backfill(tmp_path, [master_row],
                                  [{"RekvNr": "old-key", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}],
                                  [{"Key": "old-key", "NGS_LW_ID": "SEQ1"}])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert len(rows) == 1
    assert rows[0]["Prove_LW_ID"] == "0001"
    assert rows[0]["Master_Index_Source"] == "Prove_LW_ID"
    assert rows[0]["Note"] == "keep"


@pytest.mark.parametrize("case", ["duplicate", "no_id", "disagreement", "unknown_column", "ambiguous_key",
                                  "mapping_conflict", "reserved", "sequence_collision"])
def test_ambiguous_inputs_fail_without_output(tmp_path, case):
    meta = [{"RekvNr": "old-key", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}]
    history = [{"Key": "old-key", "NGS_LW_ID": "SEQ1"}]
    master = []
    if case == "duplicate":
        history *= 2
    elif case == "no_id":
        history = [{"Key": "unknown"}]
    elif case == "disagreement":
        history[0]["Prove_LW_ID"] = "0002"
    elif case == "unknown_column":
        history[0]["Unexpected"] = "keep this"
    elif case == "ambiguous_key":
        meta.append({"RekvNr": "old-key", "Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ2"})
        history = [{"Key": "old-key"}]
    elif case == "mapping_conflict":
        meta[0].update(Prove_Sesong="one", Sesong="two")
    elif case == "reserved":
        history[0]["Master_Index_Source"] = "Sequence_ID"
    elif case == "sequence_collision":
        master = [{"Prove_LW_ID": "SEQ9", "NGS_LW_ID": "OTHER"}]
        history = [{"NGS_LW_ID": "SEQ9"}]
    result, output = run_backfill(tmp_path, master, meta, history)
    assert result.returncode != 0
    assert not output.exists()


def test_known_text_repairs(tmp_path):
    result, output = run_backfill(tmp_path, [],
                                  [{"Prove_LW_ID": "0001", "Pasient_Fylke_Name": "M re g Romsdal", "PCR_H1_Res": "P vist"}],
                                  [{"Prove_LW_ID": "0001"}])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert rows[0]["Pasient_Fylke_Name"] == "Møre og Romsdal"
    assert rows[0]["PCR_H1_Res"] == "Påvist"


def test_existing_output_is_never_overwritten(tmp_path):
    output = tmp_path / "preview.csv"
    output.write_text("keep this file")
    result, _ = run_backfill(tmp_path, [], [{"Prove_LW_ID": "0001"}], [{"Prove_LW_ID": "0001"}])
    assert result.returncode != 0
    assert output.read_text() == "keep this file"


@pytest.mark.parametrize("text,error", [
    ('Key;Note\n0001;"first\nsecond"\n\n0002;extra;field\n', "Line 5: 3 fields"),
    ('Key;Note\n0001;fine\n0002\n', "Line 3: 1 fields"),
    ('Key;Note\n0001;"unclosed\n', "Unterminated quoted CSV field"),
    ('Key,Note\n0001,fine\n0002,extra,field\n', "Line 3: 3 fields"),
])
def test_malformed_csv_identifies_physical_lines_without_disclosing_values(tmp_path, text, error):
    path = tmp_path / "backlog.csv"
    path.write_text(text)
    result = subprocess.run(["Rscript", "-e", 'args <- commandArgs(TRUE); source(args[1]); read_csv_text(args[2])',
                             str(SCRIPT), str(path)], capture_output=True, text=True, timeout=15)
    assert result.returncode != 0
    assert error in result.stderr
    assert "0001" not in result.stderr and "0002" not in result.stderr
    assert path.read_text() == text


def test_diagnostic_lists_all_bad_lines(tmp_path):
    path = tmp_path / "backlog.csv"
    path.write_text('Key;Note\n0001;fine\n\n0002;extra;field\n0003\n')
    result = subprocess.run(["Rscript", "-e",
                             'args <- commandArgs(TRUE); source(args[1]); d <- diagnose_csv(args[2]); '
                             'stopifnot(identical(d$line, c(4L, 5L)), all(d$expected == 2L), '
                             'identical(d$fields, c(3L, 1L)))', str(SCRIPT), str(path)],
                            capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert "header has 2 fields; inconsistent records: 2" in result.stderr


def test_named_record_retained_and_compatible_with_future_imports(tmp_path, monkeypatch):
    name = "B/TOKYO/EIS13-175/2025"
    result, output = run_backfill(
        tmp_path, [], [{"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}],
        [{"Key": name, "Note": "historical result"}],
        header=HEADER + ["SequenceID"], extra=["--allow-name-fallback"])
    assert result.returncode == 0, result.stderr
    headers, rows = read_csv(output)
    assert rows[0]["Key"] == rows[0]["SequenceID"] == rows[0]["Prove_LW_ID"] == name
    assert rows[0]["NGS_LW_ID"] == ""
    assert rows[0]["Master_Index_Source"] == "Sequence_ID"
    assert rows[0]["Note"] == "historical result"

    # The unchanged Python importer must retain the R output, then reindex it
    # if a real specimen ID arrives later, without renaming Key or duplicating it.
    monkeypatch.syspath_prepend(str(ROOT / "master_csv/bin"))
    merger = importlib.import_module("merge_master_csv")
    report = (["OriginalName"], [{"OriginalName": name}])
    metadata = (["Prove_LW_ID"], [])
    new_headers, kept, stats = merger.merge_tables((headers, rows), metadata, report, "fasta")
    assert len(kept) == 1 and stats["added"] == 0
    assert kept[0]["Key"] == kept[0]["Prove_LW_ID"] == name
    meta_row = {"RekvNr": name, "Prove_LW_ID": "0009", "NGS_LW_ID": "SEQ9"}
    _, resolved, stats = merger.merge_tables((new_headers, kept), (list(meta_row), [meta_row]), report, "fasta")
    assert len(resolved) == 1 and stats["reindexed"] == 1
    assert resolved[0]["Key"] == resolved[0]["SequenceID"] == name
    assert resolved[0]["Prove_LW_ID"] == "0009"
    assert resolved[0]["Master_Index_Source"] == "Prove_LW_ID"

    # Replaying the historical backfill is also idempotent.
    retry = tmp_path / "retry.csv"
    command = ["Rscript", str(SCRIPT), "--master", str(output), "--metadata", str(tmp_path / "metadata.csv"),
               "--results", str(tmp_path / "history.csv"), "--output", str(retry), "--allow-name-fallback"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert retry.read_bytes() == output.read_bytes()


@pytest.mark.parametrize("case", ["no_name", "duplicate_name", "sequence_collision", "missing_column", "ambiguous_match"])
def test_name_fallback_does_not_bypass_identifier_checks(tmp_path, case):
    name = "B/TOKYO/EIS13-175/2025"
    header = HEADER + ["SequenceID"]
    metadata = [{"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1", "RekvNr": "other"}]
    master = []
    history = [{"Key": name}]
    if case == "no_name":
        history = [{"Key": "NA"}]
    elif case == "duplicate_name":
        history *= 2
    elif case == "sequence_collision":
        master = [{"Key": "other", "Prove_LW_ID": "0002", "NGS_LW_ID": name}]
    elif case == "missing_column":
        header = HEADER
    elif case == "ambiguous_match":
        metadata[0]["RekvNr"] = name
        metadata.append({"Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ2", "RekvNr": name})
    result, output = run_backfill(tmp_path, master, metadata, history,
                                  header=header, extra=["--allow-name-fallback"])
    assert result.returncode != 0
    assert not output.exists()


@pytest.mark.parametrize("policy,chosen,other_field", [("first", "first", ""), ("last", "last", "05")])
def test_duplicate_selection_keeps_whole_row_after_identifier_resolution(tmp_path, policy, chosen, other_field):
    # The same specimen is identified through a legacy alias in the first row,
    # and a sequencing identifier in the last; raw Prove_LW_ID is absent in both.
    history = [{"Key": "legacy", "NGS_LW_ID": "", "Note": "first", "Pasient_Alder": ""},
               {"Key": "", "NGS_LW_ID": "SEQ2", "Note": "separate", "Pasient_Alder": ""},
               {"Key": "", "NGS_LW_ID": "SEQ1", "Note": "last", "Pasient_Alder": "05"}]
    meta = [{"RekvNr": "legacy", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}]
    result, output = run_backfill(tmp_path, [], meta, history, extra=["--duplicate-results", policy])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert len(rows) == 2
    row = next(row for row in rows if row["Prove_LW_ID"] == "0001")
    assert row["Note"] == chosen
    assert row["Pasient_Alder"] == other_field  # Do not combine the discarded record's cells.
    assert "historical duplicate records skipped: 1" in result.stderr


def test_duplicate_name_selection_preserves_exact_name(tmp_path):
    name = "B/TOKYO/EIS13-175/2025"
    result, output = run_backfill(tmp_path, [], [{"Prove_LW_ID": "0001"}],
                                  [{"Key": name, "Note": "keep"}, {"Key": name, "Note": "discard"}],
                                  header=HEADER + ["SequenceID"],
                                  extra=["--allow-name-fallback", "--duplicate-results", "first"])
    assert result.returncode == 0, result.stderr
    _, rows = read_csv(output)
    assert len(rows) == 1
    assert rows[0]["Key"] == rows[0]["Prove_LW_ID"] == rows[0]["SequenceID"] == name
    assert rows[0]["Note"] == "keep"


@pytest.mark.parametrize("source", ["master", "metadata"])
def test_duplicate_selection_does_not_relax_other_input_checks(tmp_path, source):
    rows = [{"Prove_LW_ID": "0001"}, {"Prove_LW_ID": "0001"}]
    result, output = run_backfill(tmp_path, rows if source == "master" else [],
                                  rows if source == "metadata" else [{"Prove_LW_ID": "0001"}],
                                  [{"Prove_LW_ID": "0001"}], extra=["--duplicate-results", "first"])
    assert result.returncode != 0
    assert f"{source}: duplicate Prove_LW_ID" in result.stderr
    assert not output.exists()
