"""FASTA archive merging uses synthetic records and simulated SMB transfers."""

import importlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


BIN = Path(__file__).resolve().parents[1] / "master_csv/bin"


@pytest.fixture
def fasta(monkeypatch):
    monkeypatch.syspath_prepend(str(BIN))
    return importlib.import_module("merge_master_fasta")


def write(path, content):
    path.write_text(content)
    return path


def test_add_replace_and_preserve_distinct_samples_and_segments(fasta, tmp_path):
    master = write(tmp_path / "master.fasta", ">001|HA old\nACGT\n>001|NA\nAAAA\n>002|HA\nCCCC\n")
    incoming = write(tmp_path / "run.fasta", ">001|HA latest\nACGA\n>001|NA\nAAAA\n>003|HA\nCCCC\n")
    before = master.read_bytes()
    records, duplicates = fasta.read_fasta(incoming)
    stats = fasta.merge_local(master, records, duplicates)
    merged, _ = fasta.read_fasta(master)
    assert list(merged) == ["001|HA", "001|NA", "002|HA", "003|HA"]
    assert merged["001|HA"] == ("001|HA latest", "ACGA")
    assert merged["001|NA"][1] == "AAAA"
    assert merged["002|HA"][1] == merged["003|HA"][1] == "CCCC"
    assert (stats["added"], stats["updated"], stats["unchanged"]) == (1, 1, 1)
    assert Path(stats["backup"]).read_bytes() == before
    assert not master.with_name("master.fasta.lock").exists()


def test_identical_retry_preserves_original_format_and_has_no_backup(fasta, tmp_path):
    master = tmp_path / "master.fasta"
    master.write_bytes(b">001|HA\r\nAC\r\nGT\r\n")
    incoming = write(tmp_path / "run.fasta", ">001|HA\nACGT\n")
    before = master.read_bytes()
    stats = fasta.merge_local(master, fasta.read_fasta(incoming)[0])
    assert not stats["written"] and stats["unchanged"] == 1
    assert master.read_bytes() == before
    assert not list(tmp_path.glob("*.bak.*"))


def test_identical_duplicates_are_collapsed(fasta, tmp_path):
    master = write(tmp_path / "master.fasta", ">001|HA\nACGT\n>001|HA\nACGT\n")
    records, duplicates = fasta.read_fasta(master)
    stats = fasta.merge_local(master, records, duplicates)
    assert stats["master_duplicates_collapsed"] == stats["input_duplicates_collapsed"] == 1
    assert master.read_text().count(">") == 1


@pytest.mark.parametrize("text", ["ACGT\n", ">\nACGT\n", ">001|HA\n", ">001|HA\nAC1T\n",
                                ">001|HA\nACGT\n>001|HA\nAAAA\n"])
def test_invalid_or_conflicting_fasta_is_rejected(fasta, tmp_path, text):
    path = write(tmp_path / "bad.fasta", text)
    with pytest.raises(ValueError):
        fasta.read_fasta(path)


def test_create_master_and_empty_input(fasta, tmp_path):
    master = tmp_path / "master.fasta"
    assert fasta.merge_local(master, {})["skipped"]
    assert not master.exists()
    incoming = {"001|HA": ("001|HA", "ACGT")}
    stats = fasta.merge_local(master, incoming)
    assert stats["created"] and stats["written"]
    assert not list(tmp_path.glob("*.bak.*"))
    assert fasta.read_fasta(master)[0] == incoming
    assert not fasta.merge_local(master, incoming)["written"]


def test_existing_lock_prevents_update(fasta, tmp_path):
    master = write(tmp_path / "master.fasta", ">001|HA\nACGT\n")
    lock = tmp_path / "master.fasta.lock"
    lock.mkdir()
    with pytest.raises(ValueError, match="locked"):
        fasta.merge_local(master, {"002|HA": ("002|HA", "AAAA")})
    assert lock.exists()
    assert master.read_text() == ">001|HA\nACGT\n"


def test_concurrent_change_is_not_overwritten(fasta, tmp_path, monkeypatch):
    master = write(tmp_path / "master.fasta", ">001|HA\nACGT\n")
    original_writer = fasta.write_fasta

    def concurrent_writer(path, records):
        original_writer(path, records)
        master.write_text(">OTHER|NA\nCCCC\n")

    monkeypatch.setattr(fasta, "write_fasta", concurrent_writer)
    with pytest.raises(ValueError, match="changed during merge"):
        fasta.merge_local(master, {"002|HA": ("002|HA", "AAAA")})
    assert master.read_text() == ">OTHER|NA\nCCCC\n"


@pytest.fixture
def remote(fasta, tmp_path):
    updater = importlib.import_module("update_master_csv")

    class FakeSMB(updater.SMB):
        directory_path = tmp_path / "remote"
        calls = []
        corrupt_upload = False
        concurrent_create = False

        def command(self, verb, *arguments):
            self.calls.append(verb)
            target = self.directory_path / arguments[0]
            if verb == "get":
                if not target.exists():
                    raise updater.SMBError("get", ["NT_STATUS_OBJECT_NAME_NOT_FOUND"], 1)
                shutil.copyfile(target, arguments[1])
            elif verb == "put":
                destination = self.directory_path / arguments[1]
                shutil.copyfile(arguments[0], destination)
                if self.corrupt_upload and ".tmp." in destination.name:
                    destination.write_text("broken transfer")
            elif verb == "mkdir":
                target.mkdir()
            elif verb == "rmdir":
                target.rmdir()
            elif verb == "rename":
                destination = self.directory_path / arguments[1]
                if self.concurrent_create:
                    destination.write_text(">OTHER|HA\nCCCC\n")
                if len(arguments) < 3 and destination.exists():
                    raise updater.SMBError("rename", ["NT_STATUS_OBJECT_NAME_COLLISION"], 1)
                target.replace(destination)
            else:
                raise AssertionError(verb)

    result = FakeSMB("//mock/share", "data", "mock-auth")
    result.directory_path.mkdir()
    return result


@pytest.mark.parametrize("exists", [False, True])
def test_remote_create_replace_and_idempotent_retry(fasta, remote, exists):
    master = remote.directory_path / "master.fasta"
    if exists:
        master.write_text(">001|HA\nACGT\n>002|NA\nAAAA\n")
    before = master.read_bytes() if exists else None
    incoming = {"001|HA": ("001|HA new", "ACGA"), "003|HA": ("003|HA", "CCCC")}
    stats = fasta.merge_remote(remote, "master.fasta", incoming)
    assert stats["created"] == (not exists)
    assert fasta.read_fasta(master)[0]["001|HA"][1] == "ACGA"
    if exists:
        assert (remote.directory_path / stats["backup"]).read_bytes() == before
        assert "002|NA" in fasta.read_fasta(master)[0]
    remote.calls.clear()
    assert not fasta.merge_remote(remote, "master.fasta", incoming)["written"]
    assert "put" not in remote.calls and "rename" not in remote.calls
    assert not (remote.directory_path / "master.fasta.lock").exists()


def test_remote_corrupt_upload_preserves_master(fasta, remote):
    master = write(remote.directory_path / "master.fasta", ">001|HA\nACGT\n")
    remote.corrupt_upload = True
    with pytest.raises(ValueError, match="upload verification failed"):
        fasta.merge_remote(remote, "master.fasta", {"001|HA": ("001|HA", "AAAA")})
    assert master.read_text() == ">001|HA\nACGT\n"
    assert "rename" not in remote.calls
    assert not (remote.directory_path / "master.fasta.lock").exists()


def test_remote_concurrent_initializer_is_not_overwritten(fasta, remote):
    remote.concurrent_create = True
    with pytest.raises(ValueError, match="OBJECT_NAME_COLLISION"):
        fasta.merge_remote(remote, "master.fasta", {"001|HA": ("001|HA", "AAAA")})
    assert (remote.directory_path / "master.fasta").read_text() == ">OTHER|HA\nCCCC\n"


@pytest.mark.parametrize("status", ["NT_STATUS_ACCESS_DENIED", "NT_STATUS_OBJECT_PATH_NOT_FOUND", "NT_STATUS_CONNECTION_DISCONNECTED"])
def test_remote_failure_is_not_treated_as_empty_master(fasta, remote, monkeypatch, status):
    updater = importlib.import_module("update_master_csv")
    original_command = remote.command

    def fail_get(verb, *args):
        if verb == "get":
            raise updater.SMBError(verb, [status], 1)
        original_command(verb, *args)

    monkeypatch.setattr(remote, "command", fail_get)
    with pytest.raises(ValueError, match=status):
        fasta.merge_remote(remote, "master.fasta", {"001|HA": ("001|HA", "AAAA")})
    assert "put" not in remote.calls
    assert not (remote.directory_path / "master.fasta").exists()


@pytest.mark.parametrize("workflow", ["fastq", "fasta"])
def test_csv_and_fasta_update_share_location(fasta, tmp_path, workflow):
    updater = importlib.import_module("update_master_csv")
    master = write(tmp_path / "master.csv", "Key\n")
    write(tmp_path / "NGS_PREP_INF_report.csv", "RekvNr;NGS_LW_ID\n0008;SEQ1\n")
    report = write(tmp_path / "run.csv", "Sample\nSEQ1\n" if workflow == "fastq" else "OriginalName\n0008\n")
    run_fasta = write(tmp_path / "run.fasta", ">SEQ1|01-HA-H3N2\nACGT\n")
    config, _ = updater.configuration({"FLUSEQ_MASTER_CSV": str(master)})
    stats = updater.update(config, report, workflow, fasta=run_fasta)
    assert stats["written"] and stats["fasta"]["added"] == 1
    assert (tmp_path / "master.fasta").read_text() == run_fasta.read_text()
    stats = updater.update(config, report, workflow, fasta=run_fasta)
    assert not stats["written"] and not stats["fasta"]["written"]


def test_malformed_run_fasta_stops_before_csv_write(fasta, tmp_path):
    updater = importlib.import_module("update_master_csv")
    master = write(tmp_path / "master.csv", "Key\n")
    write(tmp_path / "NGS_PREP_INF_report.csv", "RekvNr;NGS_LW_ID\n0008;SEQ1\n")
    report = write(tmp_path / "run.csv", "Sample\nSEQ1\n")
    incoming = write(tmp_path / "bad.fasta", ">EMPTY\n")
    config, _ = updater.configuration({"FLUSEQ_MASTER_CSV": str(master)})
    with pytest.raises(ValueError, match="empty FASTA sequence"):
        updater.update(config, report, "fastq", fasta=incoming)
    assert master.read_text() == "Key\n"
    assert not list(tmp_path.glob("*.bak.*"))


@pytest.mark.parametrize(("mode", "validation"), [("false", ""), ("true", "VER")])
def test_disabled_and_validation_runs_skip_fasta(fasta, tmp_path, mode, validation):
    result = subprocess.run([sys.executable, str(BIN / "update_master_csv.py"), "--workflow", "fastq",
        "--report", str(tmp_path / "absent.csv"), "--fasta", str(tmp_path / "absent.fasta"), "--validation", validation],
        env={**os.environ, "FLUSEQ_MASTER_UPDATE": mode}, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "skipped" in result.stdout
    assert not (tmp_path / "master.fasta").exists()
