"""Specimen indexes, sequencing fallbacks, and migration of existing master rows."""

import importlib
from pathlib import Path

import pytest


@pytest.fixture
def merger(monkeypatch):
    monkeypatch.syspath_prepend(str(Path(__file__).resolve().parents[1] / "master_csv/bin"))
    return importlib.import_module("merge_master_csv")


def table(*rows, headers=()):
    return list(dict.fromkeys([*headers, *(name for row in rows for name in row)])), list(rows)


def empty():
    return table(headers=("Prove_LW_ID",))


def test_specimen_is_index_even_when_legacy_keys_are_blank_or_duplicated(merger):
    master = table(
        {"Prove_LW_ID": "0001", "Key": "same", "NGS_LW_ID": "SEQ1", "Old": "keep"},
        {"Prove_LW_ID": "0002", "Key": "same", "NGS_LW_ID": "SEQ2"},
        {"Prove_LW_ID": "0003", "Key": "", "NGS_LW_ID": "SEQ3"},
    )
    metadata = table({"Prove_LW_ID": "0001", "RekvNr": "same", "NGS_LW_ID": "SEQ1", "Future": "new"})
    headers, rows, stats = merger.merge_tables(master, metadata, table({"Sample": "SEQ1", "Result": "done"}), "fastq")
    assert [row["Prove_LW_ID"] for row in rows] == ["0001", "0002", "0003"]
    assert [row["Key"] for row in rows] == ["same", "same", ""]
    assert rows[0]["Old"] == "keep" and rows[0]["Future"] == "new" and rows[0]["Result"] == "done"
    assert "Future" in headers and stats["updated"] == 1 and stats["added"] == 0


@pytest.mark.parametrize("missing", ["", "  ", "NA", "N/A", "None", "NULL", "NaN", "-"])
def test_missing_specimen_uses_sequence_and_marks_it(merger, missing):
    metadata = table({"Prove_LW_ID": missing, "RekvNr": "legacy", "NGS_LW_ID": "000045"})
    _, rows, _ = merger.merge_tables(empty(), metadata, table({"Sample": "000045", "Prove_LW_ID": missing}), "fastq")
    assert rows[0]["Prove_LW_ID"] == "000045"
    assert rows[0]["Master_Index_Source"] == "Sequence_ID"
    assert rows[0]["Key"] == "legacy"


@pytest.mark.parametrize("column", ["NGS_LW_ID", "Sequence_ID", "SequenceID"])
def test_explicit_sequence_column_joins_fastq_sample(merger, column):
    metadata = table({"Prove_LW_ID": "0001", column: "SEQ1"})
    _, rows, _ = merger.merge_tables(empty(), metadata, table({"Sample": "SEQ1"}), "fastq")
    assert rows[0]["Prove_LW_ID"] == "0001"


@pytest.mark.parametrize("workflow", ["fastq", "fasta"])
def test_fallback_resolves_same_row_and_retry_does_not_rewrite(merger, tmp_path, workflow):
    master = tmp_path / "master.csv"
    metadata = tmp_path / "metadata.csv"
    report = tmp_path / "run.csv"
    merger.write_table(master, ["Prove_LW_ID"], [])
    merger.write_table(metadata, ["Prove_LW_ID", "NGS_LW_ID", "RekvNr"], [])
    incoming = ({"Sample": "SEQ1", "OldResult": "keep"} if workflow == "fastq"
                else {"OriginalName": "legacy", "SampleID": "stable-uid", "OldResult": "keep"})
    merger.write_table(report, *table(incoming))
    assert merger.merge_files(master, metadata, report, workflow)["added"] == 1
    _, initial = merger.read_table(master)
    assert initial[0]["Prove_LW_ID"] == ("SEQ1" if workflow == "fastq" else "stable-uid")
    assert initial[0]["Master_Index_Source"] == "Sequence_ID"
    merger.write_table(metadata, *table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1", "RekvNr": "legacy"}))
    incoming.pop("OldResult")
    merger.write_table(report, *table(incoming))
    result = merger.merge_files(master, metadata, report, workflow)
    _, rows = merger.read_table(master)
    assert result["added"] == 0 and result["updated"] == 1 and result["reindexed"] == 1
    assert len(rows) == 1 and rows[0]["Prove_LW_ID"] == "0001"
    assert rows[0]["Master_Index_Source"] == "Prove_LW_ID" and rows[0]["OldResult"] == "keep"
    assert not merger.merge_files(master, metadata, report, workflow)["written"]


def test_missing_metadata_does_not_downgrade_a_known_index(merger):
    master = table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"})
    metadata = table({"Prove_LW_ID": "", "NGS_LW_ID": "SEQ1"})
    _, rows, _ = merger.merge_tables(master, metadata, table({"Sample": "SEQ1", "Prove_LW_ID": ""}), "fastq")
    assert rows[0]["Prove_LW_ID"] == "0001"
    assert rows[0].get("Master_Index_Source") != "Sequence_ID"


def test_migrates_legacy_rows_without_copying_key_into_specimen_index(merger):
    master = table(
        {"Key": "legacy", "NGS_LW_ID": "SEQ1", "Prove_LW_ID": ""},
        {"Key": "SEQ2", "NGS_LW_ID": "SEQ2", "Master_Key_Source": "Sample"},
        {"Key": "legacy3", "Prove_LW_ID": "", "Note": "untouched"},
    )
    metadata = table({"RekvNr": "legacy", "Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"},
                     {"RekvNr": "legacy3", "Prove_LW_ID": "0003", "NGS_LW_ID": "SEQ3"})
    _, rows, stats = merger.merge_tables(master, metadata, table({"Sample": "SEQ1"}), "fastq")
    assert [row["Prove_LW_ID"] for row in rows] == ["0001", "SEQ2", "0003"]
    assert [row["Key"] for row in rows] == ["legacy", "SEQ2", "legacy3"]
    assert rows[1]["Master_Key_Source"] == "Sample" and rows[1]["Master_Index_Source"] == "Sequence_ID"
    assert rows[2]["Note"] == "untouched" and "NGS_LW_ID" not in rows[2]
    assert stats["reindexed"] == 3


def test_legacy_row_can_use_matched_metadata_sequence_as_fallback(merger):
    master = table({"Key": "legacy", "OldResult": "keep"})
    metadata = table({"RekvNr": "legacy", "Prove_LW_ID": "", "NGS_LW_ID": "SEQ1"})
    report = table({"OriginalName": "legacy"})
    headers, rows, stats = merger.merge_tables(master, metadata, report, "fasta")
    assert rows[0]["Prove_LW_ID"] == "SEQ1" and rows[0]["NGS_LW_ID"] == "SEQ1"
    assert rows[0]["Master_Index_Source"] == "Sequence_ID" and rows[0]["OldResult"] == "keep"
    assert stats["added"] == 0 and stats["reindexed"] == 1
    _, again, stats = merger.merge_tables((headers, rows), metadata, report, "fasta")
    assert again == rows and stats["unchanged"] == 1 and stats["reindexed"] == 0


@pytest.mark.parametrize("name", ["legacy", "0001"])
def test_fasta_resolves_original_name_without_overwriting_legacy_key(merger, name):
    master = table({"Prove_LW_ID": "0001", "Key": "legacy", "NGS_LW_ID": "SEQ1"})
    metadata = table({"Prove_LW_ID": "0001", "RekvNr": "legacy", "NGS_LW_ID": "SEQ1"})
    _, rows, stats = merger.merge_tables(master, metadata, table({"OriginalName": name, "SampleID": "uid"}), "fasta")
    assert rows[0]["Prove_LW_ID"] == "0001" and rows[0]["Key"] == "legacy"
    assert stats["total"] == 1 and stats["added"] == 0


@pytest.mark.parametrize(("master", "metadata", "report", "workflow", "error"), [
    (table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}, {"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ2"}),
     empty(), table({"Sample": "SEQ1"}), "fastq", "duplicate Prove_LW_ID"),
    (table({"Key": "legacy"}), empty(), table({"Sample": "SEQ1"}), "fastq", "missing Prove_LW_ID and sequencing ID"),
    (empty(), empty(), table({"OriginalName": "legacy"}), "fasta", "missing Prove_LW_ID and sequencing ID"),
    (table({"Prove_LW_ID": "SEQ1", "NGS_LW_ID": "different"}), empty(), table({"Sample": "SEQ1"}),
     "fastq", "collides with an unrelated Prove_LW_ID"),
    (table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}),
     table({"Prove_LW_ID": "0002", "NGS_LW_ID": "SEQ1"}), table({"Sample": "SEQ1"}),
     "fastq", "master differs from metadata"),
    (table({"Prove_LW_ID": "SEQ1", "NGS_LW_ID": "SEQ1", "Master_Index_Source": "Sequence_ID"},
           {"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ2"}),
     table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}), table({"Sample": "SEQ1"}),
     "fastq", "duplicate Prove_LW_ID"),
    (empty(), table({"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}),
     table({"Sample": "SEQ1", "Prove_LW_ID": "0002"}), "fastq", "disagree"),
    (empty(), empty(), table({"Sample": "SEQ1"}, {"Sample": "SEQ1"}), "fastq", "duplicate Prove_LW_ID"),
    (table({"Prove_LW_ID": "0001", "Key": "legacy"}, {"Prove_LW_ID": "0002", "Key": "legacy"}),
     empty(), table({"OriginalName": "legacy", "SampleID": "uid"}), "fasta", "ambiguous identifier"),
    (table({"Prove_LW_ID": "uid", "SampleID": "uid", "OriginalName": "legacy", "Master_Index_Source": "Sequence_ID"}),
     empty(), table({"OriginalName": "legacy", "SampleID": "uid", "NGS_LW_ID": "SEQ1"}),
     "fasta", "provisional Prove_LW_ID must equal its sequencing ID"),
])
def test_ambiguous_or_missing_identifiers_fail_before_writing(merger, tmp_path, master, metadata, report, workflow, error):
    paths = [tmp_path / name for name in ("master.csv", "metadata.csv", "run.csv")]
    for path, data in zip(paths, (master, metadata, report)):
        merger.write_table(path, *data)
    before = [path.read_bytes() for path in paths]
    with pytest.raises(merger.MergeError, match=error):
        merger.merge_files(*paths, workflow)
    assert [path.read_bytes() for path in paths] == before
    assert not list(tmp_path.glob("*.bak.*")) and not list(tmp_path.glob("*.lock"))


@pytest.mark.parametrize("original", ["legacy", "0001"])
def test_qc_uses_new_index_and_accepts_legacy_fasta_names(merger, tmp_path, original):
    qc = importlib.import_module("report_qc_html")
    report = tmp_path / "run.csv"
    merger.write_table(report, *table({"OriginalName": original, "SampleID": "uid", "Sekvens_Resultat": "A/H3N2"}))
    master = [{"Prove_LW_ID": "0001", "Key": "legacy", "PCR_H3_Res": "Påvist"}]
    result = qc.build_report(report, master, workflow="fasta")["samples"][0]
    assert result["master_key"] == "0001" and result["qpcr"]["status"] == "Match"
