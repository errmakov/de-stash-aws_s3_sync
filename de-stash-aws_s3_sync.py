#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import tempfile
import time
from datetime import datetime
import fcntl  # Add this import

# Function to log messages
def log_message(log_file, unique_id, status, message, extra_info):
    log_entry = {
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "unique_id": unique_id,
        "status": status,
        "message": message,
        "extra_info": extra_info
    }
    with open(log_file, "a") as f:
        f.write(json.dumps(log_entry) + "\n")

def main():
    parser = argparse.ArgumentParser(description='AWS S3 Sync Script')
    parser.add_argument('source', help='Source directory')
    parser.add_argument('destination', help='Destination S3 bucket')
    parser.add_argument('sync_options', nargs=argparse.REMAINDER, help='Additional aws s3 sync options')
    parser.add_argument('--o', action='store_true', help='Show output details on successful sync')
    parser.add_argument('--lock', default='/var/lock/aws_s3_sync.lock', help='File for lock')
    parser.add_argument('--log', default='/var/log/aws_s3_sync.log', help='Log file path')
    
    args = parser.parse_args()
    
    unique_id = f"{int(time.time()*1e6)}-{os.getpid()}"
    
    start_time = datetime.now()
    
    # Acquire the lock
    try:
        lock_file = open(args.lock, 'w')
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except IOError:
        print("Error: Could not acquire lock")
        return
    
    # Run the aws s3 sync command
    cmd = ["aws", "s3", "sync", args.source, args.destination] + args.sync_options
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        sync_output = result.stdout
        return_code = 0
    except subprocess.CalledProcessError as e:
        sync_output = e.stdout + "\n" + e.stderr
        return_code = e.returncode

    end_time = datetime.now()
    duration = end_time - start_time

    extra_info = {
        "source": args.source,
        "destination": args.destination,
        "options": " ".join(args.sync_options),
        "sync_output": sync_output,
        "start_time": start_time.strftime("%Y-%m-%d %H:%M:%S"),
        "end_time": end_time.strftime("%Y-%m-%d %H:%M:%S"),
        "duration": str(duration)
    }

    if return_code == 0:
        log_message(args.log, unique_id, "info", "Sync successful.", extra_info)
        if args.o:
            print(f"Well done. Source directory: {args.source}. Details: {args.log}")
    else:
        status = "error"
        if return_code == 1:
            message = "Sync failed due to a general error, exit code 1"
        elif return_code == 2:
            message = "Sync failed due to a permission error, exit code 2"
        else:
            message = f"Sync failed with exit code {return_code}"
        
        log_message(args.log, unique_id, status, message, extra_info)
        print(f"Error.\nExit code {return_code}: {sync_output}\nUNIQUE_ID {unique_id}", file=sys.stderr)

if __name__ == "__main__":
    main()
