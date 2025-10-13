variable "stage" {
  description = "Deployment stage: Dev or Prod"
  type        = string
  default     = "Dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "ami_id" {
  description = "AMI ID to use for EC2"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "AWS key pair name for SSH access"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo to clone"
  type        = string
  default     = "https://github.com/Trainings-TechEazy/test-repo-for-devops"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for logs"
  type        = string
}
variable "existing_bucket_name" {
  description = "Existing S3 bucket name that stores the JAR"
  type        = string
  default     = "techeazy-logs-devops"
}

variable "existing_jar_key" {
  description = "S3 key/path for the JAR file (e.g. app/hellomvc-0.0.1-SNAPSHOT.jar)"
  type        = string
  default     = "app/hellomvc-0.0.1-SNAPSHOT.jar"
}
variable "instance_count" {
  description = "Number of EC2 instances to launch"
  type        = number
  default     = 2
  
}


