#!/bin/bash
# Purpose: Continuously poll an S3 bucket for updates to a JAR file.
# If a new version is detected (based on ETag), download it and restart the app.
# Usage: ./poll_s3.sh <bucket> <key> <target> <logfile>

set -euo pipefail

BUCKET="$1"
KEY="$2"
TARGET="$3"
LOG="$4"
LAST_ETAG_FILE="/var/tmp/jar-etag"

log() {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - $1" | tee -a "$LOG"
}

while true; do
  # Fetch current ETag of the object in S3
  etag=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query ETag --output text 2>/dev/null || echo "")

  if [ -z "$etag" ]; then
    log "No JAR present yet at s3://$BUCKET/$KEY"
    sleep 30
    continue
  fi

  # Check if ETag changed or file not yet downloaded
  if [ ! -f "$LAST_ETAG_FILE" ] || [ "$(cat "$LAST_ETAG_FILE")" != "$etag" ]; then
    log "New JAR detected: $etag — Downloading..."
    aws s3 cp "s3://$BUCKET/$KEY" "$TARGET" --quiet
    chmod 644 "$TARGET"
    echo "$etag" > "$LAST_ETAG_FILE"

    # Stop any existing Java process for the same JAR
        pids=$(pgrep -f "$TARGET" || true)
         if [ -n "$pids" ]; then
                echo "$(date -u) - stopping old Java processes: $pids" >> "$LOG"
                for pid in $pids; do
                 kill "$pid" || true
                done
                sleep 2
        fi

    # Restart application
    log "Starting updated app..."
    nohup java -jar "$TARGET" --server.port=8080 >> "$LOG" 2>&1 &
    log "App restarted successfully with new JAR version."
  fi

  sleep 15
done
