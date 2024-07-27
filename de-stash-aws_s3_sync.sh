#!/bin/bash
# Use --o to proceed stdout with exit 0

# Function to display usage information
usage() {
    echo "Usage: $0 [options] <source> <destination> [additional aws s3 sync options]"
    echo ""
    echo "Options:"
    echo "  --o                 Show output details on successful sync"
    echo "  --lock <dir>        Directory for lock file (default: /var/lock/aws_s3_sync.lock)"
    echo "  --log <file>        Log file path (default: /log/aws_s3_sync.log)"
    echo "  --help, -h, -?      Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /local/dir s3://bucket/path"
    echo "  $0 --o /local/dir s3://bucket/path --delete"
    echo "  $0 --lock /tmp/lock --log /tmp/log/aws_s3_sync.log /local/dir s3://bucket/path"
    exit 0
}

# Default values for lock directory and log file
LOCK_DIR="/var/lock/aws_s3_sync.lock"
LOG_FILE="/var/log/aws_s3_sync.log"

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$0")

# Load environment variables from .env.aws_s3_sync file located in the same directory as the script
if [ -f "$SCRIPT_DIR/.env.aws_s3_sync" ]; then
    set -a
    source "$SCRIPT_DIR/.env.aws_s3_sync"
    set +a
else
    echo ".env.aws_s3_sync file not found in $SCRIPT_DIR."
    exit 1
fi

# Generate a unique ID for this script call
UNIQUE_ID=$(date +%s%N)-$$-$(od -vAn -N4 -tu4 < /dev/urandom | tr -d ' ')

log_message() {
    local status=$1
    local message=$2
    local extra_info=$3
    local log_entry=$(jq -n \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg unique_id "$UNIQUE_ID" \
        --arg status "$status" \
        --arg message "$message" \
        --argjson extra_info "$extra_info" \
        '{timestamp: $timestamp, unique_id: $unique_id, status: $status, message: $message, extra_info: $extra_info}')
    
    # Use mkdir to ensure exclusive access to the log file
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        sleep 0.1
    done
    trap 'rmdir "$LOCK_DIR"' EXIT
    echo "$log_entry" >> "$LOG_FILE"
}

# Check if at least 2 arguments are provided
if [ "$#" -lt 2 ]; then
    usage
fi

# Handle options
SHOW_OUTPUT=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --o)
            SHOW_OUTPUT=true
            shift
            ;;
        --lock)
            LOCK_DIR="$2"
            shift 2
            ;;
        --log)
            LOG_FILE="$2"
            shift 2
            ;;
        --help|-h|-\?)
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Check if source and destination are provided
if [ "$#" -lt 2 ]; then
    usage
fi

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Extract source and destination from the arguments
SOURCE=$1
DESTINATION=$2

# Shift arguments to pass any additional options to aws s3 sync
shift 2

# Ensure the log file directory exists
LOG_FILE_DIR=$(dirname "$LOG_FILE")
mkdir -p "$LOG_FILE_DIR"

# Run the aws s3 sync command with provided arguments
SYNC_OUTPUT=$(aws s3 sync "$SOURCE" "$DESTINATION" "$@" 2>&1)
RETURN_CODE=$?

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Convert date to timestamp on macOS and Ubuntu
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TS=$(date -jf "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s)
    END_TS=$(date -jf "%Y-%m-%d %H:%M:%S" "$END_TIME" +%s)
else
    START_TS=$(date -d "$START_TIME" +%s)
    END_TS=$(date -d "$END_TIME" +%s)
fi
DURATION=$((END_TS - START_TS))

# Construct extra information for the log
extra_info=$(jq -n \
    --arg source "$SOURCE" \
    --arg destination "$DESTINATION" \
    --arg options "$*" \
    --arg sync_output "$SYNC_OUTPUT" \
    --arg start_time "$START_TIME" \
    --arg end_time "$END_TIME" \
    --arg duration "$(date -u -d @$DURATION +"%H:%M:%S")" \
    '{source: $source, destination: $destination, options: $options, sync_output: $sync_output, start_time: $start_time, end_time: $end_time, duration: $duration}')

# Handle different return codes
if [ $RETURN_CODE -eq 0 ]; then
    log_message "info" "Sync successful." "$extra_info"
    if [ "$SHOW_OUTPUT" == "true" ]; then
        echo "Well done. Details: ${LOG_FILE}"
    fi
elif [ $RETURN_CODE -eq 1 ]; then
    log_message "error" "Sync failed due to a general error, exit code 1" "$extra_info"
    echo -e "Error.\nExit code 1: ${SYNC_OUTPUT}\nUNIQUE_ID ${UNIQUE_ID}" >&2
elif [ $RETURN_CODE -eq 2 ]; then
    log_message "error" "Sync failed due to a permission error, exit code 2" "$extra_info"
    echo -e "Error.\nExit code 2: ${SYNC_OUTPUT}\nUNIQUE_ID ${UNIQUE_ID}" >&2
else
    log_message "error" "Sync failed with exit code $RETURN_CODE." "$extra_info"
    echo -e "Error.\nExit code ${RETURN_CODE}: ${SYNC_OUTPUT}\nUNIQUE_ID ${UNIQUE_ID}" >&2
fi

# Exit the script with the same return code
exit $RETURN_CODE
