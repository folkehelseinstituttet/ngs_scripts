#!/usr/bin/env bash
# Source from a SARS wrapper after SCRIPT_DIR has been resolved.

MASTER_CSV_TOOLS="${SARSSEQ_MASTER_TOOLS:-$SCRIPT_DIR/master_csv}"

sars_master_preflight() {
    local workflow="$1" validation="$2" offline="${3:-false}"
    if [[ "$offline" == true ]]; then
        echo "Offline mode enabled: skipping SC2 master CSV/FASTA configuration/access."
        return 0
    fi
    python3 "$MASTER_CSV_TOOLS/update_master.py" \
        --workflow "$workflow" --validation "$validation" --check-config
}

sars_master_update() {
    local workflow="$1" validation="$2" run_out="$3" run="$4" offline="${5:-false}"
    local qc_remote_dir="${6:-}"
    # Select exactly this run's report, retaining software provenance when present.
    # Never glob reports or combine the duplicate with/without-version exports.
    local report="$run_out/report/${run}_with_software_versions.csv"
    if [[ ! -f "$report" ]]; then
        report="$run_out/report/${run}.csv"
    fi
    local args=(--workflow "$workflow" --validation "$validation" --report "$report"
        --qc-output "$run_out/report/${run}_qc.html"
        --qc-coverage-threshold "${SARSSEQ_QC_COVERAGE_THRESHOLD:-80}"
        --qc-cds-threshold "${SARSSEQ_QC_CDS_THRESHOLD:-80}"
        --qc-mixed-threshold "${SARSSEQ_QC_MIXED_THRESHOLD:-3}")
    if [[ "$offline" == true ]]; then
        echo "Offline mode enabled: generating local QC without master access or publishing."
        SARSSEQ_MASTER_UPDATE=false python3 "$MASTER_CSV_TOOLS/update_master.py" "${args[@]}"
    else
        if [[ -n "$qc_remote_dir" ]]; then
            args+=(--qc-smb-share "$SMB_HOST" --qc-smb-dir "$qc_remote_dir" --qc-smb-auth "$SMB_AUTH")
        fi
        python3 "$MASTER_CSV_TOOLS/update_master.py" "${args[@]}" --fasta "$run_out/report/${run}.fasta"
    fi
}
