#!/bin/bash
set -e

# Variables passed from Terraform template
BUCKET_NAME="${existing_bucket_name}"
JAR_NAME="${existing_jar_key}"
APP_DIR="/home/ubuntu/app"
LOG_FILE="/home/ubuntu/startup.log"

# Install dependencies
sudo apt-get update -y
sudo apt-get install -y openjdk-17-jdk awscli

# Prepare application directory
mkdir -p $APP_DIR
cd $APP_DIR

# Fetch the latest JAR from S3
echo "$(date) - Downloading latest JAR from S3..." | tee -a $LOG_FILE
aws s3 cp s3://$BUCKET_NAME/$JAR_NAME $APP_DIR/$JAR_NAME

# Stop any existing app
if pgrep -f "$JAR_NAME" > /dev/null; then
  echo "$(date) - Stopping old process..." | tee -a $LOG_FILE
  pkill -f "$JAR_NAME"
fi

# Start the app
echo "$(date) - Starting new app instance..." | tee -a $LOG_FILE
nohup java -jar $JAR_NAME > techeazy.log 2>&1 &

echo "$(date) - Application started successfully!" | tee -a $LOG_FILE
