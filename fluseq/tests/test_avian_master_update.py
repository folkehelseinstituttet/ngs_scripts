"""Archive integration only: synthetic tables/records, no pipeline or network calls."""

import importlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "master_csv/bin"


@pytest.fixture
def updater(monkeypatch):
    monkeypatch.syspath_prepend(str(BIN))
    return importlib.import_module("update_master_csv")


def local_inputs(tmp_path):
    master = tmp_path / "master.csv"
    master.write_text("Prove_LW_ID\n")
    report = tmp_path / "run.csv"
    report.write_text("OriginalName,SampleID,ExtraResult\n0001,SEQ1,example\n")
    fasta = tmp_path / "run.fasta"
    fasta.write_text(">record-one\nACGT\n")
    return master, report, fasta


@pytest.mark.parametrize("extension", ["csv", "xls", "xlsx"])
def test_cli_updates_both_archives_and_retry_is_idempotent(updater, tmp_path, extension):
    master, report, fasta = local_inputs(tmp_path)
    if extension == "csv":
        (tmp_path / "metadata.csv").write_text("Prove_LW_ID;NGS_LW_ID;Host\n0001;SEQ1;example\n")
    elif extension == "xls":
        pytest.importorskip("xlrd")
        # Values-only BIFF8 workbook generated with xlwt from the same synthetic
        # header/data rows as the CSV and XLSX cases below.
        shutil.copyfile(ROOT / "tests/fixtures/avian_metadata.xls", tmp_path / "metadata.xls")
    else:
        openpyxl = pytest.importorskip("openpyxl")
        book = openpyxl.Workbook()
        book.active.append(["Prove_LW_ID", "NGS_LW_ID", "Host"])
        book.active.append(["0001", "SEQ1", "example"])
        book.save(tmp_path / "metadata.xlsx")
    env = {key: value for key, value in os.environ.items() if not key.startswith(("FLUSEQ_", "AVIANSEQ_"))}
    env.update(AVIANSEQ_MASTER_UPDATE="true", AVIANSEQ_MASTER_CSV=str(master),
               FLUSEQ_MASTER_CSV="/must/not/be/used/master.csv", FLUSEQ_MASTER_UPDATE="false")
    args = [sys.executable, str(BIN / "update_master_csv.py"), "--profile", "avian", "--workflow", "fasta",
            "--report", str(report), "--fasta", str(fasta)]
    for _ in range(2):
        result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stdout + result.stderr
    _, rows = updater.read_table(master)
    assert len(rows) == 1
    assert rows[0]["Prove_LW_ID"] == "0001"
    assert rows[0]["Host"] == "example"
    assert rows[0]["ExtraResult"] == "example"
    assert master.with_suffix(".fasta").read_bytes() == fasta.read_bytes()
    assert len(list(tmp_path.glob("master.csv.bak.*"))) == 1
    assert not list(tmp_path.glob("*.lock"))


def test_metadata_discovery_requires_unambiguous_file_and_accepts_override(updater, tmp_path):
    master, _, _ = local_inputs(tmp_path)
    env = {"AVIANSEQ_MASTER_CSV": str(master)}
    with pytest.raises(updater.MergeError, match="No metadata file"):
        updater.profile_configuration(env, profile="avian")
    for name in ("metadata.csv", "metadata.xls"):
        (tmp_path / name).touch()
    with pytest.raises(updater.MergeError, match="Multiple metadata files"):
        updater.profile_configuration(env, profile="avian")
    env["AVIANSEQ_METADATA_SMB_NAME"] = "metadata.xls"
    config, _ = updater.profile_configuration(env, profile="avian")
    assert config["metadata"] == str(tmp_path / "metadata.xls")
    env["AVIANSEQ_METADATA_CSV"] = str(tmp_path / "metadata.csv")
    config, _ = updater.profile_configuration(env, profile="avian")
    assert config["metadata"] == str(tmp_path / "metadata.csv")
    assert master.read_text() == "Prove_LW_ID\n"


def test_avian_smb_defaults_are_isolated_from_human_settings(updater, tmp_path, monkeypatch):
    auth = tmp_path / "auth"
    auth.touch()
    monkeypatch.setattr(updater.shutil, "which", lambda name: "/mock/smbclient")
    config, _ = updater.profile_configuration({
        "AVIANSEQ_MASTER_UPDATE": "true", "AVIANSEQ_MASTER_SMB_AUTH": str(auth),
        "FLUSEQ_MASTER_SMB_DIR": "wrong", "FLUSEQ_METADATA_SMB_NAME": "wrong.csv",
    }, profile="avian")
    assert config["master_smb"].directory == updater.MASTER_DIR + "-AVIAN"
    assert config["metadata_smb"].directory == config["master_smb"].directory
    assert config["metadata_names"] == ("metadata.csv", "metadata.xls", "metadata.xlsx")
    assert config["master_name"] == "master.csv"


@pytest.mark.parametrize("validation,mode", [("VER", "true"), ("", "false")])
def test_disabled_and_validation_skip_without_metadata(updater, validation, mode):
    config, reason = updater.profile_configuration({"AVIANSEQ_MASTER_UPDATE": mode}, validation, "avian")
    assert config is None and reason


@pytest.mark.parametrize("available", [(), ("metadata.csv",), ("metadata.csv", "metadata.xls")])
def test_remote_discovery_before_any_master_change(updater, tmp_path, available):
    master, report, fasta = local_inputs(tmp_path)

    def get_if_exists(name, path):
        if name not in available:
            return False
        path.write_text("Prove_LW_ID,NGS_LW_ID\n0001,SEQ1\n")
        return True

    config = {"master": str(master), "metadata": None, "metadata_name": "metadata.csv",
              "metadata_names": ("metadata.csv", "metadata.xls", "metadata.xlsx"),
              "metadata_smb": SimpleNamespace(get_if_exists=get_if_exists), "nonempty_report": False}
    if len(available) == 1:
        assert updater.update(config, report, "fasta", fasta=fasta)["added"] == 1
    else:
        with pytest.raises(updater.MergeError, match="metadata file"):
            updater.update(config, report, "fasta", fasta=fasta)
        assert master.read_text() == "Prove_LW_ID\n"
        assert not master.with_suffix(".fasta").exists()
        assert not list(tmp_path.glob("*.bak.*"))


def test_remote_access_failure_is_not_missing_metadata(updater, tmp_path):
    remote = updater.SMB("//mock/share", "INF-AVIAN", "unused")
    def failed_get(*args):
        raise updater.SMBError("get", ["NT_STATUS_ACCESS_DENIED"], 1)
    remote.get = failed_get
    with pytest.raises(updater.SMBError, match="ACCESS_DENIED"):
        updater.local_metadata({"metadata": None, "metadata_name": "metadata.csv",
                                "metadata_names": ("metadata.csv", "metadata.xls"), "metadata_smb": remote}, tmp_path)


@pytest.mark.parametrize("case", ["numeric_id", "formula", "sheets", "duplicate_headers", "empty"])
def test_invalid_excel_metadata_does_not_change_either_archive(updater, tmp_path, case):
    openpyxl = pytest.importorskip("openpyxl")
    master, report, fasta = local_inputs(tmp_path)
    book = openpyxl.Workbook()
    if case != "empty":
        book.active.append(["Prove_LW_ID", "Prove_LW_ID" if case == "duplicate_headers" else "Note"])
        book.active.append([1 if case == "numeric_id" else "0001", "=1+1" if case == "formula" else "text"])
    if case == "sheets":
        book.create_sheet("Other")
    book.save(tmp_path / "metadata.xlsx")
    config, _ = updater.profile_configuration({"AVIANSEQ_MASTER_CSV": str(master)}, profile="avian")
    with pytest.raises(updater.MergeError):
        updater.update(config, report, "fasta", fasta=fasta)
    assert master.read_text() == "Prove_LW_ID\n"
    assert not master.with_suffix(".fasta").exists()
    assert not list(tmp_path.glob("*.bak.*"))


def test_excel_sheet_override_and_identifier_audit(updater, tmp_path):
    openpyxl = pytest.importorskip("openpyxl")
    master, report, _ = local_inputs(tmp_path)
    book = openpyxl.Workbook()
    sheet = book.create_sheet("Metadata")
    sheet.append(["Prove_LW_ID", "NGS_LW_ID"])
    sheet.append(["0001", "SEQ1"])
    book.save(tmp_path / "metadata.xlsx")
    config, _ = updater.profile_configuration({"AVIANSEQ_MASTER_CSV": str(master),
                                               "AVIANSEQ_METADATA_SHEET": "Metadata"}, profile="avian")
    assert updater.check_identifiers(config, report, workflow="fasta") == []
    assert master.read_text() == "Prove_LW_ID\n"


def test_xls_adapter_preserves_text_identifiers(updater, tmp_path, monkeypatch):
    reader = importlib.import_module("read_metadata")
    rows = [[SimpleNamespace(ctype=1, value=value) for value in row]
            for row in [["Prove_LW_ID", "NGS_LW_ID"], ["0001", "SEQ1"]]]
    released = []
    book = SimpleNamespace(sheet_names=lambda: ["Metadata"],
                           sheet_by_name=lambda name: SimpleNamespace(get_rows=lambda: iter(rows)),
                           release_resources=lambda: released.append(True))
    monkeypatch.setitem(sys.modules, "xlrd", SimpleNamespace(open_workbook=lambda *args, **kwargs: book,
                                                            XL_CELL_ERROR=5, XL_CELL_DATE=3))
    headers, records = reader.read_excel_metadata(tmp_path / "metadata.xls")
    assert headers == ["Prove_LW_ID", "NGS_LW_ID"]
    assert records == [{"Prove_LW_ID": "0001", "NGS_LW_ID": "SEQ1"}]
    assert released == [True]


@pytest.mark.parametrize("mode,options,expected", [(None, [], "true"), ("false", [], "false"),
                                                   ("true", ["-M"], "false"),
                                                   ("true", ["--skip-master"], "false")])
def test_wrapper_preflight_before_external_work(tmp_path, mode, options, expected):
    tools = tmp_path / "tools/bin"
    tools.mkdir(parents=True)
    (tools / "update_master_csv.py").write_text(
        "import os,sys\nprint(os.environ['AVIANSEQ_MASTER_UPDATE'])\nprint(' '.join(sys.argv[1:]))\nsys.exit(73)\n")
    env = {key: value for key, value in os.environ.items() if not key.startswith("AVIANSEQ_")}
    env.update(HOME=str(tmp_path / "home"), AVIANSEQ_MASTER_TOOLS=str(tools.parent), FLUSEQ_MASTER_UPDATE="false")
    if mode:
        env["AVIANSEQ_MASTER_UPDATE"] = mode
    result = subprocess.run(["bash", str(ROOT / "avianseq_fasta_wrapper.sh"), "--run=DEMO", "-s", "SesTEST",
                             "-y2026", *options], env=env, text=True, capture_output=True, timeout=15)
    assert result.returncode == 73, result.stdout + result.stderr
    assert result.stdout.splitlines()[0] == expected
    assert "--profile avian --workflow fasta --validation  --check-config" in result.stdout


def test_wrapper_merge_failure_prevents_cleanup(tmp_path):
    source = (ROOT / "avianseq_fasta_wrapper.sh").read_text()
    block = source[source.index("# Merge only the completed run report"):]
    script = 'set -euo pipefail\npython3() { printf "%s\\n" "$@"; return 73; }\n' + block
    sampledir = tmp_path / "input"
    sampledir.mkdir()
    env = dict(os.environ, MASTER_CSV_TOOLS=str(BIN.parent), RUN="DEMO", VALIDATION_FLAG="", SAMPLEDIR=str(sampledir))
    result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
    assert result.returncode == 73
    assert sampledir.is_dir()
    args = result.stdout.splitlines()
    assert args[args.index("--profile") + 1] == "avian"
    assert args[args.index("--report") + 1].endswith("/DEMO/reporthuman/DEMO.csv")
    assert args[args.index("--fasta") + 1].endswith("/DEMO/reporthuman/DEMO.fasta")
