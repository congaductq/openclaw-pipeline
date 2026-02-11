#!/bin/bash
# Helper script to extract OpenClaw configuration from ~/.openclaw/openclaw.json
# and prepare Docker environment variables

set -e

CONFIG_FILE="$HOME/.openclaw/openclaw.json"
ENV_FILE=".env"

echo "🔍 Extracting OpenClaw configuration for Docker..."

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️  No existing configuration found at $CONFIG_FILE"
    echo "📋 Creating new configuration..."
    
    # Create default values
    OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    GATEWAY_PORT=18789
    
    echo "✅ Generated new gateway token"
else
    echo "✅ Found existing configuration at $CONFIG_FILE"
    
    # Extract gateway token
    OPENCLAW_GATEWAY_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
        echo "⚠️  No gateway token found in config, generating new one..."
        OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
    else
        echo "✅ Extracted gateway token: ${OPENCLAW_GATEWAY_TOKEN:0:16}..."
    fi
    
    # Extract gateway port
    GATEWAY_PORT=$(jq -r '.gateway.port // 18789' "$CONFIG_FILE" 2>/dev/null || echo "18789")
    echo "✅ Gateway port: $GATEWAY_PORT"
    
    # Extract API keys (env vars take priority over config)
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-$(jq -r '.auth.profiles."anthropic:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"
    GEMINI_API_KEY="${GEMINI_API_KEY:-$(jq -r '.auth.profiles."google:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"
    OPENAI_API_KEY="${OPENAI_API_KEY:-$(jq -r '.auth.profiles."openai:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"

    [ -n "$ANTHROPIC_API_KEY" ] && echo "✅ Found Anthropic API key"
    [ -n "$GEMINI_API_KEY" ] && echo "✅ Found Gemini API key"
    [ -n "$OPENAI_API_KEY" ] && echo "✅ Found OpenAI API key"
    
    # Extract default model
    DEFAULT_MODEL=$(jq -r '.agents.defaults.model.primary // "claude-sonnet-4-20250514"' "$CONFIG_FILE" 2>/dev/null || echo "claude-sonnet-4-20250514")
    echo "✅ Default model: $DEFAULT_MODEL"
fi

# Create .env file
cat > "$ENV_FILE" << EOF
# OpenClaw Docker Configuration (Auto-generated)
# Generated: $(date)
# Source: $CONFIG_FILE

# Gateway Configuration
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN
GATEWAY_PORT=$GATEWAY_PORT
NODE_ENV=production

# AI Provider API Keys
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
GEMINI_API_KEY=$GEMINI_API_KEY
OPENAI_API_KEY=$OPENAI_API_KEY
GROQ_API_KEY=
XAI_API_KEY=
MISTRAL_API_KEY=
OPENROUTER_API_KEY=

# Model Configuration
DEFAULT_MODEL=${DEFAULT_MODEL:-claude-sonnet-4-20250514}
DEFAULT_PROVIDER=$(echo "$DEFAULT_MODEL" | cut -d'/' -f1)

# Security Settings
EXEC_ASK=on
LOG_LEVEL=info
LOG_FORMAT=json

# Docker Resources
DOCKER_CPUS=2.0
DOCKER_MEMORY=4G
EOF

echo ""
echo "✅ Configuration extracted successfully!"
echo "📄 Environment file created: $ENV_FILE"
echo ""
echo "🚀 You can now run: docker-compose up -d"
echo ""
echo "Gateway Token (for dashboard): ${OPENCLAW_GATEWAY_TOKEN:0:16}...${OPENCLAW_GATEWAY_TOKEN: -8}"
echo "Dashboard URL: http://localhost:$GATEWAY_PORT"
