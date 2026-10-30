"""QC reporting checks use synthetic identifiers, measurements and qPCR results."""

import csv
import importlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "master_csv/bin"


@pytest.fixture
def qc(monkeypatch):
    monkeypatch.syspath_prepend(str(BIN))
    return importlib.import_module("report_qc_html")


def sample(identifier="001", **changes):
    row = {"Sample": identifier, "RunID": "DEMO", "Date": "2026-10-30", "Instrument ID": "SYNTHETIC",
           "Release Version": "test", "Subtype": "H3N2", "Sekvens_Resultat": "A/H3N2",
           "NGS_QC_Sum": "", "GISAID_Comment": "", "IRMA_noise": "0.01"}
    for segment in ("HA", "NA", "MP", "NP", "NS", "PA", "PB1", "PB2"):
        row[f"Coverage-{segment}"] = "100"
        row[f"DEPTH_{segment}"] = "1000"
    for protein in ("HA1", "HA2", "M1", "M2", "NA", "NP", "NS", "PA", "PB1", "PB2"):
        row[f"Nextclade QC {protein}"] = "good"
        row[f"Nextclade Mixed Sites {protein}"] = "0"
        row[f"aaDeletions {protein}"] = "No aaDeletions"
        row[f"aaInsertions {protein}"] = "No aaInsertions"
        row[f"frameShifts {protein}"] = "No frameShifts"
    row.update(changes)
    return row


def write_csv(path, rows, delimiter=","):
    fields = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter=delimiter)
        writer.writeheader()
        writer.writerows(rows)
    return path


@pytest.mark.parametrize(("results", "call", "status"), [
    ({"PCR_H3_Res": "  PÅvist  "}, "A/H3N2", "Match"),
    ({"PCR_H1_Res": "Påvist"}, "A/H3N2", "Mismatch"),
    ({"PCR_H1_Res": "Påvist"}, "A/H1N1", "Match"),
    ({"PCR_Bvic_Res": "påvist"}, "B/Victoria", "Match"),
    ({"PCR_Byam_Res": "Påvist"}, "B/Victoria", "Mismatch"),
    ({"PCR_H3_Res": "Ikke påvist"}, "A/H3N2", "No positive subtype qPCR"),
    ({"PCR_H3_Res": "Positiv"}, "A/H3N2", "Unrecognised qPCR result"),
    ({"PCR_H1_Res": "Påvist", "PCR_H3_Res": "Påvist"}, "A/H3N2", "Multiple qPCR calls"),
    ({"PCR_H3_Res": "Påvist"}, "NA", "No sequence call"),
    ({}, "A/H3N2", "qPCR unavailable"),
])
def test_qpcr_uses_pavist_and_assay_resolution(qc, tmp_path, results, call, status):
    path = write_csv(tmp_path / "run.csv", [sample(Sekvens_Resultat=call)])
    master = [{"Key": "0008", "NGS_LW_ID": "001", **results}]
    record = qc.build_report(path, master)["samples"][0]
    assert record["qpcr"]["status"] == status
    assert record["flags"]["mismatch"] == (status == "Mismatch")


def test_run_and_segment_denominators_include_failed_samples(qc, tmp_path):
    path = write_csv(tmp_path / "run.csv", [sample(), sample("002", Sekvens_Resultat="NA", **{"Coverage-HA": "79.99"}),
                                             sample("003", Subtype="unassigned", Sekvens_Resultat="", **{"Coverage-HA": "NA"})])
    report = qc.build_report(path)
    assert report["counts"]["called"] == 1
    assert report["counts"]["failed"] == 2
    assert report["segments"]["HA"] == {"passed": 1, "low_coverage": 1, "missing_or_invalid": 1,
        "median_coverage": 89.995, "median_segment_reads": 1000, "segment_reads_available": 3}
    assert report["samples"][1]["raw_subtype"] == "H3N2"
    assert report["samples"][1]["called_subtype"] == ""


@pytest.mark.parametrize(("raw", "passed", "low", "missing"), [
    ("80", 1, 0, 0), ("79,99", 0, 1, 0), ("0", 0, 1, 0), ("NA", 0, 0, 1),
    ("101", 0, 0, 1), ("nan", 0, 0, 1), ("-1", 0, 0, 1),
])
def test_coverage_boundary_and_missing(qc, tmp_path, raw, passed, low, missing):
    report = qc.build_report(write_csv(tmp_path / "run.csv", [sample(**{"Coverage-HA": raw})]))
    counts = report["segments"]["HA"]
    assert (counts["passed"], counts["low_coverage"], counts["missing_or_invalid"]) == (passed, low, missing)


@pytest.mark.parametrize(("value", "flag"), [("3", False), ("4", False), ("5", True), ("NA", False)])
def test_segment_mixed_counts_are_not_doubled(qc, value, flag):
    row = sample(**{"Nextclade Mixed Sites HA1": value, "Nextclade Mixed Sites HA2": value,
                    "Nextclade Mixed Sites M1": value, "Nextclade Mixed Sites M2": value})
    record = qc.summarise_sample(row, list(row))
    assert record["flags"]["mixed"] == flag
    assert record["mixed_sites"]["HA"]["value"] == (None if value == "NA" else int(value))
    assert record["mixed_sites"]["MP"]["value"] == (None if value == "NA" else int(value))


def test_conflicting_copies_remain_visible(qc):
    row = sample(**{"Nextclade Mixed Sites HA1": "3", "Nextclade Mixed Sites HA2": "6"})
    record = qc.summarise_sample(row, list(row))
    assert record["mixed_sites"]["HA"]["conflict"]
    assert record["mixed_sites"]["HA"]["value"] == 6
    assert any("Conflicting" in reason for reason in record["review_reasons"])


@pytest.mark.parametrize(("raw", "flag"), [("0.09", False), ("0,09", False), ("0.09001", True),
                                           ("0,10", True), ("NA", False), ("inf", False)])
def test_noise_strict_threshold(qc, raw, flag):
    row = sample(IRMA_noise=raw)
    assert qc.summarise_sample(row, list(row))["flags"]["noise"] == flag


def test_indels_deduplicate_and_keep_type_and_source(qc):
    row = sample(**{"aaDeletions HA1": "HA1:10-12;HA2:20-21", "aaDeletions HA2": "HA1:10-12;HA2:20-21",
                    "aaInsertions NA": "NA:20:ABC", "frameShifts PB1": "PB1:9-10"})
    record = qc.summarise_sample(row, list(row))
    assert len(record["indels"]) == 4
    assert record["indels"][0]["columns"] == ["aaDeletions HA1", "aaDeletions HA2"]
    assert {e["kind"] for e in record["indels"]} == {"Deletion", "Insertion", "Frameshift"}
    assert len(record["indel_assessed_segments"]) == 8


def test_fasta_joins_original_name_and_does_not_use_old_master_qc(qc, tmp_path):
    row = sample("internal-id", OriginalName="000123", IRMA_noise="NA", **{"Coverage-HA": "NA"})
    master = [{"Key": "000123", "NGS_LW_ID": "another-run", "PCR_H3_Res": "Påvist",
               "NGS_IRMA_noise": "0.5", "NGS_Coverage_HA": "100"}]
    result = qc.build_report(write_csv(tmp_path / "fasta.csv", [row]), master, workflow="fasta")["samples"][0]
    assert result["sample"] == "000123"
    assert result["qpcr"]["status"] == "Match"
    assert result["coverage"]["HA"] is None
    assert result["noise"] is None


def test_ambiguous_master_identifiers_fail(qc, tmp_path):
    path = write_csv(tmp_path / "run.csv", [sample()])
    with pytest.raises(ValueError, match="duplicate NGS_LW_ID"):
        qc.build_report(path, [{"NGS_LW_ID": "001"}, {"NGS_LW_ID": "001"}])


def test_offline_html_escapes_inputs_and_omits_unrelated_master_data(qc, tmp_path):
    attack = '<script>alert("x")</script>@@TOTAL@@'
    path = write_csv(tmp_path / "run.csv", [sample(attack, **{"aaDeletions NA": attack})], ";")
    master = write_csv(tmp_path / "master.csv", [{"NGS_LW_ID": attack, "Key": "0008", "PCR_H1_Res": "Påvist",
        "Pasient_No": "SECRET-PATIENT"}, {"NGS_LW_ID": "OTHER", "Key": "0089", "Pasient_No": "OTHER-PATIENT"}], ";")
    before = master.read_bytes()
    output = tmp_path / "report.html"
    qc.write_report(path, output, master)
    text = output.read_text()
    assert attack not in text
    assert qc.esc(attack) in text
    assert text.count("<script>") == 1
    assert "<script src=" not in text and "<link " not in text
    assert "SECRET-PATIENT" not in text + output.with_suffix(".json").read_text()
    assert "OTHER-PATIENT" not in text + output.with_suffix(".json").read_text()
    assert master.read_bytes() == before
    assert 'data-qpcr="Mismatch"' in text
    script = re.search(r"<script>(.*?)</script>", text, re.S)[1]
    if shutil.which("node"):
        result = subprocess.run(["node", "--check"], input=script, text=True, capture_output=True)
        assert result.returncode == 0, result.stderr


def test_cli_and_empty_report(qc, tmp_path):
    source = tmp_path / "empty.csv"
    source.write_text("Sample,Subtype\n")
    result = subprocess.run([sys.executable, str(BIN / "report_qc_html.py"), str(source), "--outdir", str(tmp_path)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "0/0 (not assessable)" in (tmp_path / "empty_qc.html").read_text()
    assert json.loads((tmp_path / "empty_qc.json").read_text())["counts"]["samples"] == 0


def test_merge_creates_qc_with_new_metadata_and_regenerates_on_retry(qc, tmp_path):
    updater = importlib.import_module("update_master_csv")
    master = tmp_path / "master.csv"
    master.write_text("Key\n")
    write_csv(tmp_path / "NGS_PREP_INF_report.csv", [{"RekvNr": "0008", "NGS_LW_ID": "001", "PCR_H1_Res": "Påvist"}], ";")
    source = write_csv(tmp_path / "run.csv", [sample()])
    config, _ = updater.configuration({"FLUSEQ_MASTER_CSV": str(master)})
    output = tmp_path / "run_qc.html"
    stats = updater.update(config, source, "fastq", output)
    assert stats["written"]
    assert json.loads(output.with_suffix(".json").read_text())["samples"][0]["qpcr"]["status"] == "Mismatch"
    output.unlink()
    stats = updater.update(config, source, "fastq", output)
    assert not stats["written"]
    assert output.is_file()


def test_disabled_merge_still_generates_qc_without_master(qc, tmp_path):
    source = write_csv(tmp_path / "run.csv", [sample()])
    output = tmp_path / "run_qc.html"
    result = subprocess.run([sys.executable, str(BIN / "update_master_csv.py"), "--workflow", "fastq",
        "--report", str(source), "--qc-output", str(output)], env={**os.environ, "FLUSEQ_MASTER_UPDATE": "false"},
        capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads(output.with_suffix(".json").read_text())["samples"][0]["qpcr"]["status"] == "No master match"


@pytest.mark.parametrize("workflow", ["fastq", "fasta"])
@pytest.mark.parametrize("corrupt_upload", [False, True])
def test_smb_merge_and_verified_qc_upload(qc, tmp_path, workflow, corrupt_upload):
    remote = tmp_path / "remote"
    (remote / "master").mkdir(parents=True)
    (remote / "results").mkdir()
    (remote / "master/master.csv").write_text("Key\n")
    write_csv(remote / "master/NGS_PREP_INF_report.csv", [
        {"RekvNr": "0008", "NGS_LW_ID": "001", "PCR_H1_Res": "Påvist"}], ";")
    source = write_csv(tmp_path / "run.csv", [sample(OriginalName="0008")])
    run_fasta = tmp_path / "run.fasta"
    run_fasta.write_text(">001|01-HA-H3N2\nACGT\n")
    auth = tmp_path / "auth"
    auth.touch()
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    smbclient = bin_dir / "smbclient"
    smbclient.write_text(f"#!{sys.executable}\n" + '''
import os, pathlib, shlex, shutil, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ['MOCK_SMB_ROOT']) / args[args.index('-D') + 1]
verb, *values = shlex.split(args[args.index('-c') + 1])
if verb == 'get':
    if not (root / values[0]).exists():
        print('NT_STATUS_OBJECT_NAME_NOT_FOUND', file=sys.stderr)
        sys.exit(1)
    shutil.copyfile(root / values[0], values[1])
elif verb == 'put':
    target = root / values[1]
    shutil.copyfile(values[0], target)
    if os.environ.get('CORRUPT_QC') == 'true' and target.suffix == '.json':
        target.write_text('corrupted upload')
elif verb == 'mkdir':
    (root / values[0]).mkdir()
elif verb == 'rmdir':
    (root / values[0]).rmdir()
elif verb == 'rename':
    (root / values[0]).replace(root / values[1])
else:
    raise ValueError(verb)
''')
    smbclient.chmod(0o755)
    output = tmp_path / "run_qc.html"
    env = {key: value for key, value in os.environ.items() if not key.startswith("FLUSEQ_")}
    env.update(PATH=str(bin_dir) + os.pathsep + env.get("PATH", ""), MOCK_SMB_ROOT=str(remote),
               CORRUPT_QC=str(corrupt_upload).lower(), FLUSEQ_MASTER_UPDATE="true",
               FLUSEQ_MASTER_SMB_SHARE="//mock/share", FLUSEQ_MASTER_SMB_DIR="master",
               FLUSEQ_MASTER_SMB_AUTH=str(auth))
    command = [sys.executable, str(BIN / "update_master_csv.py"), "--workflow", workflow,
               "--report", str(source), "--fasta", str(run_fasta), "--qc-output", str(output), "--qc-smb-share", "//mock/share",
               "--qc-smb-dir", "results", "--qc-smb-auth", str(auth)]
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    assert (result.returncode != 0) == corrupt_upload, result.stdout + result.stderr
    if corrupt_upload:
        assert "SMB upload verification failed" in result.stderr
        assert output.is_file()  # Keep the good local output for retry.
    else:
        assert (remote / "results/run_qc.html").read_bytes() == output.read_bytes()
        assert (remote / "results/run_qc.json").read_bytes() == output.with_suffix(".json").read_bytes()
        data = json.loads(output.with_suffix(".json").read_text())
        assert data["samples"][0]["qpcr"]["status"] == "Mismatch"
        assert data["master_source"] == "master.csv"
    assert not (remote / "master/master.csv.lock").exists()
    assert not (remote / "master/master.fasta.lock").exists()
    assert (remote / "master/master.fasta").read_bytes() == run_fasta.read_bytes()


def test_wrapper_passes_workflow_and_qc_destinations(wrapper, tmp_path):
    source = wrapper.read_text()
    start = source.index('# Merge only the completed run report')
    end = source.index('--qc-smb-auth "$SMB_AUTH"', start) + len('--qc-smb-auth "$SMB_AUTH"')
    script = 'set -euo pipefail\npython3() { printf "%s\\n" "$@"; }\n' + source[start:end]
    env = dict(os.environ, MASTER_CSV_TOOLS=str(BIN.parent), RUN="DEMO", VALIDATION_FLAG="", SMB_HOST="//mock/share",
               SMB_AUTH="mock-auth", SMB_DIR="results", SMB_DIR_ANALYSIS="analysis", SKIP_RESULTS_MOVE="false")
    result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    args = result.stdout.splitlines()
    assert args[args.index("--workflow") + 1] == ("fasta" if "fasta" in wrapper.name else "fastq")
    assert args[args.index("--qc-output") + 1].endswith("/DEMO/reporthuman/DEMO_qc.html")
    assert args[args.index("--fasta") + 1].endswith("/DEMO/reporthuman/DEMO.fasta")
    assert args[args.index("--qc-smb-dir") + 1] == "results/DEMO/reporthuman"
    env["SKIP_RESULTS_MOVE"] = "true"
    result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    args = result.stdout.splitlines()
    assert args[args.index("--qc-smb-dir") + 1] == "analysis"
