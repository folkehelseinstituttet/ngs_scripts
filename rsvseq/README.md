Run the wrapper with: screen -S rsvseq -d -m bash /home/ngs/ngs_scripts/rsvseq/rsvseq_wrapper.sh -r TEST_RSV -a rsv -s Ses2425 -y 2025
Replace TEST with a run name (e.g. RSV002)
If running a verification of script add -v VER flag

## Run logs and cleanup

The routine wrapper writes `$HOME/rsvseq_<RUN>_wrapper.log`,
`rsvseq_<RUN>_wrapper_error.log`, `rsvseq_<RUN>_status.txt`, and
`rsvseq_<RUN>_nextflow.log`. Successful online runs archive verified logs to
`<RUN>/logs` on N: and clean this run's local inputs, work and staged routine
results. Failed runs retain their logs; validation keeps full local results.
See the [shared logging and cleanup policy](../resp-virus-toolkit/README.md#shared-wrapper-logging-and-cleanup)
for destinations, retries, failure handling and configuration.

## Primer checks

The routine wrapper enables primer-checker (PCR for influenza, PCR and NGS for
SARS/RSV). Use `-P` to override the PCR JSON file/directory and `-N` in SARS/RSV
to override the NGS primer-assets directory. The PCR defaults are defined near
the wrapper's argument parsing. `PRIMER_CHECK_ENABLED=false` disables the check.

CSV and HTML reports are written to `primer_check/`; `task_status.csv` identifies
any ignored failures. Online Docker tasks explicitly pull the latest published
CLI image. See the [deployment and input guide](https://github.com/RasmusKoRiis/primer-checker/blob/main/docs/PIPELINE_INTEGRATION.md)
before the first run.
