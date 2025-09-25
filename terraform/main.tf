provider "aws" {
  region = var.region
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg"
  description = "Allow SSH and HTTP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# IAM Roles
# -----------------------------

# Role 1a - Read-only role for S3
resource "aws_iam_role" "s3_read_role" {
  name = "${var.stage}-s3-read-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_read_policy" {
  name = "${var.stage}-s3-read-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.logs.arn,
        "${aws_s3_bucket.logs.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read_attach" {
  role       = aws_iam_role.s3_read_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

# Role 1b - Upload-only role
resource "aws_iam_role" "s3_uploader_role" {
  name = "${var.stage}-s3-uploader-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_upload_policy" {
  name = "${var.stage}-s3-upload-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:PutObjectAcl"]
      Resource = "${aws_s3_bucket.logs.arn}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_upload_attach" {
  role       = aws_iam_role.s3_uploader_role.name
  policy_arn = aws_iam_policy.s3_upload_policy.arn
}

resource "aws_iam_instance_profile" "uploader_profile" {
  name = "${var.stage}-uploader-profile"
  role = aws_iam_role.s3_uploader_role.name
}

# -----------------------------
# S3 Bucket - FIXED BUCKET POLICY
# -----------------------------
resource "aws_s3_bucket" "logs" {
  bucket = var.s3_bucket_name
  tags = {
    Name  = var.s3_bucket_name
    Stage = var.stage
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

data "aws_iam_policy_document" "bucket_policy" {
  # Allow uploader role to put objects
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.s3_uploader_role.arn]
    }
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
  }

  # Allow read role to list and get objects
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.s3_read_role.arn]
    }
    actions = [
      "s3:ListBucket",
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]
  }

  # Deny non-HTTPS traffic (security best practice)
  statement {
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [  # FIXED: This must be a list
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id = "expire-ec2-logs-7d"
    filter {
      prefix = "ec2/logs/"
    }
    status = "Enabled"
    expiration {
      days = 7
    }
  }

  rule {
    id = "expire-app-logs-7d"
    filter {
      prefix = "app/logs/"
    }
    status = "Enabled"
    expiration {
      days = 7
    }
  }
}
# -----------------------------
# EC2 Instance
# -----------------------------
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.sg.id]
  iam_instance_profile   = aws_iam_instance_profile.uploader_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "${var.stage}-ec2"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail

              sudo apt update -y
              sudo apt install -y openjdk-21-jdk git maven awscli

              cd /home/ubuntu
              git clone ${var.github_repo} app || true
              cd app
              mvn clean package

              # Start Spring Boot app
              nohup java -jar target/hellomvc-0.0.1-SNAPSHOT.jar --server.port=80 > /var/log/techeazy.log 2>&1 &

              # Upload script
              cat > /usr/local/bin/upload-logs.sh << 'SH'
              #!/bin/bash
              TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
              BUCKET=${var.s3_bucket_name}
              aws s3 cp /var/log/cloud-init.log s3://$BUCKET/ec2/logs/cloud-init-$TIMESTAMP.log
              aws s3 cp /var/log/techeazy.log s3://$BUCKET/app/logs/techeazy-$TIMESTAMP.log || true
              SH

              chmod +x /usr/local/bin/upload-logs.sh

              # Systemd service for shutdown upload
              cat > /etc/systemd/system/upload-logs.service << 'UNIT'
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
              UNIT

              systemctl daemon-reload
              systemctl enable upload-logs.service
              EOF
}
