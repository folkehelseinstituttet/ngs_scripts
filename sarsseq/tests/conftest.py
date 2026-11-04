"""Synthetic SMB publishing endpoint; tests never contact shared storage."""

import os
import sys

import pytest


@pytest.fixture
def qc_smb_env(tmp_path):
    root = tmp_path / 'mock SMB'
    for directory in ('results/SART001/report', 'validation'):
        (root / directory).mkdir(parents=True)
    auth = tmp_path / 'mock auth'
    auth.touch()
    binaries = tmp_path / 'mock bin'
    binaries.mkdir()
    client = binaries / 'smbclient'
    client.write_text(f'#!{sys.executable}\n' + '''
import os, pathlib, shlex, shutil, sys
args = sys.argv[1:]
assert args[0] == '//unused/share'
assert args[args.index('-A') + 1] == os.environ['QC_TEST_AUTH']
directory = args[args.index('-D') + 1]
root = pathlib.Path(os.environ['QC_TEST_ROOT']) / directory
verb, *values = shlex.split(args[args.index('-c') + 1])
name = values[1] if verb == 'put' else values[0]
with open(os.environ['EVENTS'], 'a') as log:
    log.write(f'qc {verb} {directory}/{name}\\n')
fault = os.environ.get('QC_TEST_FAULT', '')
if pathlib.Path(name).suffix == os.environ.get('QC_TEST_SUFFIX', '.json'):
    if fault == verb + '-exit':
        sys.exit(17)
    if fault == verb + '-status':
        print('NT_STATUS_ACCESS_DENIED', file=sys.stderr)
        sys.exit(0)
if verb == 'put':
    shutil.copyfile(values[0], root / values[1])
elif verb == 'get':
    if fault == 'corrupt' and pathlib.Path(name).suffix == os.environ.get('QC_TEST_SUFFIX', '.json'):
        pathlib.Path(values[1]).write_text('corrupted readback')
    else:
        shutil.copyfile(root / values[0], values[1])
else:
    raise ValueError(verb)
''')
    client.chmod(0o755)
    return dict(PATH=str(binaries) + os.pathsep + os.environ['PATH'], QC_TEST_ROOT=str(root),
                QC_TEST_AUTH=str(auth), SMB_AUTH=str(auth), EVENTS=str(tmp_path / 'events'))
