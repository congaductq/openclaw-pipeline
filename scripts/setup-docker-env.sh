#!/bin/bash
# Prepare .env for Docker from env vars, CLI flags, or project-local config (opt-in).
#
# Usage:
#   ./scripts/setup-docker-env.sh                              # env vars only, auto-generate token
#   ./scripts/setup-docker-env.sh --token <token>              # explicit token
#   ./scripts/setup-docker-env.sh --from-config                # read settings from ./openclaw.json
#   ANTHROPIC_API_KEY=sk-xxx ./scripts/setup-docker-env.sh     # env var override

set -e

CONFIG_FILE="openclaw.json"
ENV_FILE=".env"
USE_CONFIG=false

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-config)
            USE_CONFIG=true
            shift
            ;;
        --token)
            OPENCLAW_GATEWAY_TOKEN="$2"
            shift 2
            ;;
        --port)
            GATEWAY_PORT="$2"
            shift 2
            ;;
        --model)
            DEFAULT_MODEL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--from-config] [--token TOKEN] [--port PORT] [--model MODEL]"
            exit 1
            ;;
    esac
done

echo "Setting up OpenClaw Docker environment..."

# --- Clone from local config (opt-in only) ---
if [ "$USE_CONFIG" = true ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "  ERROR: --from-config requested but $CONFIG_FILE not found"
        exit 1
    fi
    echo "  Cloning settings from $CONFIG_FILE"

    # Token (CLI/env override still wins)
    if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
        OPENCLAW_GATEWAY_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        [ -n "$OPENCLAW_GATEWAY_TOKEN" ] && echo "  Token: cloned from config"
    fi

    # Port
    if [ -z "$GATEWAY_PORT" ]; then
        GATEWAY_PORT=$(jq -r '.gateway.port // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi

    # API keys (env vars take priority)
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-$(jq -r '.auth.profiles."anthropic:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"
    GEMINI_API_KEY="${GEMINI_API_KEY:-$(jq -r '.auth.profiles."google:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"
    OPENAI_API_KEY="${OPENAI_API_KEY:-$(jq -r '.auth.profiles."openai:default".apiKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")}"

    # Model
    if [ -z "$DEFAULT_MODEL" ]; then
        DEFAULT_MODEL=$(jq -r '.agents.defaults.model.primary // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi
fi

# --- Gateway token ---
# Priority: CLI flag > env var > (config if --from-config) > auto-generate
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "  Token: provided"
else
    OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 24)
    echo "  Token: auto-generated (new)"
fi

# --- Defaults ---
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
DEFAULT_MODEL="${DEFAULT_MODEL:-claude-sonnet-4-20250514}"
echo "  Port: $GATEWAY_PORT"
echo "  Model: $DEFAULT_MODEL"

# --- Report API keys ---
HAS_KEYS=false
[ -n "$ANTHROPIC_API_KEY" ] && echo "  Anthropic API key: set" && HAS_KEYS=true
[ -n "$GEMINI_API_KEY" ] && echo "  Gemini API key: set" && HAS_KEYS=true
[ -n "$OPENAI_API_KEY" ] && echo "  OpenAI API key: set" && HAS_KEYS=true
[ -n "$GROQ_API_KEY" ] && echo "  Groq API key: set" && HAS_KEYS=true
[ -n "$XAI_API_KEY" ] && echo "  xAI API key: set" && HAS_KEYS=true
[ -n "$MISTRAL_API_KEY" ] && echo "  Mistral API key: set" && HAS_KEYS=true
[ -n "$OPENROUTER_API_KEY" ] && echo "  OpenRouter API key: set" && HAS_KEYS=true
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && echo "  Claude Code OAuth token: set" && HAS_KEYS=true

if [ "$HAS_KEYS" = false ]; then
    echo ""
    echo "  WARNING: No API keys found. Set at least one provider key:"
    echo "    ANTHROPIC_API_KEY=sk-xxx make quick-docker"
    echo "    or edit .env after generation"
fi

# --- Write .env ---
cat > "$ENV_FILE" << EOF
# OpenClaw Docker Configuration (Auto-generated)
# Generated: $(date)
# Regenerate: make reset-env  |  Override: make quick-docker TOKEN=xxx ANTHROPIC_API_KEY=sk-xxx

# Gateway Configuration
OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN
GATEWAY_PORT=${GATEWAY_PORT}
NODE_ENV=production

# AI Provider API Keys
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
GEMINI_API_KEY=${GEMINI_API_KEY}
OPENAI_API_KEY=${OPENAI_API_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
XAI_API_KEY=${XAI_API_KEY}
MISTRAL_API_KEY=${MISTRAL_API_KEY}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}

# Claude Code OAuth Token
CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN}

# Model Configuration
DEFAULT_MODEL=${DEFAULT_MODEL}
DEFAULT_PROVIDER=$(echo "${DEFAULT_MODEL}" | cut -d'/' -f1)

# Security Settings
EXEC_ASK=on
LOG_LEVEL=info
LOG_FORMAT=json

# Docker Resources
DOCKER_CPUS=2.0
DOCKER_MEMORY=4G
EOF

echo ""
echo "Environment file created: $ENV_FILE"
echo "Gateway token: ${OPENCLAW_GATEWAY_TOKEN:0:16}..."
echo "Dashboard URL: http://localhost:$GATEWAY_PORT"
