# OpenClaw Deployment Pipeline

Deploy and manage OpenClaw AI gateway instances on AWS.

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Docker](https://docs.docker.com/get-docker/) (for local development only)

```bash
aws sts get-caller-identity  # Verify AWS credentials
terraform version             # Should show v1.0+
```

## Quick Start

### EC2 (Recommended)

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

**Total time**: ~3 minutes | **Specs**: t3.medium (2 vCPU, 4GB RAM)

This creates an SSH key, provisions an EC2 instance, installs Docker, deploys OpenClaw, and shows your dashboard URL.

### Docker (Local Development)

```bash
make quick-docker CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

### Lightsail (Alternative)

```bash
make ls-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

### EKS (Production at Scale)

```bash
make quick-deploy
```

## Deployment Options

| Option | Cost/Month | Setup Time | Best For |
|--------|-----------|------------|----------|
| **EC2** (default) | ~$30 variable | ~3 min | Most use cases |
| Docker | Free | ~1 min | Local development |
| Lightsail | $20 fixed | ~2 min | Fixed pricing |
| EKS | $75+ | ~15 min | Production at scale |

## Multiple Instances

Deploy separate instances for different AI providers:

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... NAME=claude
make ec2-full-setup GEMINI_API_KEY=... NAME=gemini
make ec2-full-setup OPENAI_API_KEY=sk-... NAME=openai
```

## Documentation

| Document | Description |
|----------|-------------|
| [INSTANCE.md](INSTANCE.md) | OpenClaw Docker instance deployment & management |
| [PIPELINE.md](PIPELINE.md) | Pipeline server (Go API) for orchestrating deployments |
| [PROMPT.md](PROMPT.md) | Project knowledge base for AI context |

## Common Commands

### EC2 (Default)

| Command | Description |
|---------|-------------|
| `make ec2-full-setup` | Complete setup from scratch |
| `make deploy-ec2` | Deploy/update OpenClaw |
| `make ec2-logs` | Tail container logs |
| `make ec2-shell` | SSH into instance |
| `make ec2-tunnel` | SSH tunnel for localhost access |
| `make ec2-cloudflare-tunnel` | Cloudflare HTTPS tunnel |
| `make ec2-url` | Show dashboard URL |
| `make ec2-restart` | Restart containers |
| `make ec2-destroy` | Destroy instance |

### Docker (Local)

| Command | Description |
|---------|-------------|
| `make quick-docker` | All-in-one start |
| `make install-docker` | Start container |
| `make logs-docker` | Follow logs |
| `make docker-shell` | Shell into container |
| `make open` | Open dashboard in browser |
| `make approve` | Approve pending device |

### Pipeline Server

| Command | Description |
|---------|-------------|
| `make server-full-setup` | Full pipeline server setup (EC2) |
| `make server-logs` | Tail server logs |
| `make server-url` | Show API URL |

### Lightsail (Alternative)

| Command | Description |
|---------|-------------|
| `make ls-full-setup` | Complete Lightsail setup |
| `make deploy-ls` | Deploy/update on Lightsail |
| `make ls-logs` | Tail logs on Lightsail |
| `make ls-shell` | SSH to Lightsail |

Run `make help` for the full list of available commands.
