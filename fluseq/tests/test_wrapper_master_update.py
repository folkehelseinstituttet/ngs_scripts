"""Check the master-update mode passed by each wrapper to its preflight."""

import os
import subprocess

import pytest


@pytest.mark.parametrize(
    ("inherited_mode", "options", "expected"),
    [
        (None, [], "true"),
        ("", [], "true"),
        ("false", [], "false"),
        ("auto", [], "auto"),
        ("true", ["-M"], "false"),
    ],
)
def test_wrapper_master_update_mode(wrapper, tmp_path, inherited_mode, options, expected):
    home = tmp_path / "home"
    conda = home / "miniconda3/etc/profile.d/conda.sh"
    conda.parent.mkdir(parents=True)
    conda.write_text(":\n")
    tools = tmp_path / "tools/bin"
    tools.mkdir(parents=True)
    # Stop at the first preflight, before any network or pipeline activity.
    (tools / "update_master_csv.py").write_text(
        "import os, sys\n"
        "print('MASTER_MODE=' + os.environ['FLUSEQ_MASTER_UPDATE'], flush=True)\n"
        "sys.exit(73)\n"
    )
    env = dict(os.environ, HOME=str(home), FLUSEQ_MASTER_TOOLS=str(tools.parent),
               CONDA_PROFILE=str(conda), WRAPPER_LOG_DIR=str(tmp_path / "logs"))
    env.pop("FLUSEQ_MASTER_UPDATE", None)
    if inherited_mode is not None:
        env["FLUSEQ_MASTER_UPDATE"] = inherited_mode
    args = ["bash", str(wrapper), "-r", "INFTEST", "-s", "SesTEST", "-y", "2026"]
    if wrapper.name == "fluseq_wrapper.sh":
        args.append("-t")
    result = subprocess.run(args + options, env=env, text=True, capture_output=True, timeout=15)
    assert result.returncode == 73, result.stdout + result.stderr
    assert f"MASTER_MODE={expected}" in result.stdout
