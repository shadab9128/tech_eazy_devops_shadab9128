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

resource "random_id" "rand_id" {
  byte_length = 4
}

# -----------------------------
# S3 Bucket for app JAR (already existing)
# -----------------------------
data "aws_s3_bucket" "existing" {
  bucket = var.existing_bucket_name
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
# Launch Template
# -----------------------------
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.stage}-app-lt-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh", {
    bucket_name = var.existing_bucket_name
    jar_name    = var.existing_jar_key
  }))

  vpc_security_group_ids = [aws_security_group.sg.id]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.stage}-app-instance"
    }
  }
}

# -----------------------------
# Application Load Balancer (unchanged, no access_logs)
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

# -----------------------------
# Target Group & Listeners (added listener_8080)
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
    Name = "${var.stage}-tg"
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

# NEW: Listener on port 8080, forwarding to the target group
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
  name                      = "${var.stage}-asg-${random_id.rand_id.hex}"
  min_size                  = 2
  max_size                  = 4
  desired_capacity           = 2
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

# -----------------------------
# SNS Topic for ASG lifecycle notifications
# -----------------------------
resource "aws_sns_topic" "asg_notifications" {
  name = "${var.stage}-asg-notifications-${random_id.rand_id.hex}"
}

# -----------------------------
# IAM Role for ASG lifecycle hooks
# -----------------------------
resource "aws_iam_role" "asg_lifecycle_role" {
  name = "${var.stage}-asg-lc-role-${random_id.rand_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "autoscaling.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "asg_lc_policy" {
  name = "${var.stage}-asg-lc-policy-${random_id.rand_id.hex}"
  role = aws_iam_role.asg_lifecycle_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["sns:Publish"],
      Resource = aws_sns_topic.asg_notifications.arn
    }]
  })
}

# -----------------------------
# Lifecycle Hooks (Launch/Terminate)
# -----------------------------
resource "aws_autoscaling_lifecycle_hook" "launch_hook" {
  name                   = "${var.stage}-launch-hook"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result         = "CONTINUE"
  notification_target_arn = aws_sns_topic.asg_notifications.arn
  heartbeat_timeout      = 300
  role_arn               = aws_iam_role.asg_lifecycle_role.arn
}

resource "aws_autoscaling_lifecycle_hook" "terminate_hook" {
  name                   = "${var.stage}-terminate-hook"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"
  notification_target_arn = aws_sns_topic.asg_notifications.arn
  heartbeat_timeout      = 300
  role_arn               = aws_iam_role.asg_lifecycle_role.arn
}

# -----------------------------
# Lambda for logging ASG events to S3
# -----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "${var.stage}-lambda-role-${random_id.rand_id.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name   = "${var.stage}-lambda-s3-policy-${random_id.rand_id.hex}"
  policy = replace(file("${path.module}/policy/lambda_s3_write_policy.json"), "EXISTING_BUCKET_NAME", var.existing_bucket_name)
}

resource "aws_iam_role_policy_attachment" "lambda_attach_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda/asg_logger.zip"
  source {
    content  = file("${path.module}/lambda/asg_logger.py")
    filename = "asg_logger.py"
  }
}

resource "aws_lambda_function" "asg_logger" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.stage}-asg-logger-${random_id.rand_id.hex}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "asg_logger.handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  environment {
    variables = {
      BUCKET = var.existing_bucket_name
      PREFIX = "asg-events/"
    }
  }
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asg_logger.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.asg_notifications.arn
}

resource "aws_sns_topic_subscription" "sns_to_lambda" {
  topic_arn = aws_sns_topic.asg_notifications.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.asg_logger.arn
}

