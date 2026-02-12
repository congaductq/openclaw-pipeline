#!/bin/bash
# Setup Cloudflare Tunnel on EC2 (optional, for HTTPS access without domain)
set -e

EC2_IP=$1
SSH_KEY=$2

if [ -z "$EC2_IP" ] || [ -z "$SSH_KEY" ]; then
  echo "Usage: $0 <EC2_IP> <SSH_KEY>"
  exit 1
fi

echo "Setting up Cloudflare Tunnel on EC2..."
echo "This will provide HTTPS access without needing a domain!"
echo ""

# Install cloudflared and start tunnel on EC2
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
# Stop any existing tunnel
if [ -f /tmp/cloudflared.pid ]; then
  kill $(cat /tmp/cloudflared.pid) 2>/dev/null || true
  rm -f /tmp/cloudflared.pid
fi

# Download and install cloudflared if not already installed
if ! command -v cloudflared &>/dev/null; then
  echo "Installing cloudflared..."
  curl -L --output cloudflared.rpm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
  sudo yum install -y cloudflared.rpm
  rm -f cloudflared.rpm
else
  echo "cloudflared already installed"
fi

# Create tunnel and get URL
echo ""
echo "Creating tunnel..."
rm -f /tmp/cloudflared.log
nohup cloudflared tunnel --url http://localhost:18789 > /tmp/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!
echo $CLOUDFLARED_PID > /tmp/cloudflared.pid

# Wait for tunnel to be ready (can take up to 60s)
echo "Waiting for tunnel URL (this may take up to 60 seconds)..."
TUNNEL_URL=""
for i in $(seq 1 60); do
  TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
  sleep 1
done

if [ -n "$TUNNEL_URL" ]; then
  echo ""
  echo "================================================================"
  echo "  Cloudflare Tunnel is running!"
  echo "================================================================"
  echo ""
  echo "  Public HTTPS URL:"
  echo "    $TUNNEL_URL"
  echo ""
  echo "  Chat URL:"
  echo "    ${TUNNEL_URL}/chat?session=main"
  echo ""
  echo "  Tunnel PID: $CLOUDFLARED_PID"
  echo "  To stop: make ec2-stop-cloudflare-tunnel"
  echo ""
else
  echo ""
  echo "Tunnel URL not found within 60 seconds."
  echo "The tunnel may still be starting. Check logs with:"
  echo "  ssh -i YOUR_KEY ec2-user@HOST 'cat /tmp/cloudflared.log'"
  echo ""
  echo "Recent log output:"
  tail -10 /tmp/cloudflared.log 2>/dev/null || echo "(no logs yet)"
  exit 1
fi
ENDSSH
