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

# SSH Key Pair — import local public key into Lightsail
resource "aws_lightsail_key_pair" "openclaw" {
  name       = "openclaw-${var.deployment_name}"
  public_key = file(var.public_key_path)
}

# Lightsail Instance
resource "aws_lightsail_instance" "openclaw" {
  name              = "openclaw-${var.deployment_name}"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.openclaw.name
  user_data         = file("${path.module}/user-data.sh")

  tags = {
    Deployment = var.deployment_name
    ManagedBy  = "terraform"
  }
}

# Static IP
resource "aws_lightsail_static_ip" "openclaw" {
  name = "openclaw-${var.deployment_name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "openclaw" {
  static_ip_name = aws_lightsail_static_ip.openclaw.name
  instance_name  = aws_lightsail_instance.openclaw.name
}

# Firewall — open SSH, Gateway, and Pipeline Server ports
resource "aws_lightsail_instance_public_ports" "openclaw" {
  instance_name = aws_lightsail_instance.openclaw.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = var.gateway_port
    to_port   = var.gateway_port
    cidrs     = ["0.0.0.0/0"]
  }

  port_info {
    protocol  = "tcp"
    from_port = 4000
    to_port   = 4000
    cidrs     = ["0.0.0.0/0"]
  }
}
