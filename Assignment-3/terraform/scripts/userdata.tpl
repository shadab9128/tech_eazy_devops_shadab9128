#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# -----------------------------
# Variables injected by Terraform
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
apt-get install -y openjdk-21-jdk awscli jq unzip net-tools

mkdir -p "$APP_DIR"
touch "$LOG_FILE"
chown ubuntu:ubuntu "$APP_DIR" "$LOG_FILE"

# -----------------------------
# Pre-fetch the JAR once before starting service
# -----------------------------
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Pre-fetching JAR from s3://$BUCKET/$JAR_KEY..." | tee -a "$LOG_FILE"
aws s3 cp "s3://$BUCKET/$JAR_KEY" "$LOCAL_JAR" --quiet || {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Initial JAR fetch failed. Will retry via systemd." | tee -a "$LOG_FILE"
}

chmod 644 "$LOCAL_JAR" || true

# -----------------------------
# Restart app script
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

if [ -f "$JAR_PATH" ]; then
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Starting new app..." >> "$LOG_FILE"
  nohup java -jar "$JAR_PATH" --server.port=8080 >> "$LOG_FILE" 2>&1 &
  sleep 5
  if netstat -tuln | grep -q ":8080"; then
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - App running successfully on port 8080." >> "$LOG_FILE"
  else
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - ERROR: App failed to start." >> "$LOG_FILE"
  fi
else
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - JAR not found at $JAR_PATH" >> "$LOG_FILE"
fi
EOF

chmod +x /usr/local/bin/restart-app.sh

# -----------------------------
# Systemd service to auto-update
# -----------------------------
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto-update Java app from S3
After=network-online.target cloud-init.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=15
ExecStart=/bin/bash -c '
  BUCKET="$BUCKET";
  APP_DIR="$APP_DIR";
  JAR_KEY="$JAR_KEY";
  LOCAL_JAR="$LOCAL_JAR";
  LAST_ETAG_FILE="$LAST_ETAG_FILE";
  LOG_FILE="$LOG_FILE";

  echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - Starting Auto-update loop..." >> "\$LOG_FILE";

  while true; do
    etag=\$(aws s3api head-object --bucket "\$BUCKET" --key "\$JAR_KEY" --query ETag --output text 2>/dev/null || echo "");
    if [ -z "\$etag" ]; then
      echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - No JAR found in S3 yet, retrying..." >> "\$LOG_FILE";
      sleep 20;
      continue;
    fi;

    if [ ! -f "\$LAST_ETAG_FILE" ] || [ "\$(cat "\$LAST_ETAG_FILE")" != "\$etag" ]; then
      echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - New JAR detected (\$etag). Downloading..." >> "\$LOG_FILE";
      aws s3 cp "s3://\$BUCKET/\$JAR_KEY" "\$LOCAL_JAR" --quiet || {
        echo "\$(date -u '+%Y-%m-%dT%H:%M:%SZ') - ERROR: Download failed." >> "\$LOG_FILE";
        sleep 30; continue;
      };
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

systemctl daemon-reload
systemctl enable app-auto-update.service
systemctl start app-auto-update.service
