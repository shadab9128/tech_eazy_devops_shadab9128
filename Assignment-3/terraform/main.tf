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
# Random suffix for unique names
# -----------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------
# Security Group (HTTP + SSH)
# -----------------------------
resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg-${random_id.suffix.hex}"
  description = "Allow HTTP and SSH inbound"

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

  tags = {
    Name  = "${var.stage}-sg"
    Stage = var.stage
  }
}

# -----------------------------
# Default VPC & Subnets
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
# S3 Bucket for logs
# -----------------------------
resource "aws_s3_bucket" "logs" {
  bucket        = "${var.stage}-logs-${random_id.suffix.hex}"
  force_destroy = true

  tags = {
    Name  = "${var.stage}-logs"
    Stage = var.stage
  }
}

# -----------------------------
# IAM Role & Policy for EC2
# -----------------------------
resource "aws_iam_role" "ec2_role" {
  name = "${var.stage}-ec2-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name   = "${var.stage}-s3-policy-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["${aws_s3_bucket.logs.arn}", "${aws_s3_bucket.logs.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.stage}-profile-${random_id.suffix.hex}"
  role = aws_iam_role.ec2_role.name
}

# -----------------------------
# EC2 Instance (Free Tier t3.micro)
# -----------------------------
resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  iam_instance_profile        = aws_iam_instance_profile.profile.name
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y openjdk-21-jdk awscli
              mkdir -p /home/ubuntu
              cd /home/ubuntu
              aws s3 cp s3://${var.s3_bucket_name}/app/techeazy.jar /home/ubuntu/app.jar || true
              if [ -f /home/ubuntu/app.jar ]; then
                nohup java -jar /home/ubuntu/app.jar --server.port=80 > /var/log/techeazy.log 2>&1 &
              fi
              EOF

  tags = {
    Name  = "${var.stage}-ec2-${random_id.suffix.hex}"
    Stage = var.stage
  }
}

# -----------------------------
# Application Load Balancer
# -----------------------------
resource "aws_lb" "alb" {
  name               = "${var.stage}-alb-${random_id.suffix.hex}"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.sg.id]
  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name  = "${var.stage}-alb"
    Stage = var.stage
  }
}

# -----------------------------
# Target Group
# -----------------------------
resource "aws_lb_target_group" "tg" {
  name     = "${var.stage}-tg-${random_id.suffix.hex}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/hello"
    port                = "80"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name  = "${var.stage}-tg"
    Stage = var.stage
  }
}

# -----------------------------
# Listener
# -----------------------------
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -----------------------------
# Attach EC2 to Target Group
# -----------------------------
resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app.id
  port             = 80
}
