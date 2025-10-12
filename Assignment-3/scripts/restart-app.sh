# /home/ubuntu/restart-app.sh
#!/bin/bash
set -e
APP_DIR="/home/ubuntu/app"
APP_NAME="hellomvc-0.0.1-SNAPSHOT.jar"
LOG="$APP_DIR/techeazy.log"

cd "$APP_DIR"

# Kill old process
pids=$(pgrep -f "$APP_NAME" || true)
if [ -n "$pids" ]; then
  echo "$(date) - stopping old app: $pids" >> "$LOG"
  kill -9 $pids
fi

# Download latest JAR from S3
aws s3 cp s3://techeazy-logs-devops/app/$APP_NAME $APP_DIR/$APP_NAME --quiet