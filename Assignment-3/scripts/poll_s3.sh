#!/bin/bash
# usage: ./poll_s3.sh <bucket> <key> <target> <logfile>
set -euo pipefail
BUCKET="$1"
KEY="$2"
TARGET="$3"
LOG="$4"
LAST_ETAG_FILE="/var/tmp/jar-etag"

while true; do
  etag=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query ETag --output text 2>/dev/null || echo "")
  if [ -z "$etag" ]; then
    echo "$(date -u) - no jar present yet" >> "$LOG"
    sleep 30
    continue
  fi

  if [ ! -f "$LAST_ETAG_FILE" ] || [ "$(cat $LAST_ETAG_FILE)" != "$etag" ]; then
    echo "$(date -u) - new jar detected: $etag" >> "$LOG"
    aws s3 cp "s3://$BUCKET/$KEY" "$TARGET"
    chmod 644 "$TARGET"
    echo "$etag" > "$LAST_ETAG_FILE"

    pid=$(pgrep -f "$TARGET" || true)
    if [ -n "$pid" ]; then
      echo "$(date -u) - killing pid $pid" >> "$LOG"
      kill $pid || true
      sleep 2
    fi

    nohup java -jar "$TARGET" --server.port=80 >> "$LOG" 2>&1 &
    echo "$(date -u) - restarted app" >> "$LOG"
  fi
  sleep 15
done

