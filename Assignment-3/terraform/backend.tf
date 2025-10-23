terraform {
  backend "s3" {
    bucket         = "techeazy-terraform-state-shad-2"
    key            = "assignment-3/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
  }
}

