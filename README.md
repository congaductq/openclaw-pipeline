# OpenClaw Docker Deployment

## Quick Start

```bash
make quick-docker
```

This will auto-extract config from `~/.openclaw/openclaw.json`, generate `.env`, start the container, and sync config.

## Manual Setup

### 1. Configure environment

Copy and edit the example env file:

```bash
cp .env.example .env
```

Fill in your API key (at least one provider):

```
OPENCLAW_GATEWAY_TOKEN=<your-token>
ANTHROPIC_API_KEY=<key>
# or GEMINI_API_KEY, OPENAI_API_KEY, GROQ_API_KEY, etc.
```

### 2. Start the container

```bash
make install-docker
```

### 3. Run onboarding

```bash
make onboard-docker
```

## Available Commands

| Command | Description |
|---------|-------------|
| `make quick-docker` | All-in-one start (recommended) |
| `make install-docker` | Start container |
| `make onboard-docker` | Run onboarding wizard |
| `make update-docker` | Pull latest image and restart |
| `make logs-docker` | Follow container logs |
| `make test-docker` | Test deployment health |
| `make docker-build` | Build local image |
| `make docker-shell` | Shell into container |
| `make docker-clean` | Stop and remove container + volumes |
| `make open` | Open dashboard in browser (auto-authenticates) |
| `make setup-docker-env` | Generate `.env` from `openclaw.json` |
| `make sync-docker-config` | Sync `openclaw.json` into running container |
