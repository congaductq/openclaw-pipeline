#!/bin/bash
# Lightsail User Data - Install Docker and Docker Compose
set -e

echo "==== Installing Docker ===="

# Update system
yum update -y

# Install Docker
yum install -y docker

# Start Docker service
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose v2
DOCKER_COMPOSE_VERSION="v2.24.5"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify installations
docker --version
docker compose version

echo "==== Docker installation complete ===="

# Create directories
mkdir -p /home/ec2-user/openclaw
chown -R ec2-user:ec2-user /home/ec2-user/openclaw

echo "==== Setup complete ===="
