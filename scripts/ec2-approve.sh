#!/bin/bash
# Auto-approve devices for EC2 deployment
# Installs a background watcher on EC2 that checks every 5 seconds and approves pending devices
# After approving 3 devices (or 10 minutes timeout), it stops itself
set -e

EC2_IP=$1
SSH_KEY=$2
TOKEN=$3

if [ -z "$EC2_IP" ] || [ -z "$SSH_KEY" ] || [ -z "$TOKEN" ]; then
  echo "Usage: $0 <EC2_IP> <SSH_KEY> <TOKEN>"
  exit 1
fi

# Expand tilde in SSH_KEY
SSH_KEY=$(echo "$SSH_KEY" | sed "s|^~|$HOME|")

echo "Installing auto-approve watcher on EC2..."

# Create the watcher script and start it as a background process on EC2
ssh -T -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@${EC2_IP} "TOKEN=$TOKEN bash -s" << 'ENDSSH'
# Kill any existing auto-approve watcher
if [ -f /home/ec2-user/.auto-approve.pid ]; then
  OLD_PID=$(cat /home/ec2-user/.auto-approve.pid)
  kill "$OLD_PID" 2>/dev/null || true
  rm -f /home/ec2-user/.auto-approve.pid
fi

# Create the auto-approve watcher script
cat > /home/ec2-user/auto-approve.sh << 'SCRIPT'
#!/bin/bash
# Auto-approve pending devices, runs as background loop
TOKEN_FILE="/home/ec2-user/.openclaw-token"
TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
LOG="/home/ec2-user/auto-approve.log"
PID_FILE="/home/ec2-user/.auto-approve.pid"
MAX_APPROVALS=3
MAX_ITERATIONS=120  # 120 * 5s = 10 minutes timeout
COUNT=0
ITER=0

echo "$(date): Auto-approve watcher started (PID $$)" >> "$LOG"

while [ "$ITER" -lt "$MAX_ITERATIONS" ]; do
  ITER=$((ITER + 1))

  # Check if container is running
  if ! docker exec openclaw true 2>/dev/null; then
    sleep 5
    continue
  fi

  # List devices and look for pending UUIDs
  DEVICES=$(docker exec openclaw node /app/openclaw.mjs devices list --url ws://127.0.0.1:18789 --token "$TOKEN" 2>/dev/null || true)
  REQ=$(echo "$DEVICES" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

  if [ -n "$REQ" ]; then
    docker exec openclaw node /app/openclaw.mjs devices approve "$REQ" --url ws://127.0.0.1:18789 --token "$TOKEN" 2>/dev/null
    echo "$(date): Approved device $REQ" >> "$LOG"
    COUNT=$((COUNT + 1))

    if [ "$COUNT" -ge "$MAX_APPROVALS" ]; then
      echo "$(date): Approved $COUNT devices, stopping watcher" >> "$LOG"
      rm -f "$PID_FILE"
      exit 0
    fi
  fi

  sleep 5
done

echo "$(date): Timed out after 10 minutes ($COUNT devices approved), stopping watcher" >> "$LOG"
rm -f "$PID_FILE"
SCRIPT

chmod +x /home/ec2-user/auto-approve.sh

# Save token for the watcher
echo "$TOKEN" > /home/ec2-user/.openclaw-token
chmod 600 /home/ec2-user/.openclaw-token

# Start watcher in background
nohup /home/ec2-user/auto-approve.sh > /dev/null 2>&1 &
echo $! > /home/ec2-user/.auto-approve.pid

echo "Auto-approve watcher started (PID $!, checks every 5s, max 10 min)"
echo "Log: /home/ec2-user/auto-approve.log"
ENDSSH

echo "Auto-approve watcher installed on EC2."
echo "It will approve up to 3 browser connections, then stop (10 min timeout)."
