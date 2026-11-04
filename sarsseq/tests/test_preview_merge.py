import importlib.util
from copy import deepcopy
from pathlib import Path
import subprocess
import sys

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'master_csv/preview_merge.py'
spec = importlib.util.spec_from_file_location('preview_merge', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def table(*rows):
    return list(dict.fromkeys(name for row in rows for name in row)), list(rows)


def empty():
    return ['Prove_LW_ID', 'NGS_LW_ID'], []


def test_mapping_and_exact_join_preserve_other_rows():
    master = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'S1', 'Old': 'keep'},
                   {'Prove_LW_ID': '002', 'NGS_LW_ID': 'S2', 'Old': 'unchanged'})
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'S1', 'RekvNr': '0008', 'County': 'Trøndelag'})
    report = table({'Sample': 'S1', 'Result': 'NA'})
    headers, rows, stats = module.preview(master, metadata, report,
        {'metadata': {'RekvNr': 'Key'}, 'report': {'Sample': 'NGS_LW_ID'}})
    assert rows[0]['Key'] == '0008' and rows[0]['County'] == 'Trøndelag'
    assert rows[0]['Old'] == 'keep' and rows[0]['Result'] == 'NA'
    assert rows[1] == master[1][1]
    assert stats['total_rows'] == 2


def test_conflicting_identifiers_fail():
    with pytest.raises(ValueError, match='disagree'):
        module.preview(table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'S1'}),
                       table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'S1'}),
                       table({'Prove_LW_ID': '002', 'NGS_LW_ID': 'S1'}))


def test_preview_never_overwrites_inputs_or_existing_output(tmp_path):
    master, metadata, report, output = [tmp_path / name for name in ('master.csv', 'metadata.csv', 'report.csv', 'preview.csv')]
    for path in (master, metadata, report):
        path.write_text('Prove_LW_ID;NGS_LW_ID\n001;S1\n', encoding='utf-8')
    original = master.read_bytes()
    command = [sys.executable, str(SCRIPT), '--master', str(master), '--metadata', str(metadata), '--report', str(report)]
    result = subprocess.run(command + ['--output', str(master)], capture_output=True, text=True)
    assert result.returncode != 0 and master.read_bytes() == original
    subprocess.run(command + ['--output', str(output)], check=True, capture_output=True)
    before = output.read_bytes()
    result = subprocess.run(command + ['--output', str(output)], capture_output=True)
    assert result.returncode != 0 and output.read_bytes() == before
    assert master.read_bytes() == original


def test_metadata_mapping_matches_influenza_without_collapsing_keys():
    from merge_master_csv import merge_tables
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1',
                      'Key': 'raw-key', 'RekvNr': 'legacy-key',
                      'Pasient_Kjonn': 'F', 'Prove_Maanad': '01',
                      'Prove_Sesong': '2526', 'Sesong': '2526',
                      'PCR_triplex_SC2_CT': '23,16', 'Future': 'text'})
    report = table({'Sample': 'SEQ1'})
    _, expected, _ = merge_tables(empty(), metadata, report, 'fastq')
    _, actual, _ = module.preview(empty(), metadata, report)
    assert actual == expected
    assert actual[0]['Key'] == 'legacy-key'
    assert actual[0]['Metadata_Key'] == 'raw-key'
    assert actual[0]['PCR_triplex_SC2_CT'] == '23,16'


@pytest.mark.parametrize('nonempty', [False, True])
def test_precedence_and_absent_columns_match_influenza(nonempty):
    from merge_master_csv import merge_tables
    master = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1',
                    'Value': 'old', 'BlankMeta': 'keep', 'Absent': 'keep',
                    'BlankReport': 'old', 'Literal': 'old', 'GISAID_Isolate_ID': 'existing'},
                   {'Prove_LW_ID': '002', 'NGS_LW_ID': 'SEQ2', 'Value': 'untouched'})
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1', 'Value': 'metadata',
                      'BlankMeta': '', 'BlankReport': 'metadata'},
                     {'Prove_LW_ID': '003', 'NGS_LW_ID': 'SEQ3'})
    report = table({'Sample': 'SEQ1', 'Value': 'report', 'BlankReport': '', 'Literal': 'NA'})
    _, expected, _ = merge_tables(master, metadata, report, 'fastq', nonempty_report=nonempty)
    _, actual, _ = module.preview(master, metadata, report, nonempty_report=nonempty)
    assert actual == expected
    assert len(actual) == 2
    assert actual[0]['BlankReport'] == ('metadata' if nonempty else '')
    assert actual[0]['Literal'] == 'NA'
    assert actual[0]['Absent'] == actual[0]['BlankMeta'] == 'keep'
    assert actual[1] == master[1][1]


@pytest.mark.parametrize('name', ['SEQ1', '001', 'legacy'])
def test_sars_fasta_sample_uses_influenza_exact_alias_matching(name):
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1', 'RekvNr': 'legacy'})
    _, rows, _ = module.preview(empty(), metadata, table({'Sample': name, 'coverage': '0.95'}), workflow='fasta')
    assert rows[0]['Prove_LW_ID'] == '001'
    assert rows[0]['NGS_LW_ID'] == 'SEQ1'
    assert rows[0]['OriginalName'] == name
    assert rows[0]['SampleID'] == name
    assert rows[0]['NC_Coverage'] == '0.95'


def test_sars_columns_and_legacy_sequence_name():
    master = table({'Prove_LW_ID': '001', 'NGS_Sekvens_ID': 'SEQ1'})
    report = table({'Sample': 'SEQ1', 'RunID': 'RUN1', 'Date': '2026-01-01',
                    'Primer': 'version', 'Instrument ID': 'instrument',
                    'Release Version': 'release', 'NGS_Script_vers': 'tools',
                    'coverage': '0.95', 'coverage_stats': '0.96',
                    'NC_Genome_QC': 'good', 'NC_Genome_MixedSites': '0',
                    'NGS_QC_Sum': '', 'GISAID_Comment': '', 'GISAID_Kommentar': '',
                    'FutureReport': 'keep'})
    headers, rows, _ = module.preview(master, empty(), report)
    row = rows[0]
    assert row['NGS_LW_ID'] == 'SEQ1'
    assert 'NGS_Sekvens_ID' not in headers
    assert row['NC_Coverage'] == '0.95' and row['coverage_stats'] == '0.96'
    assert row['NGS_Run_ID'] == 'RUN1' and row['NGS_Script_dato'] == '2026-01-01'
    assert row['NGS_Script_vers'] == 'tools' and row['Release Version'] == 'release'
    assert row['FutureReport'] == 'keep'
    assert 'NGS_Coverage_HA' not in headers


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_fallback_reindexed_when_metadata_arrives(workflow):
    report = table({'Sample': '0009'})
    headers, rows, _ = module.preview(empty(), empty(), report, workflow=workflow)
    assert rows[0]['Prove_LW_ID'] == '0009'
    assert rows[0]['Master_Index_Source'] == 'Sequence_ID'
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': '0009', 'RekvNr': 'legacy'})
    _, updated, stats = module.preview((headers, rows), metadata, report, workflow=workflow)
    assert len(updated) == 1 and updated[0]['Prove_LW_ID'] == '001'
    assert updated[0]['Master_Index_Source'] == 'Prove_LW_ID'
    assert stats['reindexed'] == 1


@pytest.mark.parametrize(('master', 'metadata', 'report', 'workflow', 'message'), [
    (empty(), empty(), table({'Sample': 'A'}, {'Sample': 'A'}), 'fastq', 'duplicate'),
    (table({'Prove_LW_ID': 'A'}), empty(), table({'Sample': 'A'}), 'fastq', 'collides'),
    (empty(), table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'A'},
                    {'Prove_LW_ID': '002', 'NGS_LW_ID': 'A'}), table({'Sample': 'A'}), 'fastq', 'multiple'),
    (empty(), table({'Prove_LW_ID': '001', 'RekvNr': 'same'},
                    {'Prove_LW_ID': '002', 'RekvNr': 'same'}), table({'Sample': 'same'}), 'fasta', 'ambiguous'),
    (empty(), table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'A', 'RekvNr': 'legacy'},
                    {'Prove_LW_ID': '002', 'NGS_LW_ID': 'B'}),
     table({'OriginalName': 'legacy', 'SampleID': 'B'}), 'fasta', 'disagree'),
    (empty(), table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'A', 'Sesong': 'a', 'Prove_Sesong': 'b'}),
     table({'Sample': 'A'}), 'fastq', 'conflicting columns'),
    (empty(), empty(), table({'Sample': 'A', 'GISAID_Comment': 'a', 'GISAID_Kommentar': 'b'}),
     'fastq', 'conflicting columns'),
    (empty(), empty(), empty(), 'fastq', 'at least one'),
])
def test_identifier_and_mapping_conflicts_fail(master, metadata, report, workflow, message):
    with pytest.raises(ValueError, match=message):
        module.preview(master, metadata, report, workflow=workflow)


@pytest.mark.parametrize('column', ['Master_Index_Source', 'Master_Key_Source'])
def test_reserved_provenance_rejected_even_in_empty_input(column):
    with pytest.raises(ValueError, match='reserved'):
        module.preview(empty(), (['Prove_LW_ID', column], []), table({'Sample': 'A'}))


def test_cli_fasta_default_mappings(tmp_path):
    master, metadata, report, output = [tmp_path / name for name in ('master.csv', 'metadata.csv', 'report.csv', 'out.csv')]
    master.write_text('Prove_LW_ID\n')
    metadata.write_text('Prove_LW_ID;NGS_LW_ID;Key;RekvNr\n001;SEQ1;raw;legacy\n')
    report.write_text('Sample;RunID\nlegacy;RUN1\n')
    subprocess.run([sys.executable, str(SCRIPT), '--master', str(master), '--metadata', str(metadata),
                    '--report', str(report), '--output', str(output), '--workflow', 'fasta'],
                   check=True, capture_output=True, text=True)
    _, rows = module.read_table(output)
    assert rows[0]['Prove_LW_ID'] == '001' and rows[0]['Metadata_Key'] == 'raw'


@pytest.mark.parametrize('workflow', ['fastq', 'fasta'])
def test_known_text_repairs_match_flu_without_changing_sources(workflow):
    from merge_master_csv import merge_tables
    master = table(
        {'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1', 'Pasient_Fylke_Name': 'old',
         'PCR_SC2_EXT_Res': 'old', 'PCR_SC2_EXT_CT': '23,16', 'Note': 'P vist'},
        {'Prove_LW_ID': '002', 'NGS_LW_ID': 'SEQ2', 'Pasient_Fylke_Name': 'M re g Romsdal',
         'PCR_SC2_EXT_Res': 'P vist', 'Note': 'M re g Romsdal'},
        {'Prove_LW_ID': '003', 'NGS_LW_ID': 'SEQ3', 'Pasient_Fylke_Name': ' stfold',
         'PCR_SC2_EXT_Res': 'Mulig p vist'},
        {'Prove_LW_ID': '004', 'NGS_LW_ID': 'SEQ4', 'Pasient_Fylke_Name': 'MÃ¸re og Romsdal',
         'PCR_SC2_EXT_Res': 'PÃ¥vist', 'PCR_SC2_TRI_Res': 'Ikke pÃ¥vist'},
        {'Prove_LW_ID': '005', 'NGS_LW_ID': 'SEQ5', 'Pasient_Fylke_Name': 'Trøndelag',
         'PCR_SC2_EXT_Res': 'Påvist', 'PCR_SC2_TRI_Res': 'Ikke påvist'},
        {'Prove_LW_ID': '006', 'NGS_LW_ID': 'SEQ6', 'Pasient_Fylke_Name': 'Ukjent fylke',
         'PCR_SC2_EXT_Res': 'P�vist', 'PCR_SC2_TRI_Res': 'NA'},
        {'Prove_LW_ID': '007', 'NGS_LW_ID': 'SEQ7', 'Pasient_Fylke_Name': 'Værøy æøa\u030a ÆØA\u030a',
         'PCR_SC2_EXT_Res': 'Pa\u030avist'},
    )
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1',
                      'Pasient_Fylke_Name': ' TR  NDELAG ', 'PCR_SC2_EXT_Res': 'P vist',
                      'PCR_triplex_SC2_Res': 'p vist'},
                     {'Prove_LW_ID': '008', 'NGS_LW_ID': 'SEQ8', 'Pasient_Fylke_Name': ' stfold'})
    report = table({'Sample' if workflow == 'fastq' else 'OriginalName': 'SEQ1' if workflow == 'fastq' else '001',
                    'PCR_SC2_EXT_Res': ' IKKE P  VIST '})
    original = deepcopy((master, metadata, report))
    _, rows, stats = module.preview(master, metadata, report, workflow=workflow)
    _, flu_rows, flu_stats = merge_tables(master, metadata, report, workflow)
    assert rows == flu_rows
    assert stats['text_repaired'] == flu_stats['text_repaired'] == 5
    assert (master, metadata, report) == original
    assert [row['Pasient_Fylke_Name'] for row in rows] == [
        'Trøndelag', 'Møre og Romsdal', 'Østfold', 'Møre og Romsdal',
        'Trøndelag', 'Ukjent fylke', 'Værøy æøå ÆØÅ']
    assert rows[0]['PCR_SC2_EXT_Res'] == rows[3]['PCR_SC2_TRI_Res'] == 'Ikke påvist'
    assert rows[0]['PCR_triplex_SC2_Res'] == rows[1]['PCR_SC2_EXT_Res'] == 'Påvist'
    assert rows[3]['PCR_SC2_EXT_Res'] == rows[6]['PCR_SC2_EXT_Res'] == 'Påvist'
    assert rows[0]['PCR_SC2_EXT_CT'] == '23,16'
    assert rows[0]['Note'] == 'P vist' and rows[1]['Note'] == 'M re g Romsdal'
    assert rows[2]['PCR_SC2_EXT_Res'] == 'Mulig p vist'
    assert rows[4] == original[0][1][4]  # Correct Norwegian text stays unchanged.
    assert rows[5]['PCR_SC2_EXT_Res'] == 'P�vist' and rows[5]['PCR_SC2_TRI_Res'] == 'NA'
    assert [row['Prove_LW_ID'] for row in rows] == [f'{i:03}' for i in range(1, 8)]


@pytest.mark.parametrize('nonempty', [False, True])
def test_text_repairs_follow_blank_precedence(nonempty):
    master = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1', 'PCR_SC2_EXT_Res': 'P vist'})
    metadata = table({'Prove_LW_ID': '001', 'NGS_LW_ID': 'SEQ1', 'PCR_SC2_EXT_Res': 'Ikke p vist'})
    _, rows, stats = module.preview(master, metadata, table({'Sample': 'SEQ1', 'PCR_SC2_EXT_Res': ''}),
                                    nonempty_report=nonempty)
    assert rows[0]['PCR_SC2_EXT_Res'] == ('Ikke påvist' if nonempty else '')
    assert stats['text_repaired'] == int(nonempty)
