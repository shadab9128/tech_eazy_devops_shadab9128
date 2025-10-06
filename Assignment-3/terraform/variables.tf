variable "region" {
  default = "eu-north-1"
}
variable "key_name" {
  description = "EC2 key pair name"
  default = "wisecow"
}
variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-0a716d3f3b16d290c"
}
variable "stage" {
  type        = string
  description = "Deployment stage"
  default     = "dev"
}


