#!/bin/bash
# Sends a webhook event to the Go pipeline server.
# Usage: ./scripts/webhook-notify.sh <type> <message> [name]
#
# The Go server receives this and forwards to the frontend.
# WEBHOOK_URL env var overrides the default (http://localhost:4000).

TYPE=$1
MESSAGE=$2
NAME=${3:-main}
WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:4000}

if [ -z "$TYPE" ] || [ -z "$MESSAGE" ]; then
  exit 0
fi

curl -s -X POST "${WEBHOOK_URL}/webhook/event" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"${TYPE}\",\"name\":\"${NAME}\",\"message\":\"${MESSAGE}\"}" \
  >/dev/null 2>&1 || true
