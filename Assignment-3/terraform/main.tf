terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------
# Random ID for unique naming
# -----------------------------
resource "random_id" "rand_id" {
  byte_length = 4
}

# -----------------------------
# Existing S3 Bucket (for JAR)
# -----------------------------
data "aws_s3_bucket" "existing" {
  bucket = var.existing_bucket_name
}

# -----------------------------
# IAM Role + Policy for EC2
# -----------------------------
resource "aws_iam_role" "ec2_role" {
  name = "${var.stage}-ec2-role-${random_id.rand_id.hex}"

  # Trust policy (allow EC2 to assume this role)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Load S3 read-only policy dynamically from template
resource "aws_iam_role_policy" "s3_read_only" {
  name = "${var.stage}-s3-readonly-policy"
  role = aws_iam_role.ec2_role.id

  policy = templatefile("${path.module}/policy/s3_read_only_policy.json.tpl", {
    bucket_name = var.existing_bucket_name
  })
}

# Instance profile to attach the IAM role to EC2 instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.stage}-ec2-profile-${random_id.rand_id.hex}"
  role = aws_iam_role.ec2_role.name
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
# Launch Template (EC2)
# -----------------------------
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.stage}-app-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh", {
    existing_bucket_name = var.existing_bucket_name
    existing_jar_key     = var.existing_jar_key
  }))

  # ✅ Attach the instance profile with S3 read access
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.stage}-app-instance"
    }
  }
}

# -----------------------------
# Load Balancer + Target Group
# -----------------------------
resource "aws_lb" "alb" {
  name               = "${var.stage}-alb-${random_id.rand_id.hex}"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.sg.id]
  enable_deletion_protection = false

  tags = {
    Name = "${var.stage}-alb"
  }
}

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
    Name = "${var.stage}-tg"
  }
}

# Listener on port 80
resource "aws_lb_listener" "listener_80" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Listener on port 8080
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
# Auto Scaling Group
# -----------------------------
resource "aws_autoscaling_group" "app_asg" {
  name                = "${var.stage}-asg-${random_id.rand_id.hex}"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier       = data.aws_subnets.default.ids
  target_group_arns         = [aws_lb_target_group.tg.arn]
  health_check_grace_period = 90
  health_check_type         = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.stage}-asg-instance"
    propagate_at_launch = true
  }
}
