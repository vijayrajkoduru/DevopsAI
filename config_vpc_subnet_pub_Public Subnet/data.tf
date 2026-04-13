data "aws_vpc" "vpc_main" {
  id = var.vpc_id

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_internet_gateway" "existing" {
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

data "aws_subnets" "existing_public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}