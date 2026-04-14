terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# ── Security Group ─────────────────────────────────────────────────────────────

resource "aws_security_group" "devopsai_sg" {
  name        = "devopsai-sg"
  description = "Security group for devopsai.com EC2 instance"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FastAPI"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "devopsai-sg"
    ManagedBy = "Terraform"
  }
}

# ── EC2 Instance ───────────────────────────────────────────────────────────────

resource "aws_instance" "devopsai" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.devopsai_sg.id]

  tags = {
    Name      = "devopsai-server"
    ManagedBy = "Terraform"
  }
}

# ── Elastic IP (static public IP) ─────────────────────────────────────────────

resource "aws_eip" "devopsai_eip" {
  instance = aws_instance.devopsai.id
  domain   = "vpc"

  tags = {
    Name      = "devopsai-eip"
    ManagedBy = "Terraform"
  }
}
