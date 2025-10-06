terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.15.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Random suffix
resource "random_id" "id" {
  byte_length = 4
}

# Security Group (HTTP + SSH)
resource "aws_security_group" "sg" {
  name        = "${var.stage}-sg-${random_id.id.hex}"
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

  tags = { Name = "${var.stage}-sg" }
}

# -----------------------------
# Default VPC
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


# S3 bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket = "${var.stage}-logs-${random_id.id.hex}"
  force_destroy = true
  tags = { Name = "${var.stage}-logs" }
}

# EC2 IAM Role (S3 access)
resource "aws_iam_role" "ec2_role" {
  name = "${var.stage}-ec2-role-${random_id.id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name = "${var.stage}-s3-policy-${random_id.id.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["s3:*"],
      Resource = ["${aws_s3_bucket.logs.arn}", "${aws_s3_bucket.logs.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.stage}-profile-${random_id.id.hex}"
  role = aws_iam_role.ec2_role.name
}

# EC2 instance (Free tier t2.micro)
resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.sg.id]
  iam_instance_profile        = aws_iam_instance_profile.profile.name
  key_name                    = var.key_name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y openjdk-21-jdk awscli
              echo "Hello from $(hostname)" > /var/www/html/index.html
              nohup busybox httpd -f -p 80 &
              EOF
  tags = { Name = "${var.stage}-ec2" }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = "${var.stage}-alb-${random_id.id.hex}"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.sg.id]
  enable_deletion_protection = false
  tags = { Name = "${var.stage}-alb" }
}

# Target Group & Listener
resource "aws_lb_target_group" "tg" {
  name     = "${var.stage}-tg"
  port     = 80
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
    Name = "${var.stage}-tg"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Attach instance to ALB
resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app.id
  port             = 80
}

