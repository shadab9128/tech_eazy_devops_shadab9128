variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name (must exist in AWS)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "stage" {
  description = "Stage name (dev/prod)"
  type        = string
  default     = "dev"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for logs"
  type        = string
}

variable "instance_count" {
  description = "Number of EC2 instances to launch"
  type        = number
  default     = 2
}

variable "github_repo" {
  description = "GitHub repo to clone app from"
  type        = string
  default     = "https://github.com/Trainings-TechEazy/test-repo-for-devops"
}

