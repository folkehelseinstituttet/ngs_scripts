"""Exercise the actual reference update block using an isolated SMB substitute."""

import os
from pathlib import Path
import re
import subprocess

import pytest


WRAPPER = Path(__file__).resolve().parents[1] / 'fluseq_wrapper.sh'
MOCK_SMB = r'''
smbclient() {
    [[ "$#" == 5 && "$1" == mock-host && "$2" == -A && "$3" == mock-auth && "$4" == -D ]]
    local remote="$5" kind local_dir='' line
    case "$remote" in
        "$EXPECTED_REMOTE/human") kind=human ;;
        "$EXPECTED_REMOTE/human_vaccine") kind=human_vaccine ;;
        "$EXPECTED_REMOTE") kind=table ;;
        *) echo "Unexpected SMB source: $remote" >&2; return 90 ;;
    esac
    printf '%s\n' "$kind" >> "$MOCK_LOG"
    while IFS= read -r line; do
        case "$line" in
            'lcd '*) local_dir="${line#lcd }" ;;
        esac
    done
    if [[ "$MOCK_FAIL" == "$kind" ]]; then
        return 91
    fi
    [[ -d "$local_dir" ]]
    if [[ "$kind" == table ]]; then
        cp "$MOCK_REMOTE/reference_table.csv" "$local_dir/"
    else
        [[ "$local_dir" == "$SEQUENCE_REFERENCES/$kind" ]]
        cp -R "$MOCK_REMOTE/$kind/." "$local_dir/"
    fi
}
'''


@pytest.mark.parametrize(('case', 'error'), [
    ('valid', None),
    ('missing_epi', 'Missing EPI identifier'),
    ('wrong_epi', 'Wrong EPI'),
    ('missing_vaccine_table_row', 'No reference-table entries'),
    ('empty_vaccine_directory', 'No FASTA files found'),
    ('failed_download_with_stale_files', None),
])
def test_reference_download(tmp_path, case, error):
    source = WRAPPER.read_text()
    validator = re.search(r'^validate_reference_type\(\) \{\n.*?^\}', source, re.M | re.S)[0]
    assignments = '\n'.join(line for line in source.splitlines() if re.match(
        r'^(?:HUMAN_REFERENCES|HUMAN_VACCINE_REFERENCES|REFERENCE_VALIDATION)=', line))
    start = source.index('echo "Updating human references"')
    end_line = 'validate_reference_type "$SEQUENCE_REFERENCES/human_vaccine" "human_vaccine" "$REFERENCE_TABLE_LOCAL_FILE"'
    end = source.index('\n' + end_line, start) + len('\n' + end_line)
    script = '\n'.join(['set -euo pipefail', 'shopt -s nullglob', validator,
                        MOCK_SMB, assignments, source[start:end], 'echo VALIDATION_COMPLETED'])
    remote = tmp_path / 'remote'
    local = tmp_path / 'database'
    (local / 'sequence_references/human').mkdir(parents=True)
    rows = ['Subtype;Reference;Type;GISAID_EPI',
            'H1N1;A/Test/1/2026;human;EPI_ISL_123456']
    if case != 'missing_vaccine_table_row':
        rows.append('H1N1;A/Test/2/2026;human_vaccine;EPI_ISL_234567')
    for kind, name, epi in [('human', 'A/Test/1/2026', 'EPI_ISL_123456'),
                            ('human_vaccine', 'A_Test_2_2026', 'EPI_ISL_234567')]:
        directory = remote / kind / 'H1N1'
        directory.mkdir(parents=True)
        for segment in ('HA1', 'HA2'):
            header = f'{name}|{epi}_{segment}'
            if kind == 'human_vaccine':
                if case == 'missing_epi':
                    header = f'{name}_{segment}'
                elif case == 'wrong_epi':
                    header = f'{name}|EPI_ISL_999999_{segment}'
                elif case == 'empty_vaccine_directory':
                    continue
            (directory / f'{segment}.fasta').write_text(f'>{header}\nACDE\n')
    (remote / 'reference_table.csv').write_text('\n'.join(rows) + '\n')
    if case == 'failed_download_with_stale_files':
        directory = local / 'sequence_references/human_vaccine/H1N1'
        directory.mkdir(parents=True)
        (directory / 'HA1.fasta').write_text('>A/Test/2/2026|EPI_ISL_234567_HA1\nACDE\n')
    env = dict(os.environ, FLU_DATABASE=str(local),
               SEQUENCE_REFERENCES=str(local / 'sequence_references'),
               REFERENCE_TABLE_LOCAL_FILE=str(local / 'reference_table.csv'),
               SEASON='SesTEST', SMB_HOST='mock-host', SMB_AUTH='mock-auth',
               EXPECTED_REMOTE='Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/Influensa/Sesongfiler/SesTEST/references',
               MOCK_REMOTE=str(remote), MOCK_LOG=str(tmp_path / 'smb.log'),
               MOCK_FAIL='human_vaccine' if case == 'failed_download_with_stale_files' else '')
    result = subprocess.run(['bash', '-c', script], env=env, text=True, capture_output=True, timeout=15)
    assert (result.returncode == 0) == (case == 'valid'), result.stdout + result.stderr
    assert ('VALIDATION_COMPLETED' in result.stdout) == (case == 'valid')
    if case == 'valid':
        assert 'Validated 2 human_vaccine FASTA files' in result.stdout
        for segment in ('HA1', 'HA2'):
            relative = Path('human_vaccine/H1N1') / f'{segment}.fasta'
            assert (local / 'sequence_references' / relative).read_bytes() == (remote / relative).read_bytes()
    if case == 'failed_download_with_stale_files':
        assert result.returncode == 91
        assert (tmp_path / 'smb.log').read_text().splitlines() == ['human', 'human_vaccine']
    else:
        assert (tmp_path / 'smb.log').read_text().splitlines() == ['human', 'human_vaccine', 'table']
    if error:
        assert error in result.stderr
