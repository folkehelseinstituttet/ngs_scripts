#!/usr/bin/env bash

# Send all stdout/stderr to the main wrapper log (and to the console when not detached)
exec > >(tee -a /home/ngs/mpx_wrapper.log) 2>&1

# Error/history log file
LOGFILE="/home/ngs/mpx_wrapper_error.log"

# Provide a conservative default STATUS_FILE early so very early failures still write somewhere.
# This will be overwritten with the run-specific file after argument parsing.
STATUS_FILE="$HOME/mpx_artic_unknown_status.txt"
printf '[%s] Initialized (unknown run)\n' "$(date +'%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"

# Small helper to write status; STATUS_FILE will be updated after args are parsed.
# Writes to LOGFILE (append), wrapper log (append) and updates STATUS_FILE atomically.
set_status() {
    msg="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    # history
    echo "$msg" >> "$LOGFILE"
    # also write to the main wrapper log for completeness
    echo "$msg" >> /home/ngs/mpx_artic_wrapper.log
    # atomic write of the single-line status file if it's defined
    if [ -n "${STATUS_FILE:-}" ]; then
        tmp="${STATUS_FILE}.tmp"
        if printf '%s\n' "$msg" > "$tmp"; then
            mv "$tmp" "$STATUS_FILE" || echo "[$(date)] Failed to mv $tmp to $STATUS_FILE" >> "$LOGFILE"
        else
            echo "[$(date)] Failed to write status to $tmp" >> "$LOGFILE"
        fi
    fi
}

# Trap for detailed error info: line number and command
trap 'set_status "Error at line $LINENO: \"$BASH_COMMAND\" exited with status $?"' ERR

# Trap for termination signals so we update the status file on graceful termination
trap 'set_status "Received SIGTERM - terminating"; exit 143' SIGTERM
trap 'set_status "Received SIGHUP - terminating"; exit 129' SIGHUP

# Trap for any script exits (success or failure)
trap 'ec=$?;
  if [ $ec -ne 0 ]; then
    set_status "Script exited with error code $ec"
    echo "Script exited with error code $ec" >&2
    echo "Did you remember to change \"RUN_NAME\"?" >&2
  else
    set_status "Script completed successfully."
    echo "Script completed successfully."
  fi' EXIT


# --- 1. INITIALIZATION & ARGUMENTS ---


SCRIPT_NAME=$(basename "$0")

usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo "Options:"
    echo "  -h, --help        Display this help message"
    echo "  -r, --run         Specify the run name (MPX012)"
    echo "  -a, --agens       Specify agens (MPX)"
    echo "  -y, --year        Specify the year directory of the fastq files on the N-drive"
    exit 1
}

# Initialize variables
RUN=""
AGENS=""
YEAR=""

while getopts "hr:a:y:" opt; do
    case "$opt" in
        h) usage ;;
        r) RUN="$OPTARG" ;;
        a) AGENS="$OPTARG" ;;
        y) YEAR="$OPTARG" ;;
        ?) usage ;;
    esac
done

if [[ -z "$RUN" || -z "$AGENS" || -z "$YEAR" ]]; then
    echo "Error: Missing required arguments."
    usage
fi

# Now that arguments are parsed, set a run-specific status file and initialize it.
if [ -n "${RUN:-}" ]; then
    STATUS_FILE="$HOME/mpx_${RUN}_status.txt"
else
    STATUS_FILE="$HOME/mpx_unknown_status.txt"
fi
printf '[%s] Initialized\n' "$(date +'%Y-%m-%d %H:%M:%S')" > "$STATUS_FILE"
set_status "Started wrapper. RUN=$RUN AGENS=$AGENS YEAR=$YEAR"

# Set working directory
cd $HOME

# --- 2. ENVIRONMENT CONFIGURATION ---

# Set up paths
BASE_DIR=/mnt/tempdata/
# TMP_DIR will hold the raw fastq files and results
TMP_DIR=/mnt/tempdata/fastq_mpx/raw/${RUN}
TMP_RES=/mnt/tempdata/fastq_mpx/analysis/${RUN}
#MAKE SURE CSV FILE PATH IS PARSED CORRECTLY
TMP_SAMPLESHEET_DIR=/mnt/tempdata/fastq_mpx/data/samplesheets/

# SMB Credentials and remote Paths
SMB_AUTH=/home/ngs/.smbcreds
SMB_HOST=//pos1-fhi-svm01.fhi.no/styrt
SMB_DIR=Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/${YEAR}
SMB_SAMPLESHEET_REMOTE=/Virologi/NGS/1-NGS-Analyser/1-Rutine/2-Resultater/${AGENS}/${YEAR}/Samplesheets

# Determine Input Directory based on Year/Test status
if [ "$RUN" = "TEST" ] || [ "$RUN" = "FULL_TEST" ]; then
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/TEST/MPX/$RUN/$RUN/"
elif [ "$YEAR" -ge 2026 ]; then
    # -----------------------------------------------------------------------
    # PATH FOR 2026 AND NEWER
    # -----------------------------------------------------------------------
    SMB_INPUT="/Virologi/NGS/0-Sekvenseringsbiblioteker/Nanopore_Grid_Run/$RUN/$RUN"
else 
    # -----------------------------------------------------------------------
    # LEGACY PATH FOR 2025 AND OLDER
    # -----------------------------------------------------------------------
    SMB_INPUT="NGS/3-Sekvenseringsbiblioteker/${YEAR}/Nanopore_Grid_Run/$RUN/$RUN"
fi

# Create directories
mkdir -p "$TMP_RES"
mkdir -p "$TMP_DIR"
mkdir -p "$TMP_SAMPLESHEET_DIR"

# --- 3. VERIFY REMOTE PATH & DOWNLOAD DATA ---

echo "Verifying that remote path exists: $SMB_INPUT"

# Check if the path exists by trying to list it (-c "ls"). 
# If smbclient returns a non-zero exit code, the path is likely invalid.
if ! smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" -c "ls" >/dev/null 2>&1; then
    set_status "Error: Remote path not found on N-drive: $SMB_INPUT"
    echo "Error: The constructed path does not exist on the server."
    echo "Path attempted: $SMB_INPUT"
    exit 1
fi

# Debug: show the SMB_INPUT
echo "Listing directories in: $SMB_INPUT"
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" -c "ls"

# Get the unknown subfolder name
SUBFOLDER=$(smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_INPUT" -c "ls" \
    | grep " D " \
    | awk '{print $1}' \
    | grep -vE '^\.$|^\.\.$' \
    | head -n1)

if [ -z "$SUBFOLDER" ]; then
    echo "No subfolder found in $SMB_INPUT"
    exit 1
fi

REMOTE_FASTQ="$SMB_INPUT/$SUBFOLDER/fastq_pass"

echo "Copying fastq files from the N drive..."
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$REMOTE_FASTQ" <<EOF
prompt OFF
recurse ON
lcd $TMP_DIR
mget *
EOF

echo "Copying samplesheet from the N drive..."
smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_SAMPLESHEET_REMOTE" <<EOF
prompt OFF
recurse ON
lcd $TMP_SAMPLESHEET_DIR
get ${RUN}_samplesheet.csv
EOF

# --- 4. POPULATE SAMPLESHEET  ---

RAW_SAMPLESHEET="${TMP_SAMPLESHEET_DIR}/${RUN}_samplesheet.csv"
FINAL_SAMPLESHEET="${TMP_SAMPLESHEET_DIR}/${RUN}_samplesheet_filled.csv"

echo "Processing samplesheet..."
echo "Input: $RAW_SAMPLESHEET"
echo "Base Path for FastQ: $TMP_DIR"

if [ ! -f "$RAW_SAMPLESHEET" ]; then
    echo "Error: Downloaded samplesheet not found at $RAW_SAMPLESHEET"
    exit 1
fi

# Remove BOM (Byte Order Mark) if present
sed -i '1s/^\xEF\xBB\xBF//' "$RAW_SAMPLESHEET"


awk -F';' -v OFS=';' -v base="$TMP_DIR" '
# Helper function to remove spaces AND Windows carriage returns (\r)
function trim(s) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    return s
}
#Header processing
NR == 1 {
    #Save number of columns in header
    expected_NF = NF

    # Detect original positions of columns and store column index for relevant columns
    for (i = 1; i <= NF; i++) {
        name = trim($i)
        if (name == "PrøveID")  prove_col   = i
        if (name == "RunName")  runname_col = i
        if (name ~ /^[Bb]arcode$/) barcode_col = i
    }
    #Stop script if columns are not present
    if (!prove_col || !runname_col || !barcode_col) {
        print "ERROR: header must contain PrøveID, RunName, and Barcode/barcode" > "/dev/stderr"
        print "DEBUG: Headers found: " > "/dev/stderr"
        for (i = 1; i <= NF; i++) printf "[%s] ", trim($i) > "/dev/stderr"
        print "" > "/dev/stderr"
        exit 1
    }

    # Construct new header names and inject new column
    out_idx = 0
    for (i = 1; i <= NF; i++) {
        if (i == prove_col) {
            out[++out_idx] = "sample_id"
            out[++out_idx] = "fastq"
        } else if (i == barcode_col) {
            out[++out_idx] = "barcode"
        } else {
            out[++out_idx] = trim($i)
        }
    }
    #Save new number of fields 
    out_NF = out_idx

    for (i = 1; i <= out_NF; i++) {
        if (i > 1) printf OFS
        printf "%s", out[i]
    }
    printf "\n"

    next
}
#Skip empty lines 
$0 ~ /^[[:space:]]*$/ { next }

{
    #Check if row has same number of columns as header
    if (NF != expected_NF) {
        print "ERROR: line " NR " has wrong number of fields" > "/dev/stderr"
        exit 1
    }
    #Store values using column indices
    sid = trim($prove_col)
    rn  = trim($runname_col)
    
    # 1. Get the barcode from the CSV
    raw_bc = trim($barcode_col)
    
    # 2. Force it to lowercase (Barcode01 -> barcode01)
    bc = tolower(raw_bc)
    #See if important data is missing
    if (sid == "" || rn == "" || bc == "") {
        print "ERROR: required field empty at line " NR > "/dev/stderr"
        exit 1
    }

    # 3. Use the lowercase barcode for the path
    fq = base "/" bc

    #Build new row in same order as header
    out_idx = 0
    for (i = 1; i <= NF; i++) {
        if (i == prove_col) {
            out[++out_idx] = sid
            out[++out_idx] = fq
        } else if (i == barcode_col) {
            # 4. Use the lowercase barcode for the column value too
            out[++out_idx] = bc
        } else {
            out[++out_idx] = trim($i)
        }
    }

    for (i = 1; i <= out_idx; i++) {
        if (i > 1) printf OFS
        printf "%s", out[i]
    }
    printf "\n"
}
' "$RAW_SAMPLESHEET" > "$FINAL_SAMPLESHEET"

# Check if AWK succeeded
if [ $? -ne 0 ]; then
    echo "Error processing samplesheet."
    exit 1
fi

echo "Samplesheet created: $FINAL_SAMPLESHEET"


# --- 5. RUN PIPELINE ---

# Activate the conda environment that holds Nextflow
# Temporarily disable set -u because the JAVA_HOME variable is unset
set +u
source ~/miniconda3/etc/profile.d/conda.sh
conda activate NEXTFLOW
set -u

set_status "Activated NEXTFLOW conda environment"

# 1. Set the version (switch back to 'main' once development is complete and merged)
VERSION="main"

# 2. Tell Nextflow to refresh the code from GitHub
nextflow pull alexanderhes/Mpx_artic -r $VERSION || {
    set_status "Error: Nextflow pull failed"
    exit 1
}

# 3. Run it directly from the GitHub handle
nextflow run alexanderhes/Mpx_artic -r $VERSION \
    --input_dir "$FINAL_SAMPLESHEET" || {
    set_status "Error: Nextflow pipeline execution failed"
    exit 1
}


# --- 6. UPLOAD RESULTS AND CLEAN UP ---

echo "Moving results to the N: drive"
mkdir -p "$BASE_DIR/move_MPX"

# Move content to staging folder
mv "$TMP_RES/" "$BASE_DIR/move_MPX"

smbclient "$SMB_HOST" -A "$SMB_AUTH" -D "$SMB_DIR" <<EOF
prompt OFF
recurse ON
lcd $BASE_DIR/move_MPX
mput *
EOF

echo "Cleaning up local files..."
rm -rf "$TMP_DIR" "$TMP_RES" "$BASE_DIR/move_MPX"

nextflow clean -f

echo "Done."
