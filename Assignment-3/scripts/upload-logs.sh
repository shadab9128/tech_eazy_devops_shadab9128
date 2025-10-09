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

