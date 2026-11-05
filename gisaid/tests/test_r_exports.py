"""R-only exporters and parity with the frozen Sequence Review JavaScript reader."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest
from test_approved_exports import GISAID, approved, make_dataset, review, write_csv


def r_approved(master, pathogen='SC2', token=None):
    code = ('a <- commandArgs(TRUE); source(a[1]); '
            's <- read_approved_master(a[2], a[3]); '
            's$original_rows <- NULL; '
            's$headers <- as.list(s$headers); s$identity_headers <- as.list(s$identity_headers); '
            'cat(jsonlite::toJSON(s, auto_unbox=TRUE, dataframe="rows", null="null"))')
    if token:
        code = 'a <- commandArgs(TRUE); source(a[1]); assert_approved_master(a[2], a[3], a[4])'
    return subprocess.run(['Rscript', '-e', code, str(GISAID / 'shared/approval.R'), str(master), pathogen,
                           *([token] if token else [])], capture_output=True, text=True,
                          env={**os.environ, 'GISAID_NODE': '/missing/node', 'TZ': 'UTC'}, timeout=30)


def assert_parity(master, pathogen='SC2'):
    reference = approved(master, pathogen)
    result = r_approved(master, pathogen)
    assert result.returncode == reference.returncode, result.stderr + reference.stderr
    if not reference.returncode:
        assert json.loads(result.stdout) == json.loads(reference.stdout)
    return result


@pytest.mark.parametrize('pathogen', ['INF', 'SC2'])
def test_r_approval_states_hashes_overrides_and_snapshot_match_reference(tmp_path, pathogen):
    master, rows = make_dataset(tmp_path, pathogen, 8)
    rows[0].update(Pasient_Fylke_Name='Møre og Romsdal', Comment='Quotes "x"; pipe|\r\nnew line\t😀/ø\\')
    rows[0]['\ue000'] = 'private use'
    rows[0]['😀'] = 'astral header sorts before private use in JS'
    write_csv(master, rows)
    review(master, rows[0], 'current', overrides={'NGS_Sekvens_Resultat': 'B/Victoria'})
    review(master, rows[1], 'stale', stale=True)
    review(master, rows[2], 'rejected', assessment='Rejected')
    review(master, rows[3], 'conflict1')
    review(master, rows[3], 'conflict2')
    review(master, rows[4], 'old')
    review(master, rows[4], 'followup', assessment='Needs follow-up', supersedes=['old'])
    review(master, rows[5], 'old1')
    review(master, rows[5], 'old2')
    review(master, rows[5], 'resolved', supersedes=['old1', 'old2'])
    # The test helper uses Python's codepoint sort: obtain JS's UTF-16 hash here.
    event = master.parent / 'reviews/current.json'
    data = json.loads(event.read_text())
    pairs = sorted(([k, v] for k, v in rows[0].items() if k != 'Prove_LW_ID' and v != ''),
                   key=lambda pair: pair[0].encode('utf-16-be'))
    data['result_hash'] = 'sha256:' + hashlib.sha256(json.dumps(pairs, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    event.write_text(json.dumps(data))
    # Include a hidden review filename, like the directory reader in Node.
    review(master, rows[7], 'hidden').rename(master.parent / 'reviews/.hidden.json')
    result = assert_parity(master, pathogen)
    assert json.loads(result.stdout)['counts'] == dict(total=8, approved=3, pending=1, stale=1, conflict=1, not_approved=2)


@pytest.mark.parametrize('legacy,composite', [(False, False), (False, True), (True, False), (True, True)])
def test_r_identity_and_legacy_migration_match_reference(tmp_path, legacy, composite):
    master, rows = make_dataset(tmp_path)
    config_path = master.with_name('config.json')
    config = json.loads(config_path.read_text())
    original = ['Key', 'NGS_LW_ID'] if composite else ['Key']
    current = ['Prove_LW_ID', 'NGS_LW_ID'] if composite else ['Prove_LW_ID']
    config['key_columns'] = original if legacy else current
    config_path.write_text(json.dumps(config))
    review(master, rows[0], 'review', overrides={'NGS_Sekvens_Resultat': 'B/Victoria'})
    if legacy:
        config.update(key_columns=current, legacy_key_columns=original)
        config_path.write_text(json.dumps(config))
    result = assert_parity(master)
    assert json.loads(result.stdout)['counts']['approved'] == 1


@pytest.mark.parametrize('failure', ['config', 'reviews', 'malformed-json', 'wrong-pathogen', 'missing-parent',
                                    'unknown-policy', 'unsupported-override', 'identity-override', 'cycle',
                                    'duplicate-event', 'bad-time', 'bad-key-columns', 'duplicate-key',
                                    'unclosed-quote', 'unquoted-quote', 'after-quote', 'short-row',
                                    'invalid-utf8', 'duplicate-header', 'legacy-missing-mapping'])
def test_r_reader_fails_closed_like_reference(tmp_path, failure):
    master, rows = make_dataset(tmp_path)
    event_path = review(master, rows[0], 'current')
    event = json.loads(event_path.read_text())
    changes = {
        'wrong-pathogen': {'pathogen': 'INF'}, 'missing-parent': {'supersedes': ['missing']},
        'unknown-policy': {'policy_version': 'unknown'}, 'bad-time': {'created_at': 'garbage'},
        'bad-key-columns': {'key_columns': ['Wrong']},
        'unsupported-override': {'review': {**event['review'], 'overrides': {'NGS_LW_ID': 'other'}}},
        'identity-override': {'review': {**event['review'], 'overrides': {'Prove_LW_ID': 'other'}}},
    }
    if failure in changes:
        event.update(changes[failure]); event_path.write_text(json.dumps(event))
    elif failure == 'config':
        master.with_name('config.json').unlink()
    elif failure == 'reviews':
        shutil.rmtree(event_path.parent)
    elif failure == 'malformed-json':
        event_path.write_text('{')
    elif failure == 'cycle':
        event['supersedes'] = ['second']; event_path.write_text(json.dumps(event))
        review(master, rows[0], 'second', supersedes=['current'])
    elif failure == 'duplicate-event':
        shutil.copyfile(event_path, event_path.with_name('other.json'))
    elif failure == 'duplicate-key':
        write_csv(master, [rows[0], rows[0]])
    elif failure in {'unclosed-quote', 'unquoted-quote', 'after-quote', 'short-row'}:
        suffix = {'unclosed-quote': '"broken', 'unquoted-quote': 'broken"field',
                  'after-quote': '"closed"extra', 'short-row': 'short'}[failure]
        with master.open('a') as handle:
            handle.write(suffix + '\n')
    elif failure == 'invalid-utf8':
        master.write_bytes(master.read_bytes() + b'\xff')
    elif failure == 'duplicate-header':
        master.write_text('Prove_LW_ID;Prove_LW_ID\n001;001\n')
    elif failure == 'legacy-missing-mapping':
        cfg = json.loads(master.with_name('config.json').read_text())
        cfg['legacy_key_columns'] = ['Key']; master.with_name('config.json').write_text(json.dumps(cfg))
        event.update(key='missing', key_columns=['Key']); event_path.write_text(json.dumps(event))
    reference = approved(master)
    assert reference.returncode != 0
    result = r_approved(master)
    assert result.returncode != 0, result.stdout
    assert 'no submission was written' in result.stderr


def test_r_rechecks_review_and_master_changes(tmp_path):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    before = json.loads(assert_parity(master).stdout)
    rows[0]['NC_Coverage'] = '0.96'; write_csv(master, rows)
    changed = assert_parity(master)
    assert json.loads(changed.stdout)['counts']['stale'] == 1
    result = r_approved(master, token=before['token'])
    assert result.returncode != 0 and 'changed during export' in result.stderr


def r_sc2_command(master, tmp_path, extra=()):
    return ['Rscript', str(GISAID / 'sars-cov-2/sc2_gisaid_csv.R'), 'RUN', 'synthetic-submitter',
            '--master', str(master), '--lab-lookup', str(tmp_path / 'labs.csv'),
            '--output-dir', str(tmp_path / 'r-output'), '--prefix', 'synthetic',
            '--assembly-method', 'Synthetic test method', *extra]


def run_r_sc2(master, tmp_path, extra=()):
    return subprocess.run(r_sc2_command(master, tmp_path, extra), capture_output=True, text=True,
                          env={**os.environ, 'GISAID_NODE': '/missing/node', 'TZ': 'UTC'}, timeout=60)


def test_r_sc2_matches_python_submission_fasta_manifest_and_refuses_overwrite(tmp_path):
    from test_approved_exports import sc2_command
    master, rows = make_dataset(tmp_path, count=8)
    rows[1]['GISAID_Kommentar'] = 'hold'; rows[2]['NC_Coverage'] = '0.74'
    rows[3]['NGS_Run_ID'] = 'OTHER'; rows[4]['Key'] = ''; rows[7]['NC_Coverage'] = '0,75'
    write_csv(master, rows)
    for i in [0, 1, 2, 3, 4, 6, 7]:
        review(master, rows[i], f'event{i}', stale=(i == 6))
    before = {p: p.read_bytes() for p in master.parent.rglob('*') if p.is_file()}
    reference = subprocess.run(sc2_command(master, tmp_path), capture_output=True, text=True)
    assert reference.returncode == 0, reference.stderr
    result = run_r_sc2(master, tmp_path)
    assert result.returncode == 0, result.stdout + result.stderr
    for suffix in ['csv', 'fasta']:
        assert (tmp_path / f'r-output/synthetic.{suffix}').read_bytes() == (tmp_path / f'output/synthetic.{suffix}').read_bytes()
    manifest = json.loads((tmp_path / 'r-output/synthetic.manifest.json').read_text())
    assert manifest == json.loads((tmp_path / 'output/synthetic.manifest.json').read_text())
    assert all(p.read_bytes() == content for p, content in before.items())
    previous = {p: p.read_bytes() for p in (tmp_path / 'r-output').iterdir()}
    retry = run_r_sc2(master, tmp_path)
    assert retry.returncode != 0 and 'already exists' in retry.stderr
    assert all(p.read_bytes() == content for p, content in previous.items())


@pytest.mark.parametrize('failure', ['unapproved', 'manual-hold', 'missing-sequence', 'duplicate-sequence',
                                    'multiple-aliases', 'ambiguous-master-id', 'bad-date', 'missing-lab',
                                    'duplicate-lab', 'duplicate-name', 'all-low-coverage', 'bad-prefix'])
def test_r_sc2_validation_failure_writes_no_submission(tmp_path, failure):
    count = 2 if failure in {'ambiguous-master-id', 'duplicate-name'} else 1
    master, rows = make_dataset(tmp_path, count=count)
    if failure == 'ambiguous-master-id': rows[1]['NGS_LW_ID'] = 'SEQ0'
    if failure == 'duplicate-name': rows[1]['Key'] = '242500000'
    if failure == 'bad-date': rows[0]['Prove_Tatt'] = '2026-02-31'
    if failure == 'unapproved': rows[0]['NGS_QC_Assessment'] = 'Approved'
    if failure == 'all-low-coverage': rows[0]['NC_Coverage'] = '0.749'
    write_csv(master, rows)
    if failure != 'unapproved':
        for i, row in enumerate(rows):
            review(master, row, f'event{i}', overrides={'GISAID_Kommentar': 'hold'} if failure == 'manual-hold' else {})
    fasta = master.with_name('master.fasta')
    if failure == 'missing-sequence': fasta.write_text('>unrelated\nACGT\n')
    if failure == 'duplicate-sequence': fasta.write_text(fasta.read_text() * 2)
    if failure == 'multiple-aliases': fasta.write_text(fasta.read_text() + f">{rows[0]['Key']}\nACGT\n")
    if failure in {'missing-lab', 'duplicate-lab'}:
        write_csv(tmp_path / 'labs.csv', [{'Innsender_nr': 'other' if failure == 'missing-lab' else '001',
                                        'Innsender_navn': 'Test'}] * (2 if failure == 'duplicate-lab' else 1))
    command = r_sc2_command(master, tmp_path)
    if failure == 'bad-prefix':
        command[command.index('--prefix') + 1] = '../escape'
    result = subprocess.run(command, capture_output=True, text=True, timeout=60,
                            env={**os.environ, 'GISAID_NODE': '/missing/node', 'TZ': 'UTC'})
    assert result.returncode != 0, result.stdout
    assert not (tmp_path / 'r-output').exists()


@pytest.mark.parametrize('field', ['Key', 'Prove_LW_ID', 'OriginalName', 'SampleID'])
def test_r_sc2_matches_exact_original_fasta_aliases(tmp_path, field):
    master, rows = make_dataset(tmp_path)
    if field in {'OriginalName', 'SampleID'}:
        rows[0][field] = 'original-name'; write_csv(master, rows)
    review(master, rows[0], 'current')
    master.with_name('master.fasta').write_text(f">{rows[0][field]} synthetic description\nACGT\n")
    result = run_r_sc2(master, tmp_path)
    assert result.returncode == 0, result.stderr
    manifest = json.loads((tmp_path / 'r-output/synthetic.manifest.json').read_text())
    assert manifest['approvals'][0]['fasta_id'] == rows[0][field]


@pytest.mark.parametrize('launch', ['source', 'source-wrapper', 'console'])
def test_r_sc2_runs_from_rstudio_and_paths_with_spaces(tmp_path, launch):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    checkout = tmp_path / 'checkout with spaces'
    shutil.copytree(GISAID / 'shared', checkout / 'gisaid/shared')
    (checkout / 'gisaid/sars-cov-2').mkdir()
    for file in ['sc2_gisaid_csv.R', 'sc2_export.R']:
        shutil.copyfile(GISAID / 'sars-cov-2' / file, checkout / 'gisaid/sars-cov-2' / file)
    script = checkout / 'gisaid/sars-cov-2/sc2_gisaid_csv.R'
    env = {**os.environ, 'GISAID_NODE': '/missing/node', 'TEST_SCRIPT': str(script), 'TZ': 'UTC'}
    env.pop('GISAID_SHARED_DIR', None)
    command = r_sc2_command(master, tmp_path)
    code = 'gisaid_args <- unlist(jsonlite::fromJSON(' + json.dumps(json.dumps(command[2:])) + ')); '
    code += 'source(Sys.getenv("TEST_SCRIPT"), encoding="UTF-8")' if launch.startswith('source') else 'eval(parse(text=readLines(Sys.getenv("TEST_SCRIPT"))))'
    cmd = ['Rscript', '-e', code]
    if launch == 'source-wrapper':
        wrapper = tmp_path / 'outer script.R'; wrapper.write_text(code)
        cmd = ['Rscript', str(wrapper)]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=checkout if launch == 'console' else tmp_path,
                            env=env, timeout=60)
    assert result.returncode == 0, result.stderr
    assert (tmp_path / 'r-output/synthetic.manifest.json').exists()


def test_r_sc2_rechecks_approval_and_removes_owned_files_on_write_failure(tmp_path):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    module = GISAID / 'sars-cov-2/sc2_export.R'
    code = ('a <- commandArgs(TRUE); source(a[1]); source(a[2]); args <- sc2_gisaid_defaults(); '
            'args$master <- a[3]; args$lab_lookup <- a[4]; args$output_dir <- a[5]; '
            'args$run <- "RUN"; args$submitter <- "TEST"; args$assembly_method <- "Synthetic"; args$prefix <- "synthetic"; '
            'original <- assert_approved_master; assert_approved_master <- function(master, pathogen, token) { '
            'cat("\\n", file=master, append=TRUE); original(master, pathogen, token) }; export_sc2_gisaid(args)')
    result = subprocess.run(['Rscript', '-e', code, str(GISAID / 'shared/approval.R'), str(module), str(master),
                             str(tmp_path / 'labs.csv'), str(tmp_path / 'r-output')], capture_output=True, text=True, timeout=60)
    assert result.returncode != 0 and 'changed during export' in result.stderr
    assert not (tmp_path / 'r-output').exists()
    # Fail the second write, after the CSV is created; remove only this attempt's CSV.
    code = code[:code.index('original <- assert_approved_master;')] + (
        'original <- file; file <- function(description, open="", ...) { '
        'if (endsWith(description,"synthetic.fasta") && open == "wxb") stop("simulated write failure"); '
        'original(description, open, ...) }; export_sc2_gisaid(args)')
    result = subprocess.run(['Rscript', '-e', code, str(GISAID / 'shared/approval.R'), str(module), str(master),
                             str(tmp_path / 'labs.csv'), str(tmp_path / 'r-output')], capture_output=True, text=True, timeout=60)
    assert result.returncode != 0 and 'simulated write failure' in result.stderr
    assert not list((tmp_path / 'r-output').iterdir())


@pytest.mark.parametrize('timestamp,valid', [
    ('2026-02-04T12:00:00.123Z', True), ('2026-02-04T12:00+01:00', True),
    ('2026-02-04T24:00:00Z', True), ('2026-02-04', True),
    ('2026-02-04T12:00:00+99:99', False), ('2026-02-04T25:00:00Z', False),
    ('2026-02-04T12:00:61Z', False), ('2026-02-04T24:01:00Z', False),
])
def test_r_review_timestamps_match_persisted_iso_format(tmp_path, timestamp, valid):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current', created_at=timestamp)
    result = assert_parity(master)
    assert (result.returncode == 0) == valid


def test_r_review_cannot_supply_internal_legacy_identity_flag(tmp_path):
    master, rows = make_dataset(tmp_path)
    cfg_path = master.with_name('config.json')
    config = json.loads(cfg_path.read_text()); config['legacy_key_columns'] = ['Key']
    cfg_path.write_text(json.dumps(config))
    pairs = sorted([k, v] for k, v in rows[0].items() if k != 'Key' and v != '')
    legacy_hash = 'sha256:' + hashlib.sha256(json.dumps(pairs, separators=(',', ':')).encode()).hexdigest()
    review(master, rows[0], 'forged-flag', result_hash=legacy_hash, gisaid_legacy_identity=True)
    result = assert_parity(master)
    assert json.loads(result.stdout)['counts']['stale'] == 1


@pytest.mark.parametrize('policy,valid', [(None, False), ('v2', True), ('unknown', False)])
def test_r_current_and_legacy_manual_field_policies(tmp_path, policy, valid):
    master, rows = make_dataset(tmp_path)
    cfg_path = master.with_name('config.json')
    config = json.loads(cfg_path.read_text())
    config.update(review_policy_version='v2', legacy_edit_columns=['NGS_Sekvens_Resultat'])
    cfg_path.write_text(json.dumps(config))
    changes = {'policy_version': policy} if policy else {}
    review(master, rows[0], 'current', overrides={'GISAID_Kommentar': 'manual hold'}, **changes)
    result = assert_parity(master)
    assert (result.returncode == 0) == valid


def test_r_detects_input_change_during_approval_loading(tmp_path):
    master, rows = make_dataset(tmp_path)
    review(master, rows[0], 'current')
    code = ('a <- commandArgs(TRUE); source(a[1]); original <- gisaid_read_snapshot; calls <- 0L; '
            'gisaid_read_snapshot <- function(master) {calls <<- calls+1L; '
            'if (calls == 2L) cat("\\n", file=master, append=TRUE); original(master)}; '
            'read_approved_master(a[2], "SC2")')
    result = subprocess.run(['Rscript', '-e', code, str(GISAID / 'shared/approval.R'), str(master)],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode != 0 and 'changed while reading' in result.stderr
