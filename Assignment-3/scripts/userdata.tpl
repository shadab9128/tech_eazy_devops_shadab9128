  

```bash
#!/bin/bash
set -euo pipefail

# Variables injected by Terraform
GITHUB_REPO="${github_repo}"
BUCKET="${existing_bucket_name}"  # Standardized
APP_DIR="/home/ubuntu/app"
JAR_KEY="app/hellomvc-0.0.1-SNAPSHOT.jar"
LOCAL_JAR="$APP_DIR/hellomvc-0.0.1-SNAPSHOT.jar"
LOG_FILE="$APP_DIR/techeazy.log"
LAST_ETAG_FILE="/var/tmp/jar-etag"

apt-get update -y
apt-get install -y openjdk-21-jdk awscli jq

mkdir -p $APP_DIR
chown ubuntu:ubuntu $APP_DIR
touch $LOG_FILE
chown ubuntu:ubuntu $LOG_FILE

# Poll and restart logic
while true; do
  etag=$(aws s3api head-object --bucket "$BUCKET" --key "$JAR_KEY" --query ETag --output text 2>/dev/null || echo "")
  if [ -z "$etag" ]; then
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - No JAR present yet at s3://$BUCKET/$JAR_KEY" >> "$LOG_FILE"
    sleep 30
    continue
  fi

  if [ ! -f "$LAST_ETAG_FILE" ] || [ "$(cat "$LAST_ETAG_FILE")" != "$etag" ]; then
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - New JAR detected: $etag — Downloading..." >> "$LOG_FILE"
    # Updated to use s3api get-object with integrity and version validation
    aws s3api get-object \
        --bucket "$BUCKET" \
        --key "$JAR_KEY" \
        --if-match "$etag" \
        --checksum-mode ENABLED \
        "$LOCAL_JAR" 2>/dev/null || true
    chmod 644 "$LOCAL_JAR"
    echo "$etag" > "$LAST_ETAG_FILE"

    pids=$(pgrep -f "$LOCAL_JAR" || true)
    if [ -n "$pids" ]; then
      echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Stopping old Java processes: $pids" >> "$LOG_FILE"
      for pid in $pids; do
        kill -9 "$pid" || true
      done
      sleep 2
    fi

    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Starting updated app..." >> "$LOG_FILE"
    nohup java -jar "$LOCAL_JAR" --server.port=8080 >> "$LOG_FILE" 2>&1 &
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - App restarted successfully." >> "$LOG_FILE"
  fi
  sleep 15
done &

# Upload logs on shutdown
cat > /etc/systemd/system/upload-logs.service <<'US'
[Unit]
Description=Upload logs to S3 on shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=/bin/bash -c 'TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ); BUCKET="${existing_bucket_name}"; [ -f /var/log/cloud-init.log ] && aws s3 cp /var/log/cloud-init.log s3://$BUCKET/ec2/logs/cloud-init.$TIMESTAMP.log; [ -f /home/ubuntu/app/techeazy.log ] && aws s3 cp /home/ubuntu/app/techeazy.log s3://$BUCKET/app/logs/techeazy.$TIMESTAMP.log'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
US

systemctl daemon-reload
systemctl enable upload-logs.service
```