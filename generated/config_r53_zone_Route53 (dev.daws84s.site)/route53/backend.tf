terraform {
  backend "s3" {
    bucket         = "daws84s-terraform-state"
    key            = "dev/route53/dev.daws84s.site/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "daws84s-terraform-locks"
  }
}