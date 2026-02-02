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

### Routine avian run

```bash
screen -S fluseq-INF077-human -d -m bash /home/ngs/ngs_scripts/fluseq/fluseq_fasta_wrapper.sh \
  -r INF077 \
  -a avian \
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
