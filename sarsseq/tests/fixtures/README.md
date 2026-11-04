# Synthetic SC2 validation fixtures

These small files contain invented identifiers, metadata and placeholder FASTA
text. They are not patient reports or biological consensus sequences.

FASTQ/FASTA field spellings and fraction/percent units follow the local
`nf-core-sars` report schema inspected for this integration (`bin/report.py`,
`bin/report-fasta.py`, `bin/csv_conversion_nextclade.py` and
`docs/report-data-dictionary.md`). Only the report/table boundary is exercised;
no sequencing or mutation analysis is run by these fixtures.

FASTA omits FASTQ-only evidence. The partial CDS list intentionally checks that
unavailable metrics remain unavailable rather than being treated as passes.
The metadata exercises the common INF/SC2 column mapping, leading zeroes, Unicode
repair, qPCR context and exact identifiers. Production format/access validation
still requires the user's representative reports and deployed shared folders.
