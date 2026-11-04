"""SARS column names; LabWare mappings are shared with Influenza.

Mappings rename text fields only. They do not calculate or interpret results.
"""
from pathlib import Path
import sys

SHARED = Path(__file__).resolve().parents[2] / 'fluseq' / 'master_csv' / 'bin'
sys.path.insert(0, str(SHARED))
from merge_master_csv import ASSETS, read_mapping, schema as shared_schema

ASSET_DIR = Path(__file__).resolve().parent / 'assets'


def schema():
    columns, canonical = shared_schema(ASSET_DIR)
    # Canonicalize shared metadata names even when absent from the old SC2 export.
    _, metadata_canonical = shared_schema()
    metadata_map = read_mapping(ASSETS / 'LABWAREDIRECT.xml', metadata_canonical)
    metadata_map['Key'] = 'Metadata_Key'
    for name in metadata_map.values():
        canonical.setdefault(name.casefold(), name)
    canonical['ngs_sekvens_id'] = 'NGS_LW_ID'
    return columns, canonical, metadata_map


def report_mapping(workflow):
    if workflow not in {'fastq', 'fasta'}:
        raise ValueError('workflow must be fastq or fasta')
    mapping = {
        'Sample': 'NGS_LW_ID' if workflow == 'fastq' else 'SampleID',
        'RunID': 'NGS_Run_ID',
        'Date': 'NGS_Script_dato',
        'Instrument ID': 'NGS_Instrument ID',
        'Primer': 'NGS_Primer_vers',
        'clade': 'NC_Clade',
        'Nextclade_pango': 'NC_Pangolin_Short',
        'partiallyAliased': 'NC_Pangolin_Long',
        'coverage': 'NC_Coverage',
        'NC_Genome_MixedSites': 'NC_MixedSItes',
        'NC_Genome_QC': 'NC_Genome_Quality',
        'NC_Genome_frameShifts': 'NC_Genome_Frameshift',
        'Spike_mAbs_inhibitors': 'DR_Spike_mAbs',
        'Spike_Fold': 'DR_Spike_mAbs_fold',
        '3CLpro_inhibitors': 'DR_3CLpro_Mut',
        '3CLpro_Fold': 'DR_3CLpro_fold',
        'RdRp_inhibitors': 'DR_RdRP_Mut',
        'RdRp_Fold': 'DR_RdRp_Fold',
        'GISAID_Comment': 'GISAID_Kommentar',
    }
    for gene in ('E', 'M', 'N', 'ORF1a', 'ORF1b', 'ORF3a', 'ORF6',
                 'ORF7a', 'ORF7b', 'ORF8', 'ORF9b', 'S'):
        mapping[f'{gene}_aaSubstitutions'] = f'Mut_{gene}'
        mapping[f'{gene}_aaDeletions'] = f'NC_{gene}_Deletions'
        mapping[f'{gene}_aaInsertions'] = f'NC_{gene}_Insertions'
    for gene in ('S', 'ORF1a'):
        for number in range(1, 5):
            mapping[f'{gene}_aaSubstitutions_{number}'] = f'Mut_{gene}_{number}'
    return mapping
