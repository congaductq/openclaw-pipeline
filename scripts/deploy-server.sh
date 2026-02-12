#!/bin/bash
# Deploy the Pipeline Go server to EC2
# Usage: ./scripts/deploy-server.sh
#
# This deploys the Go pipeline server to an EC2 instance.
# The server orchestrates OpenClaw EC2 deployments via API.

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEPLOY_NAME=${DEPLOY_NAME:-server}
TF_STATE=${TF_STATE:-terraform-server.tfstate}
FRONTEND_URL=${FRONTEND_URL:-http://localhost:3000}
SERVER_PORT=${SERVER_PORT:-4000}

# Read CLAUDE_CODE_OAUTH_TOKEN from env or .env file
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ] && [ -f .env ]; then
  CLAUDE_CODE_OAUTH_TOKEN=$(grep '^CLAUDE_CODE_OAUTH_TOKEN=' .env 2>/dev/null | cut -d= -f2)
fi

# Get EC2 IP from terraform
EC2_IP=$(terraform -chdir=terraform/ec2 output -state="$TF_STATE" -raw public_ip 2>/dev/null)
if [ -z "$EC2_IP" ]; then
  echo "Error: No EC2 instance found. Run 'make server-setup' first."
  exit 1
fi

SSH_KEY=$(terraform -chdir=terraform/ec2 output -state="$TF_STATE" -json 2>/dev/null | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$HOME|")
if [ -z "$SSH_KEY" ]; then
  SSH_KEY="$HOME/.ssh/openclaw.pem"
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo -e "${GREEN}Pipeline Server Deployment${NC}"
echo -e "  EC2: ${EC2_IP}"
echo -e "  SSH Key: ${SSH_KEY}"
echo -e "  Frontend: ${FRONTEND_URL}"
echo -e "  OAuth Token: ${CLAUDE_CODE_OAUTH_TOKEN:0:20}..."
echo ""

# [1] Build Go binary for Linux
echo -e "${BLUE}[1/5] Building Go server for Linux...${NC}"
(cd server && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ../pipeline-server .)
echo "  Binary built: pipeline-server"

# [2] Install tools on EC2
echo -e "${BLUE}[2/5] Installing tools on EC2 (terraform, aws-cli, make, jq)...${NC}"
ssh -T $SSH_OPTS ec2-user@${EC2_IP} << 'ENDSSH'
set -e

# Install base tools
sudo yum install -y make jq git tar gzip unzip curl 2>/dev/null || true

# Install terraform if missing
if ! command -v terraform &>/dev/null; then
  echo "Installing Terraform..."
  TERRAFORM_VERSION="1.7.5"
  curl -sL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
  sudo unzip -o /tmp/terraform.zip -d /usr/local/bin/
  rm -f /tmp/terraform.zip
  terraform version
fi

# Install AWS CLI if missing
if ! command -v aws &>/dev/null; then
  echo "Installing AWS CLI..."
  curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  cd /tmp && unzip -o awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
  aws --version
fi

# Create dirs
mkdir -p /home/ec2-user/pipeline/terraform/ec2
mkdir -p /home/ec2-user/pipeline/scripts
mkdir -p /home/ec2-user/pipeline/server

echo "Tools ready"
ENDSSH

# [3] Copy pipeline project + binary to EC2
echo -e "${BLUE}[3/5] Copying pipeline project to EC2...${NC}"

# Stop existing server before overwriting binary
ssh -T $SSH_OPTS ec2-user@${EC2_IP} "sudo systemctl stop pipeline-server 2>/dev/null; rm -f /home/ec2-user/pipeline/pipeline-server" || true

# Clean and recreate remote dirs to avoid nesting issues
ssh -T $SSH_OPTS ec2-user@${EC2_IP} "rm -rf /home/ec2-user/pipeline/terraform/ec2 /home/ec2-user/pipeline/scripts && mkdir -p /home/ec2-user/pipeline/terraform/ec2 /home/ec2-user/pipeline/scripts"

scp $SSH_OPTS pipeline-server ec2-user@${EC2_IP}:/home/ec2-user/pipeline/
scp $SSH_OPTS Makefile ec2-user@${EC2_IP}:/home/ec2-user/pipeline/
scp $SSH_OPTS docker-compose.yml ec2-user@${EC2_IP}:/home/ec2-user/pipeline/
scp $SSH_OPTS .env ec2-user@${EC2_IP}:/home/ec2-user/pipeline/ 2>/dev/null || true
scp $SSH_OPTS openclaw.json ec2-user@${EC2_IP}:/home/ec2-user/pipeline/ 2>/dev/null || true
scp $SSH_OPTS .env.example ec2-user@${EC2_IP}:/home/ec2-user/pipeline/

# Copy scripts (individual files, not directory)
scp $SSH_OPTS scripts/*.sh ec2-user@${EC2_IP}:/home/ec2-user/pipeline/scripts/

# Copy terraform config files (*.tf, *.example — NOT state files)
scp $SSH_OPTS terraform/ec2/*.tf ec2-user@${EC2_IP}:/home/ec2-user/pipeline/terraform/ec2/
scp $SSH_OPTS terraform/ec2/user-data.sh ec2-user@${EC2_IP}:/home/ec2-user/pipeline/terraform/ec2/
scp $SSH_OPTS terraform/ec2/terraform.tfvars.example ec2-user@${EC2_IP}:/home/ec2-user/pipeline/terraform/ec2/
scp $SSH_OPTS terraform/ec2/terraform.tfvars ec2-user@${EC2_IP}:/home/ec2-user/pipeline/terraform/ec2/ 2>/dev/null || true
# Copy .terraform.lock.hcl for provider pinning
scp $SSH_OPTS terraform/ec2/.terraform.lock.hcl ec2-user@${EC2_IP}:/home/ec2-user/pipeline/terraform/ec2/ 2>/dev/null || true

# Copy AWS credentials
echo -e "  Copying AWS credentials..."
ssh -T $SSH_OPTS ec2-user@${EC2_IP} "mkdir -p ~/.aws"
scp $SSH_OPTS ~/.aws/credentials ec2-user@${EC2_IP}:~/.aws/ 2>/dev/null || true
scp $SSH_OPTS ~/.aws/config ec2-user@${EC2_IP}:~/.aws/ 2>/dev/null || true

# Copy SSH key to EC2 — unlock first, then copy, keep 600 so ec2-create-key can overwrite
ssh -T $SSH_OPTS ec2-user@${EC2_IP} "mkdir -p ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/openclaw.pem 2>/dev/null || true"
scp $SSH_OPTS ~/.ssh/openclaw.pem ec2-user@${EC2_IP}:~/.ssh/openclaw.pem
ssh -T $SSH_OPTS ec2-user@${EC2_IP} "chmod 600 ~/.ssh/openclaw.pem"

rm -f pipeline-server
echo "  Files copied"

# [4] Create systemd service with env vars and start
echo -e "${BLUE}[4/5] Starting pipeline server on EC2...${NC}"

# Write env file locally, then scp
cat > /tmp/pipeline-server.env << EOF
SERVER_PORT=${SERVER_PORT}
FRONTEND_URL=${FRONTEND_URL}
PIPELINE_DIR=/home/ec2-user/pipeline
CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}
WEBHOOK_URL=http://localhost:${SERVER_PORT}
HOME=/home/ec2-user
EOF
scp $SSH_OPTS /tmp/pipeline-server.env ec2-user@${EC2_IP}:/home/ec2-user/pipeline/server.env
rm -f /tmp/pipeline-server.env

ssh -T $SSH_OPTS ec2-user@${EC2_IP} << 'ENDSSH'
set -e

chmod +x /home/ec2-user/pipeline/pipeline-server
chmod +x /home/ec2-user/pipeline/scripts/*.sh 2>/dev/null || true

# Create systemd service
sudo tee /etc/systemd/system/pipeline-server.service > /dev/null << 'UNIT'
[Unit]
Description=OpenClaw Pipeline Server
After=network.target docker.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/pipeline
ExecStart=/home/ec2-user/pipeline/pipeline-server
EnvironmentFile=/home/ec2-user/pipeline/server.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable pipeline-server
sudo systemctl restart pipeline-server
sleep 2
sudo systemctl status pipeline-server --no-pager || true
ENDSSH

# [5] Health check
echo -e "${BLUE}[5/5] Health check...${NC}"
sleep 2
HEALTH=$(ssh -T $SSH_OPTS ec2-user@${EC2_IP} "curl -s http://localhost:${SERVER_PORT}/health" 2>/dev/null)
if echo "$HEALTH" | grep -q '"ok"'; then
  echo -e "  ${GREEN}Server is healthy!${NC}"
else
  echo -e "  ${YELLOW}Server may still be starting. Check: make server-logs${NC}"
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  Pipeline Server deployed!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "  API:     http://${EC2_IP}:${SERVER_PORT}"
echo -e "  Swagger: http://${EC2_IP}:${SERVER_PORT}/swagger"
echo -e "  Health:  http://${EC2_IP}:${SERVER_PORT}/health"
echo ""
echo -e "  SSH:  ssh -i ${SSH_KEY} ec2-user@${EC2_IP}"
echo -e "  Logs: make server-logs"
echo ""
echo -e "  Launch OpenClaw instance:"
echo -e "    curl -X POST http://${EC2_IP}:${SERVER_PORT}/launch -H 'Content-Type: application/json' \\"
echo -e "      -d '{\"name\":\"main\",\"claude_code_oauth_token\":\"sk-ant-oat01-...\",\"cloudflare\":true}'"
echo ""
