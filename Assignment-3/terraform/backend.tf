terraform {
  backend "s3" {
    bucket         = "techeazy-terraform-state"
    key            = "assignment-3/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "techeazy-terraform-locks"
    encrypt        = true
  }
}

