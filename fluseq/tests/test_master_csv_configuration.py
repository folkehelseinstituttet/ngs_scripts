"""Check metadata lookup using synthetic files and isolated SMB configuration."""

import importlib
from pathlib import Path
import subprocess

import pytest


@pytest.fixture
def updater(monkeypatch):
    monkeypatch.syspath_prepend(str(Path(__file__).resolve().parents[1] / "master_csv/bin"))
    return importlib.import_module("update_master_csv")


@pytest.fixture
def master(tmp_path):
    path = tmp_path / "shared directory" / "master.csv"
    path.parent.mkdir()
    path.write_text("Key\n")
    return path


@pytest.mark.parametrize("workflow", ["fastq", "fasta"])
@pytest.mark.parametrize("override", [False, True])
def test_mounted_merge_uses_sibling_or_explicit_metadata(updater, master, tmp_path, monkeypatch, workflow, override):
    # Mounted inputs must work without smbclient or its authentication file.
    monkeypatch.setattr(updater.shutil, "which", lambda name: None)
    metadata = master.with_name("NGS_PREP_INF_report.csv")
    metadata.write_text("RekvNr;Prove_LW_ID;NGS_LW_ID;Note\n001;P001;SEQ1;sibling\n")
    environ = {"FLUSEQ_MASTER_CSV": str(master)}
    if override:
        metadata = tmp_path / "separate.csv"
        metadata.write_text("RekvNr;Prove_LW_ID;NGS_LW_ID;Note\n001;P001;SEQ1;override\n")
        environ["FLUSEQ_METADATA_CSV"] = str(metadata)
        environ["FLUSEQ_METADATA_SMB_SHARE"] = "//unused/share"
    report = tmp_path / "report.csv"
    report.write_text("Sample\nSEQ1\n" if workflow == "fastq" else "OriginalName\n001\n")

    config, reason = updater.configuration(environ)
    assert reason is None
    stats = updater.update(config, report, workflow)

    assert stats["added"] == 1
    assert stats["without_metadata"] == 0
    _, rows = updater.read_table(master)
    assert rows[0]["Key"] == "001"
    assert rows[0]["Prove_LW_ID"] == "P001"
    assert rows[0]["Note"] == ("override" if override else "sibling")
    assert Path(stats["backup"]).read_text() == "Key\n"


def test_missing_sibling_metadata_fails_before_update(updater, master):
    with pytest.raises(updater.MergeError, match="Configured metadata CSV does not exist"):
        updater.configuration({"FLUSEQ_MASTER_CSV": str(master)})
    assert master.read_text() == "Key\n"
    assert not list(master.parent.glob("*.bak.*"))


@pytest.mark.parametrize("custom_master", [False, True])
@pytest.mark.parametrize("override_metadata", [False, True])
def test_smb_metadata_inherits_master_location_unless_overridden(
    updater, tmp_path, monkeypatch, custom_master, override_metadata,
):
    auth = tmp_path / "auth"
    auth.touch()
    monkeypatch.setattr(updater.shutil, "which", lambda name: "/mock/smbclient")
    environ = {"FLUSEQ_MASTER_UPDATE": "true", "FLUSEQ_MASTER_SMB_AUTH": str(auth)}
    share, directory = updater.MASTER_SHARE, updater.MASTER_DIR
    if custom_master:
        share, directory = "//custom/master", "custom directory/INF"
        environ.update(FLUSEQ_MASTER_SMB_SHARE=share, FLUSEQ_MASTER_SMB_DIR=directory)
    if override_metadata:
        share, directory = "//separate/metadata", "Prod/FromSecure/LW_Datauttrekk"
        auth = tmp_path / "metadata-auth"
        auth.touch()
        environ.update(FLUSEQ_METADATA_SMB_SHARE=share, FLUSEQ_METADATA_SMB_DIR=directory,
                       FLUSEQ_METADATA_SMB_AUTH=str(auth))
    config, reason = updater.configuration(environ)
    assert reason is None
    local = tmp_path / "download.csv"
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        local.write_text("RekvNr\n001\n")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(updater.subprocess, "run", run)
    config["metadata_smb"].get(config["metadata_name"], local)
    assert calls == [["smbclient", share, "-A", str(auth), "-D", directory,
                      "-c", f'get "NGS_PREP_INF_report.csv" "{local}"']]


def test_mounted_master_can_use_explicit_metadata_share(updater, master, tmp_path, monkeypatch):
    auth = tmp_path / "auth"
    auth.touch()
    monkeypatch.setattr(updater.shutil, "which", lambda name: "/mock/smbclient")
    config, _ = updater.configuration({
        "FLUSEQ_MASTER_CSV": str(master),
        "FLUSEQ_METADATA_SMB_SHARE": "//separate/metadata",
        "FLUSEQ_METADATA_SMB_DIR": "export",
        "FLUSEQ_METADATA_SMB_AUTH": str(auth),
    })
    assert config["master_smb"] is None
    assert config["metadata"] is None
    assert config["metadata_smb"].share == "//separate/metadata"
    assert config["metadata_smb"].directory == "export"


@pytest.mark.parametrize(("environ", "validation"), [
    ({}, ""),
    ({"FLUSEQ_MASTER_UPDATE": "false"}, ""),
    ({"FLUSEQ_MASTER_UPDATE": "true"}, "VER"),
])
def test_unconfigured_disabled_and_validation_runs_still_skip(updater, environ, validation):
    config, reason = updater.configuration(environ, validation)
    assert config is None
    assert reason
