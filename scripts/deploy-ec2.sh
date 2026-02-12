#!/bin/bash
# Deploy OpenClaw to EC2
# Usage: ./scripts/deploy-ec2.sh [EC2_IP] [SSH_KEY]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# State file flag for terraform (if provided via TF_STATE env var)
TF_STATE_FLAG=""
if [ -n "$TF_STATE" ]; then
  TF_STATE_FLAG="-state=$TF_STATE"
fi

# Get EC2 IP and SSH key from args or terraform output
if [ -z "$1" ]; then
  echo -e "${BLUE}[1/6] Getting EC2 IP from Terraform...${NC}"
  EC2_IP=$(terraform -chdir=terraform/ec2 output $TF_STATE_FLAG -raw public_ip 2>/dev/null)
  if [ -z "$EC2_IP" ]; then
    echo "Error: EC2 IP not found. Run 'make ec2-setup' first or pass IP as argument."
    exit 1
  fi
else
  EC2_IP=$1
fi

if [ -z "$2" ]; then
  SSH_KEY=$(terraform -chdir=terraform/ec2 output $TF_STATE_FLAG -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p')
  if [ -z "$SSH_KEY" ]; then
    SSH_KEY="~/.ssh/openclaw.pem"
  fi
else
  SSH_KEY=$2
fi

echo -e "${GREEN}Deploying to: ${EC2_IP}${NC}"
echo -e "${GREEN}SSH Key: ${SSH_KEY}${NC}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
  echo -e "${YELLOW}No .env file found. Creating...${NC}"
  make setup-docker-env CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN}"
fi

# Create openclaw.json for EC2 - merge local openclaw.json with EC2 overrides
TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2)
OAUTH=$(grep '^CLAUDE_CODE_OAUTH_TOKEN=' .env 2>/dev/null | cut -d= -f2)
if [ -f openclaw.json ]; then
  echo -e "  Found local openclaw.json — merging with EC2 overrides..."
  jq --arg token "$TOKEN" '
    .gateway.bind = "lan" |
    .gateway.port = 18789 |
    .gateway.auth.mode = "token" |
    .gateway.auth.token = $token |
    .gateway.trustedProxies = ["172.18.0.0/16", "172.17.0.0/16", "127.0.0.1/8"] |
    .agents.defaults.workspace = "/home/node/openclaw/workspace" |
    del(.meta, .wizard)
  ' openclaw.json > /tmp/openclaw-ec2.json
else
  echo -e "  No local openclaw.json — using minimal config..."
  cat > /tmp/openclaw-ec2.json << EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${TOKEN}"
    },
    "trustedProxies": ["172.18.0.0/16", "172.17.0.0/16", "127.0.0.1/8"]
  },
  "agents": {
    "defaults": {
      "workspace": "/home/node/openclaw/workspace"
    }
  }
}
EOF
fi

# Create auth-profiles.json for Claude API access
if [ -n "$OAUTH" ]; then
  printf '{"version":1,"profiles":{"anthropic:default":{"type":"api_key","provider":"anthropic","key":"%s"}},"lastGood":{"anthropic":"anthropic:default"}}' "$OAUTH" > /tmp/auth-profiles.json
else
  echo -e "${YELLOW}Warning: No CLAUDE_CODE_OAUTH_TOKEN in .env - agent auth will not be configured${NC}"
fi

echo -e "${BLUE}[2/6] Copying files to EC2...${NC}"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  docker-compose.yml \
  .env \
  ec2-user@${EC2_IP}:/home/ec2-user/openclaw/
# Copy auth-profiles if created
if [ -f /tmp/auth-profiles.json ]; then
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/auth-profiles.json ec2-user@${EC2_IP}:/tmp/
fi

echo -e "${BLUE}[3/6] Pulling latest image on EC2...${NC}"
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
cd /home/ec2-user/openclaw
docker compose pull
ENDSSH

echo -e "${BLUE}[4/6] Stopping old containers...${NC}"
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
cd /home/ec2-user/openclaw
docker compose down || true
ENDSSH

echo -e "${BLUE}[5/6] Starting OpenClaw and configuring...${NC}"
# Copy config and start container in one SSH session (faster)
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/openclaw-ec2.json ec2-user@${EC2_IP}:/tmp/
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
cd /home/ec2-user/openclaw
# Start container
docker compose up -d
sleep 3
# Configure while container is starting
docker exec -u root openclaw mkdir -p /home/node/.openclaw/agents/main/agent
docker exec -u root openclaw mkdir -p /home/node/openclaw/workspace
docker cp /tmp/openclaw-ec2.json openclaw:/home/node/.openclaw/openclaw.json
# Copy auth-profiles for Claude API access
if [ -f /tmp/auth-profiles.json ]; then
  docker cp /tmp/auth-profiles.json openclaw:/home/node/.openclaw/agents/main/agent/auth-profiles.json
  rm -f /tmp/auth-profiles.json
fi
docker exec -u root openclaw chown -R node:node /home/node/.openclaw /home/node/openclaw
rm -f /tmp/openclaw-ec2.json
docker restart openclaw
sleep 3
ENDSSH
rm -f /tmp/openclaw-ec2.json

echo -e "${BLUE}[6/6] Checking health...${NC}"
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
cd /home/ec2-user/openclaw
docker compose ps
docker compose logs --tail=20
ENDSSH

# Setup Cloudflare Tunnel if requested
TUNNEL_URL=""
if [ "${SETUP_CLOUDFLARE:-false}" = "true" ]; then
  echo ""
  echo -e "${BLUE}Setting up Cloudflare Tunnel...${NC}"
  chmod +x scripts/setup-cloudflare-tunnel.sh
  TUNNEL_OUTPUT=$(./scripts/setup-cloudflare-tunnel.sh "$EC2_IP" "$SSH_KEY" 2>&1) || true
  TUNNEL_URL=$(echo "$TUNNEL_OUTPUT" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
  if [ -n "$TUNNEL_URL" ]; then
    echo -e "  ${GREEN}Cloudflare Tunnel ready!${NC}"
  else
    echo -e "  ${YELLOW}Cloudflare Tunnel setup failed (you can retry: make ec2-cloudflare-tunnel NAME=${DEPLOY_NAME:-main})${NC}"
  fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  ✓ Deployment complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""

# Show access URLs
if [ -n "$TUNNEL_URL" ]; then
  echo -e "🔗 ${GREEN}Chat URL (HTTPS via Cloudflare):${NC}"
  echo -e "  ${BLUE}${TUNNEL_URL}/chat?session=main&token=${TOKEN}${NC}"
  echo ""
else
  echo -e "💬 ${GREEN}Chat URL:${NC}"
  echo -e "  ${BLUE}http://${EC2_IP}:18789/chat?session=main${NC}"
  echo ""
  echo -e "🔒 ${GREEN}Secure Access (run separately):${NC}"
  echo -e "  ${YELLOW}Cloudflare:${NC} make ec2-cloudflare-tunnel NAME=${DEPLOY_NAME:-main}"
  echo -e "  ${YELLOW}SSH Tunnel:${NC} make ec2-tunnel NAME=${DEPLOY_NAME:-main}"
  echo ""
fi

echo -e "💻 ${GREEN}SSH:${NC} ssh -i ${SSH_KEY} ec2-user@${EC2_IP}"
echo -e "📋 ${GREEN}Logs:${NC} make ec2-logs NAME=${DEPLOY_NAME:-main}"
echo -e "🔄 ${GREEN}Restart:${NC} make ec2-restart NAME=${DEPLOY_NAME:-main}"
echo -e "✅ ${GREEN}Approve:${NC} make ec2-approve NAME=${DEPLOY_NAME:-main}"
echo ""

# Install auto-approve cron job on EC2 (non-blocking, runs in background on EC2)
if [ "${SKIP_APPROVAL:-false}" != "true" ]; then
  echo -e "${BLUE}Installing auto-approve watcher on EC2...${NC}"
  bash scripts/ec2-approve.sh "$EC2_IP" "$SSH_KEY" "$TOKEN" 2>&1 | sed 's/^/  /' || true
  echo ""
else
  echo -e "${YELLOW}Skipping auto-approval (SKIP_APPROVAL=true)${NC}"
  echo ""
fi
