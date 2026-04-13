# Remote backend configuration for Route53 state management

terraform {
  backend "s3" {
    bucket         = "daws84s-terraform-state"
    key            = "dev/dns/route53/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "daws84s-terraform-locks"
  }
}