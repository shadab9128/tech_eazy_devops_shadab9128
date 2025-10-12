#!/bin/bash
set -euo pipefail

# variables injected by Terraform
GITHUB_REPO="${github_repo}"
BUCKET="${bucket_name}"
APP_DIR="/home/ubuntu/app"
JAR_KEY="app/app.jar"
LOCAL_JAR="${APP_DIR}/app.jar"
POLL_SCRIPT="/usr/local/bin/poll_s3.sh"
LOG_FILE="/home/ubuntu/app/techeazy.log"

apt-get update -y
apt-get install -y openjdk-21-jdk awscli jq

mkdir -p ${APP_DIR}
chown ubuntu:ubuntu ${APP_DIR}

# Write poll script
cat > ${POLL_SCRIPT} <<'PSH'
#!/bin/bash
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
PSH

chmod +x ${POLL_SCRIPT}
chown root:root ${POLL_SCRIPT}

# Upload logs on shutdown
cat > /usr/local/bin/upload-logs.sh <<'UL'
#!/bin/bash
set -euo pipefail
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
BUCKET="${bucket_name}"
if [ -f /var/log/cloud-init.log ]; then
  aws s3 cp /var/log/cloud-init.log s3://$BUCKET/ec2/logs/cloud-init.$TIMESTAMP.log
fi
if [ -f /home/ubuntu/techeazy.log ]; then
  aws s3 cp /home/ubuntu/techeazy.log s3://$BUCKET/app/logs/techeazy.$TIMESTAMP.log || true
fi
exit 0
UL

chmod +x /usr/local/bin/upload-logs.sh
chown root:root /usr/local/bin/upload-logs.sh

cat > /etc/systemd/system/upload-logs.service <<'US'
[Unit]
Description=Upload logs to S3 on shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=/usr/local/bin/upload-logs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
US

systemctl daemon-reload
systemctl enable upload-logs.service

sudo -u ubuntu nohup ${POLL_SCRIPT} "${BUCKET}" "${JAR_KEY}" "${LOCAL_JAR}" "${LOG_FILE}" > /var/log/poll_s3.log 2>&1 &
