#!/bin/bash
# Use SHOW_OUTPUT=true to proceed stdout with exit 0

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
    local extra_info_file=$3
    local log_entry=$(jq -n \
        --arg timestamp "$(date --iso-8601=seconds)" \
        --arg unique_id "$UNIQUE_ID" \
        --arg status "$status" \
        --arg message "$message" \
        --rawfile extra_info "$extra_info_file" \
        '{timestamp: $timestamp, unique_id: $unique_id, status: $status, message: $message, extra_info: $extra_info}')
    # Use flock to ensure exclusive access to the log file
    {
        flock -x 200
        echo "$log_entry" >> "$AWS_S3_SYNC_LOG_FILE"
    } 200>"$AWS_S3_SYNC_LOCK_FILE"
}

# Check if at least 2 arguments are provided
if [ "$#" -lt 2 ]; then
    log_message "error" "Usage: $0 <source> <destination> [additional aws s3 sync options]. Make sure AWS_S3_SYNC_LOG_FILE exists and is writable." "/dev/null"
    exit 1
fi

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Extract source and destination from the arguments
SOURCE=$1
DESTINATION=$2

# Shift arguments to pass any additional options to aws s3 sync
shift 2

# Create a temporary file for capturing the output
TMP_FILE=$(mktemp)
EXTRA_INFO_FILE=$(mktemp)

# Run the aws s3 sync command with provided arguments and capture the output
aws s3 sync "$SOURCE" "$DESTINATION" "$@" > "$TMP_FILE" 2>&1
RETURN_CODE=$?

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_TS=$(date -d "$START_TIME" +%s)
END_TS=$(date -d "$END_TIME" +%s)
DURATION=$((END_TS - START_TS))

# Construct extra information for the log
jq -n \
    --arg source "$SOURCE" \
    --arg destination "$DESTINATION" \
    --arg options "$*" \
    --rawfile sync_output "$TMP_FILE" \
    --arg start_time "$START_TIME" \
    --arg end_time "$END_TIME" \
    --arg duration "$(date -u -d @$DURATION +"%H:%M:%S")" \
    '{source: $source, destination: $destination, options: $options, sync_output: $sync_output, start_time: $start_time, end_time: $end_time, duration: $duration}' > "$EXTRA_INFO_FILE"

# Handle different return codes
if [ $RETURN_CODE -eq 0 ]; then
    log_message "info" "Sync successful." "$EXTRA_INFO_FILE"
    if [ "$SHOW_OUTPUT" == "true" ]; then
        cat "$TMP_FILE"
    fi
elif [ $RETURN_CODE -eq 1 ]; then
    log_message "error" "Sync failed due to a general error, exit code 1" "$EXTRA_INFO_FILE"
    echo -e "Error.\nExit code 1: $(cat "$TMP_FILE")\nUNIQUE_ID ${UNIQUE_ID}" >&2
elif [ $RETURN_CODE -eq 2 ]; then
    log_message "error" "Sync failed due to a permission error, exit code 2" "$EXTRA_INFO_FILE"
    echo -e "Error.\nExit code 2: $(cat "$TMP_FILE")\nUNIQUE_ID ${UNIQUE_ID}" >&2 
else
    log_message "error" "Sync failed with exit code $RETURN_CODE." "$EXTRA_INFO_FILE"
    echo -e "Error.\nExit code ${RETURN_CODE}: $(cat "$TMP_FILE")\nUNIQUE_ID ${UNIQUE_ID}" >&2
fi

# Cleanup temporary files
rm "$TMP_FILE"
rm "$EXTRA_INFO_FILE"

# Exit the script with the same return code
exit $RETURN_CODE
