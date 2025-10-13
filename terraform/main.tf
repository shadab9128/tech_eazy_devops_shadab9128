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
    stage = var.stage
  }
}

# -----------------------------
# Security Group
# -----------------------------
resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg-${random_id.rand_id.hex}"
  description = "Allow SSH, HTTP, and App Port"

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

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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
# Existing S3 Bucket for JAR
# -----------------------------
data "aws_s3_bucket" "existing_app_bucket" {
  bucket = var.existing_bucket_name
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

# -----------------------------
# ALB Logs Bucket (for access logs)
# -----------------------------
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.stage}-alb-logs-${random_id.rand_id.hex}"

  tags = {
    Name  = "${var.stage}-alb-logs-${random_id.rand_id.hex}"
    Stage = var.stage
  }
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
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
      }
    ]
  })
}

# -----------------------------
# Target Group & Listeners
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
    Name = "${var.stage}-tg-${random_id.rand_id.hex}"
  }
}

resource "aws_lb_listener" "listener_80" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_listener" "listener_8080" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------------
# IAM Role for EC2 to Read from S3
# -----------------------------
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
  description = "Policy for EC2 read-only access to existing bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          "arn:aws:s3:::${var.existing_bucket_name}",
          "arn:aws:s3:::${var.existing_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "read_attach" {
  role       = aws_iam_role.s3_read_role.name
  policy_arn = aws_iam_policy.read_policy.arn
}

resource "aws_iam_instance_profile" "s3_read_profile" {
  name = "${var.stage}-s3-read-profile-${random_id.rand_id.hex}"
  role = aws_iam_role.s3_read_role.name
}

# -----------------------------
# EC2 Instances - Application
# -----------------------------
resource "aws_instance" "app" {
  count                       = var.instance_count
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.sg.id]
  subnet_id                   = element(data.aws_subnets.default.ids, count.index % length(data.aws_subnets.default.ids))
  iam_instance_profile        = aws_iam_instance_profile.s3_read_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -euo pipefail
              apt-get update -y
              apt-get install -y openjdk-21-jdk awscli
              mkdir -p /home/ubuntu/app
              cd /home/ubuntu/app
              aws s3 cp s3://${var.existing_bucket_name}/${var.existing_jar_key} app.jar
              nohup java -jar app.jar --server.port=8080 > /home/ubuntu/app/app.log 2>&1 &
              EOF

  tags = {
    Name  = "${var.stage}-ec2-${count.index}"
    Stage = var.stage
  }
}

# -----------------------------
# Attach EC2 to Target Group
# -----------------------------
resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = length(aws_instance.app)
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8080
}
