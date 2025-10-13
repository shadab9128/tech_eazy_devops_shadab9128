# outputs.tf

# Output the ALB DNS name (useful for accessing the app on ports 80/8080)
output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
  description = "DNS name of the Application Load Balancer"
}

# Output the target group ARN (for reference)
output "target_group_arn" {
  value       = aws_lb_target_group.tg.arn
  description = "ARN of the ALB target group"
}

# Output the existing S3 bucket name (since it's not managed by Terraform, we just echo the variable)
output "existing_s3_bucket" {
  value       = var.existing_bucket_name
  description = "Name of the existing S3 bucket for JAR and logs"
}

# Output EC2 instance IDs (if using multiple instances)
output "ec2_instance_ids" {
  value       = aws_instance.app[*].id
  description = "IDs of the EC2 instances"
}