terraform {
  backend "s3" {
    bucket         = "techeazy-terraform-state-shad-1"
    key            = "assignment-3/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}

