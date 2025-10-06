output "alb_dns" {
  description = "Public ALB DNS"
  value       = aws_lb.alb.dns_name
}

output "s3_bucket" {
  description = "S3 bucket for logs and jars"
  value       = aws_s3_bucket.logs.bucket
}

output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

#output "asg_name" {
# description = "AutoScaling Group name"
#value       = aws_autoscaling_group.asg.name
#}

