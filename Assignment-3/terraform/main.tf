terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.15.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------
# Random ID
# -----------------------------
resource "random_id" "rand_id" {
  byte_length = 8
  keepers = {
    # Change this to force new random ID
    stage = var.stage
  }
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg-${random_id.rand_id.hex}"
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
ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.stage}-sg"
    Stage = var.stage
  }
}

# -----------------------------
# Networking - Default VPC and Subnets
# -----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------
# S3 Buckets
# -----------------------------

# Logs bucket
resource "aws_s3_bucket" "logs" {
  bucket = var.s3_bucket_name${random_id.rand_id.hex}
  tags = {
    Name  = var.s3_bucket_name
    Stage = var.stage
  }
}

# Remove ACL resources and use bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs_lifecycle" {
  bucket     = aws_s3_bucket.logs.id
  depends_on = [aws_s3_bucket_ownership_controls.logs]

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

# ALB logs bucket
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.stage}-alb-logs-${random_id.rand_id.hex}"
  tags = {
    Name  = "${var.stage}-alb-logs-${random_id.rand_id.hex}"
    Stage = var.stage
  }
}

# ALB logs bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ALB logs bucket policy for Load Balancer delivery
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  depends_on = [aws_s3_bucket_ownership_controls.alb_logs]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# -----------------------------
# Target Group
# -----------------------------
resource "aws_lb_target_group" "tg" {
  name     = "${var.stage}-tg-${random_id.rand_id.hex}"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
  path                = "/hello"
  port                = "8080"
  protocol            = "HTTP"
  healthy_threshold   = 2
  unhealthy_threshold = 2
  interval            = 30
  timeout             = 5
}

  tags = {
    Name  = "${var.stage}-tg"
  }
}


# -----------------------------
# ALB Listener
# -----------------------------
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------------
# Attach EC2 instances to Target Group
# -----------------------------
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = length(aws_instance.app)
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8080
}
###############################################################################
# EC2 Instances - app
# Creates var.instance_count instances and attaches instance profile
###############################################################################
resource "aws_instance" "app" {
  count                       = var.instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg.id]
  subnet_id                   = element(data.aws_subnets.default.ids, count.index % length(data.aws_subnets.default.ids))
  iam_instance_profile        = aws_iam_instance_profile.uploader_profile.name
  associate_public_ip_address = true

  # Simple user_data: download jar from S3 (app/techeazy.jar) and run on port 8080
  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              apt-get update -y
              apt-get install -y openjdk-21-jdk awscli
              mkdir -p /home/ubuntu
              cd /home/ubuntu
              # try to download jar from S3 (will succeed if you've uploaded it)
              aws s3 cp s3://${var.s3_bucket_name}/app/techeazy.jar /home/ubuntu/app.jar || true
              # start app if present
              if [ -f /home/ubuntu/app.jar ]; then
                nohup java -jar /home/ubuntu/app.jar --server.port=80 > /var/log/techeazy.log 2>&1 &
              fi
              EOF

  tags = {
    Name  = "${var.stage}-ec2-${count.index}"
    Stage = var.stage
  }
}


# -----------------------------
# IAM Roles
# -----------------------------

# Uploader Role
resource "aws_iam_role" "s3_uploader_role" {
  name = "${var.stage}-s3-uploader-role-${random_id.rand_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "uploader_policy" {
  name        = "${var.stage}-s3-uploader-policy-${random_id.rand_id.hex}"
  description = "Policy for S3 uploader role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:PutObject", "s3:PutObjectAcl"],
      Resource = ["${aws_s3_bucket.logs.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "uploader_attach" {
  role       = aws_iam_role.s3_uploader_role.name
  policy_arn = aws_iam_policy.uploader_policy.arn
}

resource "aws_iam_instance_profile" "uploader_profile" {
  name = "${var.stage}-uploader-profile-${random_id.rand_id.hex}"
  role = aws_iam_role.s3_uploader_role.name
}

# Read-only Role
resource "aws_iam_role" "s3_read_role" {
  name = "${var.stage}-s3-read-role-${random_id.rand_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "read_policy" {
  name        = "${var.stage}-s3-read-policy-${random_id.rand_id.hex}"
  description = "Policy for S3 read-only access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "read_attach" {
  role       = aws_iam_role.s3_read_role.name
  policy_arn = aws_iam_policy.read_policy.arn
}

# -----------------------------
# Application Load Balancer
# -----------------------------
resource "aws_lb" "alb" {
  name               = "${var.stage}-alb-${random_id.rand_id.hex}"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.sg.id]

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}
