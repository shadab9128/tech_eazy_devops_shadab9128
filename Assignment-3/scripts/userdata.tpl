#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# -----------------------------
# Variables (injected by Terraform)
# -----------------------------
GITHUB_REPO="${github_repo}"
BUCKET="${existing_bucket_name}"
APP_DIR="/home/ubuntu/app"
JAR_KEY="app/hellomvc-0.0.1-SNAPSHOT.jar"
LOCAL_JAR="$APP_DIR/hellomvc-0.0.1-SNAPSHOT.jar"
LOG_FILE="$APP_DIR/techeazy.log"
LAST_ETAG_FILE="/var/tmp/jar-etag"
SERVICE_FILE="/etc/systemd/system/app-auto-update.service"

# -----------------------------
# System setup
# -----------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openjdk-21-jdk awscli jq unzip

mkdir -p "$APP_DIR"
chown ubuntu:ubuntu "$APP_DIR"
touch "$LOG_FILE"
chown ubuntu:ubuntu "$LOG_FILE"

# -----------------------------
# Function: restart app safely
# -----------------------------
cat > /usr/local/bin/restart-app.sh <<'EOF'
#!/bin/bash
set -euo pipefail
APP_DIR="/home/ubuntu/app"
APP_NAME="hellomvc-0.0.1-SNAPSHOT.jar"
LOG_FILE="$APP_DIR/techeazy.log"
JAR_PATH="$APP_DIR/$APP_NAME"

pids=$(pgrep -f "$APP_NAME" || true)
if [ -n "$pids" ]; then
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Stopping old app (PIDs: $pids)" >> "$LOG_FILE"
  kill -9 $pids || true
  sleep 2
fi

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Starting updated app..." >> "$LOG_FILE"
nohup java -jar "$JAR_PATH" --server.port=8080 >> "$LOG_FILE" 2>&1 &
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - App restarted successfully." >> "$LOG_FILE"
EOF

chmod +x /usr/local/bin/restart-app.sh

# -----------------------------
# Create app auto-update service
# -----------------------------
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto-update Java app from S3
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStart=/bin/bash -c '
  BUCKET="$BUCKET";
  APP_DIR="$APP_DIR";
  JAR_KEY="$JAR_KEY";
  LOCAL_JAR="$LOCAL_JAR";
  LAST_ETAG_FILE="$LAST_ETAG_FILE";
  LOG_FILE="$LOG_FILE";
  while true; do
    etag=\$(aws s3api head-object --bucket "\$BUCKET" --key "\$JAR_KEY" --query ETag --output text 2>/dev/null || echo "");
    if [ -z "\$etag" ]; then
      echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - No JAR present yet in s3://\$BUCKET/\$JAR_KEY" >> "\$LOG_FILE";
      sleep 30;
      continue;
    fi;

    if [ ! -f "\$LAST_ETAG_FILE" ] || [ "\$(cat "\$LAST_ETAG_FILE")" != "\$etag" ]; then
      echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - New JAR detected (\$etag). Downloading..." >> "\$LOG_FILE";
      aws s3 cp "s3://\$BUCKET/\$JAR_KEY" "\$LOCAL_JAR" --quiet || { echo "Download failed" >> "\$LOG_FILE"; sleep 30; continue; };
      chmod 644 "\$LOCAL_JAR";
      echo "\$etag" > "\$LAST_ETAG_FILE";
      /usr/local/bin/restart-app.sh;
    fi;
    sleep 15;
  done
'

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------
# Enable auto-update service
# -----------------------------
systemctl daemon-reload
systemctl enable app-auto-update.service
systemctl start app-auto-update.service

# -----------------------------
# Upload logs on shutdown
# -----------------------------
cat > /etc/systemd/system/upload-logs.service <<EOF
[Unit]
Description=Upload EC2 logs to S3 on shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=/bin/bash -c '
  TIMESTAMP=\$(date -u +%Y%m%dT%H%M%SZ);
  BUCKET="$BUCKET";
  [ -f /var/log/cloud-init.log ] && aws s3 cp /var/log/cloud-init.log s3://\$BUCKET/ec2/logs/cloud-init.\$TIMESTAMP.log --quiet;
  [ -f /home/ubuntu/app/techeazy.log ] && aws s3 cp /home/ubuntu/app/techeazy.log s3://\$BUCKET/app/logs/techeazy.\$TIMESTAMP.log --quiet;
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable upload-logs.service
