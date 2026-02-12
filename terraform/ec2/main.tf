terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data: Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group
resource "aws_security_group" "openclaw" {
  name_prefix = "openclaw-${var.deployment_name}-"
  description = "OpenClaw (${var.deployment_name}) - Allow SSH and gateway access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenClaw Gateway"
    from_port   = var.gateway_port
    to_port     = var.gateway_port
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
    Name           = "openclaw-${var.deployment_name}-sg"
    Deployment     = var.deployment_name
    ManagedBy      = "terraform"
  }
}

# EC2 Instance
resource "aws_instance" "openclaw" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.openclaw.id]

  user_data = file("${path.module}/user-data.sh")

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name           = "openclaw-${var.deployment_name}"
    Deployment     = var.deployment_name
    ManagedBy      = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Elastic IP (optional but recommended)
resource "aws_eip" "openclaw" {
  count    = var.use_elastic_ip ? 1 : 0
  instance = aws_instance.openclaw.id

  tags = {
    Name       = "openclaw-${var.deployment_name}-eip"
    Deployment = var.deployment_name
    ManagedBy  = "terraform"
  }
}
