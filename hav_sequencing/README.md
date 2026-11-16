Wrapper for sequence analysis of Hepatitis A sequence data

[wrapper.sh](wrapper.sh) prepares the input data, runs the analysis from the
[hav_seq](https://github.com/folkehelseinstituttet/hav_seq) repository, and
uploads the results. See the `hav_seq` README.md for details about the analysis itself.

## Usage

```bash
./wrapper.sh [--local] [--test] [-v|--version <tag|branch>] --mode <sanger|wgs> <batch_name> <year>
```

| Option | Description |
|---|---|
| `--mode` | `sanger` or `wgs` (required) |
| `<batch_name>`, `<year>` | Batch name and year; determine the folder on the N: drive (required) |
| `-v`, `--version` | Tag or branch of `hav_seq` to run. Default: latest commit on the default branch |
| `--test` | Do not modify the database `2PA.fa` on the N: drive; write `2PA_test_<date_time>.fa` instead |
| `--local` | Run locally (`~/ngs_local`) instead of on the server. Skips pull/clone and ignores `--version` |

## What wrapper.sh does

1. Selects environment (server by default: input in `/mnt/tempdata`, repos/logs/results in `/home/ngs`) and starts run-specific log files.
2. Creates clean working directories for input, database and results.
3. Updates local copies of `ngs_scripts` and `hav_seq` (clone or pull), and checks out the requested `hav_seq` version (default: latest).
4. Copies from the N: drive (`Virologi/Hepatitt/Hepatitt A/HAV genteknologi/`, via `smbclient`):
   - fasta files from `<year>/<batch_name>/Fasta`
   - `HAV_lw_uttrekk.tsv` (LabWare extract). The script stops if the file is not dated today.
   - `Requests.xlsx`
   - the database `2PA.fa`
5. Runs `hav_seq/scripts/hav_wrapper.sh` with the chosen mode, `--test` flag, batch name and year.
6. Uploads the results, including the log files, to `<year>/<batch_name>` on the N: drive.
7. Uploads the updated database to `Databaser/` on the N: drive.
8. Cleans up temporary files. The log files are deleted from the server only if the run succeeded; otherwise they are kept for debugging.
