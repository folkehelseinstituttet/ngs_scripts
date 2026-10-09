# fluseq: Quick Start Guide

---

## 1. Human influenza pipeline (FASTQ)

### Routine run

```bash
screen -S fluseq-RUN -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_wrapper.sh \
  -r INF075 \
  -a influensa \
  -s Ses2425 \
  -y 2025
```

Replace:
- `INF075` → your run name  
- `Ses2425` → season folder  
- `2025` → year folder  

---

### Validation run (VER)

```bash
screen -S fluseq-RUN-VER -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_wrapper.sh \
  -r INF075 \
  -a influensa \
  -s Ses2425 \
  -y 2025 \
  -v VER
```

---

## 2. Avian influenza pipeline (FASTQ)

Used for **avian influenza** runs (H5, H7, etc.).

### Routine avian run

```bash
screen -S fluseq-RUN-avian -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_avian_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025
```

Replace:
- `INF075` → your run name  
- `Ses2425` → season folder  
- `2025` → year folder  

---

## 3. Avian influenza pipeline (FASTA)

Used for **avian influenza** runs (H5, H7, etc.) with FASTA as input.
FASTA-seqeunces are retrived from N:\**\1-Rutine\2-Resultater\Influensa\12-Export, where -r references to the folder with FASTA-file. 

### Routine avian run

```bash
screen -S fluseq-INF077-avian -d -m bash /home/ngs/ngs_scripts/fluseq/avianseq_fasta_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025
```

---

## 4. Human influenza pipeline (FASTA)

Used for **human influenza** runs with FASTA as input.
FASTA-seqeunces are retrived from N:\**\1-Rutine\2-Resultater\Influensa\12-Export, where -r references to the folder with FASTA-file. 

### Routine avian run

```bash
screen -S fluseq-INF077-human -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_fasta_wrapper.sh \
  -r INF077 \
  -a influensa \
  -s Ses2425 \
  -y 2025
```

---

### Validation avian run

```bash
screen -S fluseq-RUN-avian-VER -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_avian_wrapper.sh \
  -r INF077 \
  -a avian \
  -s Ses2425 \
  -y 2025 \
  -v VER
```

---


## 3. Checking progress

List sessions:

```bash
screen -ls
```

Reconnect:

```bash
screen -r fluseq-INF075
```

Detach again with `Ctrl+A` then `D`.

## Primer checks

The routine wrapper enables primer-checker (PCR for influenza, PCR and NGS for
SARS/RSV). Use `-P` to override the PCR JSON file/directory and `-N` in SARS/RSV
to override the NGS primer-assets directory. The PCR defaults are defined near
the wrapper's argument parsing. `PRIMER_CHECK_ENABLED=false` disables the check.

CSV and HTML reports are written to `primer_check/`; `task_status.csv` identifies
any ignored failures. Online Docker tasks explicitly pull the latest published
CLI image. See the [deployment and input guide](https://github.com/RasmusKoRiis/primer-checker/blob/main/docs/PIPELINE_INTEGRATION.md)
before the first run.

## Run logs and cleanup

The routine wrapper writes `$HOME/fluseq_<RUN>_wrapper.log`,
`fluseq_<RUN>_wrapper_error.log`, `fluseq_<RUN>_status.txt`, and
`fluseq_<RUN>_nextflow.log`. Successful online runs archive verified logs to
`<RUN>/logs` on N: and clean this run's local inputs, work and staged routine
results. Failed runs retain their logs; validation keeps full local results.
See the [shared logging and cleanup policy](../resp-virus-toolkit/README.md#shared-wrapper-logging-and-cleanup)
for destinations, retries, failure handling and configuration.

Teams completion/failure notifications use `~/.teams_webhook_inf`. Add `-t` to
suppress notifications during testing; the pipeline, uploads and cleanup still
run. Validation (`-v VER`) sends notifications unless `-t` is also supplied.
See [Teams setup](../resp-virus-toolkit/README.md#teams-completion-and-failure-notifications).
