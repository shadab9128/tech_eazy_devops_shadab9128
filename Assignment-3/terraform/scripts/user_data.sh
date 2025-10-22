#!/bin/bash
set -e

# Variables passed from Terraform template
BUCKET_NAME="${existing_bucket_name}"
JAR_NAME="${existing_jar_key}"
ALB_DNS_NAME="${alb_dns_name}"
APP_DIR="/home/ubuntu/app"
LOG_FILE="/home/ubuntu/startup.log"

# -----------------------------
# Install dependencies for Ubuntu
# -----------------------------
sudo apt-get update -y
sudo apt-get install -y openjdk-17-jdk python3-pip curl unzip

# -----------------------------
# Install AWS CLI v2
# -----------------------------
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install

# -----------------------------
# Prepare application directory
# -----------------------------
mkdir -p $APP_DIR
cd $APP_DIR

# -----------------------------
# Fetch the JAR from S3
# -----------------------------
echo "$(date) - Downloading JAR from S3..." | tee -a $LOG_FILE
aws s3 cp s3://$BUCKET_NAME/$JAR_NAME $APP_DIR/app.jar

# Stop any existing app
if pgrep -f "app.jar" > /dev/null; then
  echo "$(date) - Stopping old process..." | tee -a $LOG_FILE
  pkill -f "app.jar"
fi

# -----------------------------
# Start the main app
# -----------------------------
echo "$(date) - Starting new app instance..." | tee -a $LOG_FILE
nohup java -jar app.jar --server.port=8080 > techeazy.log 2>&1 &

echo "$(date) - Application started successfully!" | tee -a $LOG_FILE

# -----------------------------
# Create fallback health check endpoint
# -----------------------------
cat > /home/ubuntu/health_check.py << 'EOF'
from http.server import BaseHTTPRequestHandler, HTTPServer
class MyServer(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/hello':
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><body><h1>Hello from Auto Scaling Group!</h1><p>Instance is healthy</p></body></html>")
        elif self.path == '/health':
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), MyServer)
    print("Health check server started on port 8080")
    server.serve_forever()
EOF

nohup python3 /home/ubuntu/health_check.py > /home/ubuntu/health_check.log 2>&1 &

# -----------------------------
# Load Generator (to test auto scaling)
# -----------------------------
cat > /home/ubuntu/load_test.sh <<EOF
#!/bin/bash
ALB_URL="http://${ALB_DNS_NAME}/hello"
echo "Starting load test against \$ALB_URL..."
while true; do
  for i in {1..50}; do
    curl -s "\$ALB_URL" > /dev/null &
  done
  sleep 1
done
EOF

chmod +x /home/ubuntu/load_test.sh
nohup /home/ubuntu/load_test.sh > /home/ubuntu/load_test.log 2>&1 &

echo "$(date) - Load generator started against http://${ALB_DNS_NAME}/hello" | tee -a $LOG_FILE
