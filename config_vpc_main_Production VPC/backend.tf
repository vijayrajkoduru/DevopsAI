# -----------------------------------------------
# Terraform Remote State Backend
# -----------------------------------------------
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "production/vpc/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}