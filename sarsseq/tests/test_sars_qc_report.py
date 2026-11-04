"""SARS QC tests use synthetic report measurements, never sequence analysis."""

import csv
import importlib.util
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1] / 'master_csv'
sys.path.insert(0, str(ROOT))
import sars_qc_report as qc
import sars_qc_metrics as metrics

spec = importlib.util.spec_from_file_location('sars_qc_updater', ROOT / 'update_master.py')
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def sample(name='001', **changes):
    row = {'Sample': name, 'RunID': 'SYNTHETIC', 'Date': '2026-01-01', 'Instrument ID': 'Test instrument',
           'Primer': 'Test version', 'Release Version': 'test', 'NGS_Script_vers': 'test tools',
           'coverage': '0.95', 'QC_overall_pct': '95', 'NC_Genome_MixedSites': '0',
           'NC_Genome_QC': 'good', 'NC_Genome_frameShifts': 'No frameShifts',
           'Nextclade_pango': 'TEST.1', 'partiallyAliased': 'TEST.LONG.1', 'clade': 'TEST',
           'NGS_QC_Sum': '', 'GISAID_Comment': '', 'cdsCoverage': ';'.join(f'{gene}:1' for gene in metrics.GENES)}
    for gene in metrics.GENES:
        row[f'{gene}_aaDeletions'] = 'No mutation'
        row[f'{gene}_aaInsertions'] = 'No mutation'
    row.update(changes)
    return row


def csv_file(path, rows, fields=None):
    fields = fields or list(dict.fromkeys(key for row in rows for key in row))
    with path.open('w', encoding='utf-8-sig', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter=';')
        writer.writeheader()
        writer.writerows(rows)
    return path


def test_complete_sample_has_no_flags_and_omits_flu_metrics(tmp_path):
    report = qc.build_report(csv_file(tmp_path / 'run.csv', [sample()]))
    assert report['samples'][0]['qc_status'] == 'No flags'
    assert report['counts']['lineage_assigned'] == 1
    assert report['counts']['review'] == 0
    assert report['samples'][0]['coverage']['Genome'] == 95
    assert report['regions']['S']['passed'] == 1
    assert 'noise' not in report['samples'][0]
    assert 'segment_reads' not in report['samples'][0]


@pytest.mark.parametrize(('value', 'expected', 'low'), [('0.8', 80, False), ('0,7999', 79.99, True),
                                                     ('0', 0, True), ('1', 100, False), ('NA', None, False),
                                                     ('80', None, False), ('1.01', None, False),
                                                     ('-1', None, False), ('inf', None, False)])
def test_fraction_units_thresholds_and_invalid_primary(value, expected, low):
    result = metrics.summarise_sample(sample(coverage=value))
    actual = result['coverage']['Genome']
    assert actual == pytest.approx(expected) if expected is not None else actual is None
    assert ('Genome' in result['low_coverage_regions']) == low
    # The valid QC_overall_pct copy must not hide a missing/invalid primary value.
    assert ('Genome' in result['missing_coverage_regions']) == (expected is None)


def test_explicit_percent_and_conflicting_coverage_copies():
    row = sample(QC_overall_pct='1')
    row.pop('coverage')
    assert metrics.summarise_sample(row)['coverage']['Genome'] == 1
    result = metrics.summarise_sample(sample(coverage='0.6', coverage_stats='0.95'))
    assert result['coverage']['Genome'] == 60
    assert result['coverage_evidence']['Genome']['conflict']


@pytest.mark.parametrize('value', ['S:0.8;ORF1a:0.9', 'S:0.8,ORF1a:0.9', 'S:0,8;ORF1a:0,9'])
def test_cds_delimiters_and_decimal_comma(value):
    result = metrics.summarise_sample(sample(cdsCoverage=value))
    assert result['coverage']['S'] == 80 and result['coverage']['ORF1a'] == 90
    assert result['coverage']['ORF1b'] is None


def test_cds_missing_low_and_duplicate_entries_are_not_passes():
    result = metrics.summarise_sample(sample(cdsCoverage='S:0;ORF1a:0.7;ORF1a:0.9;ORF1b:bad;Unknown:1'))
    assert result['coverage']['S'] == 0
    assert result['coverage']['ORF1a'] is None and result['coverage']['ORF1b'] is None
    assert result['qc_status'] == 'Review'
    assert any('Conflicting cdsCoverage' in reason for reason in result['review_reasons'])


@pytest.mark.parametrize(('value', 'expected', 'flag'), [('3', 3, False), ('4', 4, True), ('0', 0, False),
                                                      ('3.5', None, False), ('NA', None, False), ('-1', None, False)])
def test_mixed_sites_not_summed_or_replaced_by_lower_priority(value, expected, flag):
    result = metrics.summarise_sample(sample(NC_Genome_MixedSites=value, **{'qc.mixedSites.totalMixedSites': '3'}))
    assert result['mixed_sites']['value'] == expected
    assert result['flags']['mixed'] == flag
    if value == '4':
        assert result['mixed_sites']['conflict']


@pytest.mark.parametrize(('raw', 'status'), [('', 'No flags'), ('NA', 'Unavailable'), ('Genome:MS', 'Review')])
def test_source_qc_empty_and_missing_are_distinct(raw, status):
    result = metrics.summarise_sample(sample(NGS_QC_Sum=raw))
    assert result['reported_qc_status'] == status
    assert result['reported_qc'] == raw


def test_indels_keep_coordinates_and_missing_is_not_no_events():
    result = metrics.summarise_sample(sample(S_aaDeletions='example-event;example-event',
                                             N_aaInsertions='example-insertion', NC_Genome_frameShifts='example-frame',
                                             M_aaDeletions='NA'))
    assert len(result['indels']) == 3
    assert {event['kind'] for event in result['indels']} == {'Deletion', 'Insertion', 'Frameshift'}
    assert result['indel_availability']['S:Deletion']
    assert not result['indel_availability']['M:Deletion']
    assert result['flags']['indels']


@pytest.mark.parametrize(('fields', 'status'), [
    ({'PCR_SC2_EXT_Res': '  P  VIST '}, 'Positive qPCR'),
    ({'PCR_SC2_TRI_Res': 'Påvist', 'PCR_SC2_EXT_Res': 'P vist'}, 'Positive qPCR'),
    ({'PCR_SC2_EXT_Res': 'Ikke påvist'}, 'Negative qPCR'),
    ({'PCR_SC2_EXT_Res': 'Påvist', 'PCR_SC2_TRI_Res': 'Ikke p vist'}, 'Conflicting qPCR results'),
    ({'PCR_triplex_SC2_CT': '23,16'}, 'Ct only'),
    ({'PCR_SC2_EXT_Res': 'Possible result'}, 'Unrecognised qPCR result'),
    ({}, 'qPCR unavailable'),
])
def test_qpcr_is_detection_evidence_not_lineage_concordance(fields, status):
    result = metrics.qpcr_evidence(fields)
    assert result['status'] == status
    if 'PCR_triplex_SC2_CT' in fields:
        assert result['ct']['PCR_triplex_SC2_CT'] == {'raw': '23,16', 'value': 23.16}


@pytest.mark.parametrize(('workflow', 'name'), [('fastq', '001'), ('fasta', '001'), ('fasta', 'P001'), ('fasta', 'legacy')])
def test_master_matching_and_no_stale_master_metrics(tmp_path, workflow, name):
    master = [{'Prove_LW_ID': 'P001', 'NGS_LW_ID': '001', 'Key': 'legacy', 'PCR_SC2_EXT_Res': 'Påvist',
               'NC_Coverage': '1', 'NC_Pangolin_Short': 'OLD', 'NC_Genome_QC': 'good', 'Pasient_No': 'SECRET'}]
    path = csv_file(tmp_path / 'run.csv', [sample(name, coverage='NA', Nextclade_pango='NA')])
    result = qc.build_report(path, master, workflow)['samples'][0]
    assert result['master_key'] == 'P001'
    assert result['qpcr']['status'] == 'Positive qPCR'
    assert result['coverage']['Genome'] is None and not result['lineage']
    assert 'SECRET' not in json.dumps(result)


def test_ambiguous_and_conflicting_identifiers_fail(tmp_path):
    path = csv_file(tmp_path / 'run.csv', [sample()])
    with pytest.raises(ValueError, match='multiple'):
        qc.build_report(path, [{'Prove_LW_ID': 'A', 'NGS_LW_ID': '001'}, {'Prove_LW_ID': 'B', 'NGS_LW_ID': '001'}])
    path = csv_file(path, [sample('legacy')])
    with pytest.raises(ValueError, match='ambiguous'):
        qc.build_report(path, [{'Prove_LW_ID': 'A', 'Key': 'legacy'}, {'Prove_LW_ID': 'B', 'Key': 'legacy'}], 'fasta')
    path = csv_file(path, [sample(Prove_LW_ID='wrong')])
    with pytest.raises(ValueError, match='disagree'):
        qc.build_report(path, [{'Prove_LW_ID': 'A', 'NGS_LW_ID': '001'}])


def test_all_rows_in_denominator_and_lineage_separate_from_qc(tmp_path):
    report = qc.build_report(csv_file(tmp_path / 'run.csv', [sample(), sample('002', coverage='0.1'),
                                                           sample('003', coverage='NA', Nextclade_pango='unassigned')]))
    assert report['counts']['samples'] == 3 and report['counts']['lineage_assigned'] == 2
    assert report['regions']['Genome']['passed'] == 1
    assert report['regions']['Genome']['low_coverage'] == 1
    assert report['regions']['Genome']['missing_or_invalid'] == 1
    assert report['regions']['Genome']['median_coverage'] == 52.5
    assert report['samples'][1]['qc_status'] == 'Review'


def test_empty_and_unavailable_reports(tmp_path):
    path = csv_file(tmp_path / 'empty.csv', [], ['Sample'])
    result = qc.write_report(path, tmp_path / 'empty.html')
    assert result['assessment'] == 'Not assessable'
    assert '0/0 (not assessable)' in (tmp_path / 'empty.html').read_text()
    path = csv_file(path, [{'Sample': '001'}])
    assert qc.build_report(path)['samples'][0]['qc_status'] == 'Unavailable'


@pytest.mark.parametrize('rows', [[sample(), sample()], [sample('NA')], [{'Unrelated': '001'}]])
def test_malformed_report_identifiers_fail(tmp_path, rows):
    with pytest.raises(ValueError):
        qc.build_report(csv_file(tmp_path / 'run.csv', rows))


def test_html_json_escape_and_omit_private_master_fields(tmp_path):
    attack = '</script><script>alert("x")</script>@@TOTAL@@'
    source = csv_file(tmp_path / 'run.csv', [sample(attack, N_aaDeletions=attack)])
    master = csv_file(tmp_path / 'master.csv', [{'Prove_LW_ID': 'A', 'NGS_LW_ID': attack, 'PCR_SC2_EXT_Res': 'Påvist',
                                               'Pasient_No': 'PRIVATE-PATIENT', 'Pasient_Kommentar': 'PRIVATE-COMMENT'},
                                              {'Prove_LW_ID': 'B', 'NGS_LW_ID': 'UNRELATED-RECORD'}])
    before = master.read_bytes(), source.read_bytes()
    output = tmp_path / 'qc.html'
    qc.write_report(source, output, master)
    text = output.read_text()
    summary = output.with_suffix('.json').read_text()
    assert attack not in text and qc.esc(attack) in text
    assert text.count('<script') == 2 and '<script src=' not in text
    for secret in ('PRIVATE-PATIENT', 'PRIVATE-COMMENT', 'UNRELATED-RECORD'):
        assert secret not in text + summary
    payload = re.search(r'<script id="report-data" type="application/json">(.*?)</script>', text, re.S)[1]
    assert json.loads(payload) == json.loads(summary)
    assert (master.read_bytes(), source.read_bytes()) == before
    if shutil.which('node'):
        script = re.search(r'<script>\n(.*?)</script>', text, re.S)[1]
        subprocess.run(['node', '--check'], input=script, text=True, capture_output=True, check=True)


@pytest.mark.parametrize('options', [{'coverage_threshold': 0}, {'coverage_threshold': 101},
                                     {'cds_threshold': float('nan')}, {'mixed_threshold': -1}, {'mixed_threshold': 1.5}])
def test_invalid_thresholds_fail(tmp_path, options):
    with pytest.raises(ValueError):
        qc.build_report(csv_file(tmp_path / 'run.csv', [sample()]), **options)


def test_output_collisions_rejected(tmp_path):
    source = csv_file(tmp_path / 'source.json', [sample()])
    before = source.read_bytes()
    with pytest.raises(ValueError, match='separate'):
        qc.write_report(source, tmp_path / 'source.html')
    assert source.read_bytes() == before
    with pytest.raises(ValueError, match='.html'):
        qc.write_report(source, tmp_path / 'out.csv')


def test_updater_uses_fresh_metadata_and_rebuilds_on_noop(tmp_path):
    master = csv_file(tmp_path / 'master.csv', [], ['Prove_LW_ID'])
    csv_file(tmp_path / 'NGS_PREP_SC2_report.csv', [{'Prove_LW_ID': 'P001', 'NGS_LW_ID': '001', 'PCR_triplex_SC2_CT': '23,16'}])
    source = csv_file(tmp_path / 'run.csv', [sample()])
    config, _ = updater.configuration({'SARSSEQ_MASTER_CSV': str(master)})
    output = tmp_path / 'run_qc.html'
    stats = updater.update(config, source, 'fastq', qc_output=output)
    assert stats['written']
    assert json.loads(output.with_suffix('.json').read_text())['samples'][0]['qpcr']['status'] == 'Ct only'
    output.unlink()
    assert not updater.update(config, source, 'fastq', qc_output=output)['written']
    assert output.is_file()


def test_smb_updater_generates_from_updated_master_with_sars_renderer(tmp_path):
    root = tmp_path / 'remote'
    root.mkdir()
    csv_file(root / 'master.csv', [], ['Prove_LW_ID'])
    metadata = csv_file(tmp_path / 'metadata.csv', [{'Prove_LW_ID': 'P001', 'NGS_LW_ID': '001', 'PCR_SC2_EXT_Res': 'Påvist'}])

    class Remote(updater.storage.SMB):
        def command(self, verb, *args):
            if verb == 'get':
                shutil.copyfile(root / args[0], args[1])
            elif verb == 'put':
                shutil.copyfile(args[0], root / args[1])
            elif verb == 'mkdir':
                (root / args[0]).mkdir()
            elif verb == 'rmdir':
                (root / args[0]).rmdir()
            elif verb == 'rename':
                (root / args[0]).replace(root / args[1])
            else:
                raise AssertionError(verb)

    config = {'master': None, 'metadata': str(metadata), 'master_name': 'master.csv', 'metadata_name': 'metadata.csv',
              'master_smb': Remote('//test/share', 'SC2', 'unused'), 'metadata_smb': None, 'nonempty_report': False}
    source = csv_file(tmp_path / 'run.csv', [sample()])
    output = tmp_path / 'qc.html'
    updater.update(config, source, 'fastq', qc_output=output)
    result = json.loads(output.with_suffix('.json').read_text())
    assert result['schema_version'] == 'sars-qc-1.0'
    assert result['master_source'] == 'master.csv'
    assert result['samples'][0]['qpcr']['status'] == 'Positive qPCR'
    assert not (root / 'master.csv.lock').exists()
    assert not list(root.glob('*.html')) and not list(root.glob('*.json'))


@pytest.mark.parametrize('failure', ['threshold', 'output-collision', 'render'])
def test_qc_failure_timing_and_retry(tmp_path, monkeypatch, failure):
    master = csv_file(tmp_path / 'master.json', [], ['Prove_LW_ID'])
    metadata = csv_file(tmp_path / 'metadata.csv', [{'Prove_LW_ID': 'P001', 'NGS_LW_ID': '001'}])
    config, _ = updater.configuration({'SARSSEQ_MASTER_CSV': str(master), 'SARSSEQ_METADATA_CSV': str(metadata)})
    source = csv_file(tmp_path / 'run.csv', [sample()])
    before = master.read_bytes()
    output = tmp_path / ('master.html' if failure == 'output-collision' else 'qc.html')
    options = {'coverage_threshold': -1} if failure == 'threshold' else {}
    if failure == 'render':
        original = qc.render
        def fail(report):
            raise OSError('simulated render failure')
        monkeypatch.setattr(qc, 'render', fail)
    with pytest.raises((ValueError, OSError)):
        updater.update(config, source, 'fastq', qc_output=output, qc_options=options)
    assert not Path(str(master) + '.lock').exists()
    if failure == 'render':
        assert master.read_bytes() != before  # Reporting cannot roll back a completed master update.
        monkeypatch.setattr(qc, 'render', original)
        assert not updater.update(config, source, 'fastq', qc_output=output)['written']
        assert output.exists()
    else:
        assert master.read_bytes() == before


@pytest.mark.parametrize('validation', ['', 'VER'])
def test_disabled_or_validation_cli_generates_without_master_access(tmp_path, validation):
    source = csv_file(tmp_path / 'run.csv', [sample()])
    output = tmp_path / 'qc.html'
    env = {key: value for key, value in os.environ.items() if not key.startswith('SARSSEQ_')}
    env.update(SARSSEQ_MASTER_UPDATE='true' if validation else 'false', SARSSEQ_MASTER_CSV='/missing/master.csv')
    result = subprocess.run([sys.executable, str(ROOT / 'update_master.py'), '--workflow', 'fastq', '--report', str(source),
                             '--qc-output', str(output), '--validation', validation], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads(output.with_suffix('.json').read_text())['master_source'] is None


def test_standalone_cli(tmp_path):
    source = csv_file(tmp_path / 'run.csv', [sample()])
    result = subprocess.run([sys.executable, str(ROOT / 'sars_qc_report.py'), str(source), '--outdir', str(tmp_path)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert (tmp_path / 'run_qc.html').is_file() and (tmp_path / 'run_qc.json').is_file()


def test_generated_javascript_filters_sorts_and_exports(tmp_path):
    if not shutil.which('node'):
        pytest.skip('Node is needed to exercise the generated JavaScript')
    source = csv_file(tmp_path / 'run.csv', [sample(), sample('002', NC_Genome_MixedSites='4', S_aaDeletions='example-event'),
                                           sample('=1+1', Nextclade_pango='NA', coverage='NA')])
    page = qc.render(qc.build_report(source))

    class PageParser(HTMLParser):
        def __init__(self):
            super().__init__()
            self.table = None
            self.current = None
            self.tables = {'samples': [], 'indels': []}
            self.ids = {}
            self.buttons = []

        def handle_starttag(self, tag, attrs):
            attrs = dict(attrs)
            if 'id' in attrs:
                self.ids[attrs['id']] = {'tagName': tag.upper()}
            if tag == 'table':
                self.table = attrs.get('id')
            if tag == 'tr' and self.table in self.tables and 'data-export' in attrs:
                self.current = {'dataset': {name[5:]: value for name, value in attrs.items() if name.startswith('data-')},
                                'textContent': ''}
                self.tables[self.table].append(self.current)
            if tag == 'button' and 'data-finding' in attrs:
                self.buttons.append({'dataset': {'finding': attrs['data-finding']}})

        def handle_data(self, data):
            if self.current is not None:
                self.current['textContent'] += data

        def handle_endtag(self, tag):
            if tag == 'tr':
                self.current = None
            if tag == 'table':
                self.table = None

    parser = PageParser()
    parser.feed(page)
    data = {'ids': parser.ids, 'tables': parser.tables, 'buttons': parser.buttons,
            'report': re.search(r'<script id="report-data" type="application/json">(.*?)</script>', page, re.S)[1]}
    script = re.search(r'<script>\n(.*?)</script>', page, re.S)[1]
    harness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const data = JSON.parse(process.env.QC_DOM);
function element(values={}) { return Object.assign({value:'', hidden:false, listeners:{}, textContent:'',
  addEventListener(type, fn) {this.listeners[type]=fn;}, scrollIntoView(){}, remove(){}, click(){}}, values); }
const ids = Object.fromEntries(Object.entries(data.ids).map(([id, value]) => [id, element(value)]));
ids.sort.value='priority'; ids['report-data'].textContent=data.report;
const tables = Object.fromEntries(Object.entries(data.tables).map(([id, rows]) => [id, rows.map(element)]));
const buttons = data.buttons.map(element);
let download=null, content=null;
const document = {
  getElementById(id) {assert.ok(ids[id], id); return ids[id];},
  querySelectorAll(selector) {
    if (selector==='[data-finding]') return buttons;
    const match=selector.match(/^#(samples|indels) tbody tr$/); assert.ok(match, selector); return tables[match[1]];
  },
  querySelector(selector) {assert.equal(selector,'#samples tbody'); return {append(...rows){tables.samples=rows;}};},
  createElement() {return element({click(){download=this.download;}});}, body:{append(){}}
};
const context={document, window:{print(){}}, setTimeout:fn=>fn(),
  Blob:class {constructor(parts){this.parts=parts;}}, URL:{createObjectURL(blob){content=blob.parts.join('');return 'blob:test';},revokeObjectURL(){}}};
vm.runInNewContext(process.env.QC_SCRIPT, context);
const change=(id,value,type='change')=>{ids[id].value=value;ids[id].listeners[type]();};
const click=id=>ids[id].listeners.click();
assert.equal(tables.samples.filter(row=>!row.hidden).length,3);
buttons.find(button=>button.dataset.finding==='mixed').listeners.click();
assert.equal(tables.samples.filter(row=>!row.hidden).length,1);
assert.equal(tables.samples.find(row=>!row.hidden).dataset.sample,'002');
change('region','S'); assert.equal(tables.samples.filter(row=>!row.hidden).length,0);
change('region','Genome'); assert.equal(tables.samples.filter(row=>!row.hidden).length,1);
click('export-samples'); assert.equal(download,'sars_qc_samples.csv');
assert.ok(content.includes('"002"')); assert.ok(!content.includes('"001"'));
click('reset'); change('search','=1+1','input'); click('export-samples');
assert.ok(content.includes('"\'=1+1"')); // Formula-safe CSV cells.
click('reset'); change('sort','sample');
assert.deepEqual(tables.samples.map(row=>row.dataset.sample),['=1+1','001','002']);
change('qc','No flags'); assert.equal(tables.samples.filter(row=>!row.hidden).length,1);
click('reset'); change('lineage','Unavailable'); assert.equal(tables.samples.filter(row=>!row.hidden).length,1);
click('reset'); change('qpcr','No master match'); assert.equal(tables.samples.filter(row=>!row.hidden).length,3);
change('indel-region','S'); change('indel-kind','Deletion'); click('export-indels');
assert.equal(download,'sars_qc_indels.csv'); assert.ok(content.includes('example-event'));
change('indel-kind','Frameshift'); assert.ok(ids['indel-empty'].hidden===false);
click('indel-reset'); assert.equal(tables.indels.filter(row=>!row.hidden).length,1);
click('export-json'); assert.equal(download,'sars_qc.json'); assert.equal(JSON.parse(content).counts.samples,3);
'''
    result = subprocess.run(['node', '-e', harness], env={**os.environ, 'QC_DOM': json.dumps(data), 'QC_SCRIPT': script},
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
