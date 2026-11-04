"""Schema inspection must not include any data cells."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "master_csv" / "inspect_schemas.py"
spec = importlib.util.spec_from_file_location("inspect_schemas", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


@pytest.mark.parametrize(("encoding", "delimiter"), [("utf-8-sig", ";"), ("cp1252", ","), ("utf-16", "\t")])
def test_only_headers_and_case_insensitive_overlap(tmp_path, encoding, delimiter):
    source = tmp_path / "source.csv"
    source.write_bytes((f'Key{delimiter}Påvist\nSECRET_SAMPLE{delimiter}private\n').encode(encoding))
    other = tmp_path / "other.csv"
    other.write_text("KEY;Status\nSECRET_SAMPLE;private\n", encoding="utf-8")
    result = subprocess.run([sys.executable, str(SCRIPT), "--report", str(source), "--master", str(other)],
                            capture_output=True, text=True, check=True)
    parsed = json.loads(result.stdout)
    assert parsed["columns"]["report"] == ["Key", "Påvist"]
    assert parsed["shared_columns"]["report_and_master"] == ["Key"]
    assert "SECRET_SAMPLE" not in result.stdout and "private" not in result.stdout


def test_duplicate_header_is_rejected(tmp_path):
    source = tmp_path / "data.csv"
    source.write_text("Key;key\n1;2\n", encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate"):
        module.read_headers(source)
