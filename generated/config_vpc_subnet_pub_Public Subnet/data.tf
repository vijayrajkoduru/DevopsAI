data "aws_vpc" "vpc_main" {
  id = var.vpc_id

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_internet_gateway" "existing_igw" {
  count = var.create_internet_gateway ? 0 : 1

  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "attachment.state"
    values = ["available"]
  }
}

locals {
  vpc_cidr_block = data.aws_vpc.vpc_main.cidr_block
  vpc_name       = lookup(data.aws_vpc.vpc_main.tags, "Name", "Production VPC")

  resolved_internet_gateway_id = var.create_internet_gateway ? (
    length(aws_internet_gateway.vpc_subnet_pub_igw) > 0 ? aws_internet_gateway.vpc_subnet_pub_igw[0].id : ""
  ) : (
    var.internet_gateway_id != "" ? var.internet_gateway_id : (
      length(data.aws_internet_gateway.existing_igw) > 0 ? data.aws_internet_gateway.existing_igw[0].id : ""
    )
  )

  subnet_full_name = "${local.vpc_name}-public-subnet"
}