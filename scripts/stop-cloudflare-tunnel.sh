#!/bin/bash
# Stop Cloudflare Tunnel on EC2
set -e

EC2_IP=$1
SSH_KEY=$2

if [ -z "$EC2_IP" ] || [ -z "$SSH_KEY" ]; then
  echo "Usage: $0 <EC2_IP> <SSH_KEY>"
  exit 1
fi

echo "Stopping Cloudflare Tunnel on EC2..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@${EC2_IP} << 'ENDSSH'
if [ -f /tmp/cloudflared.pid ]; then
  PID=$(cat /tmp/cloudflared.pid)
  kill $PID 2>/dev/null || true
  rm -f /tmp/cloudflared.pid /tmp/cloudflared.log
  echo "✓ Tunnel stopped"
else
  echo "No active tunnel found"
fi
ENDSSH
