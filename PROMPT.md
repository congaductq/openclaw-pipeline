# OpenClaw Pipeline - Knowledge Base

This document serves as the AI context and knowledge base for the OpenClaw Deployment Pipeline project.

## Project Overview

OpenClaw Deployment Pipeline is an infrastructure-as-code project that automates the deployment of OpenClaw AI gateway instances to AWS. It supports multiple deployment targets (EC2, Lightsail, EKS, local Docker) and a Go-based pipeline server for API-driven orchestration.

## Architecture

```
                          +-------------------+
                          |    Frontend App   |
                          | (webhook receiver)|
                          +--------+----------+
                                   |
                                   v
                      +------------------------+
                      |   Pipeline Server (Go) |
                      |   Port: 4000           |
                      |   EC2 / Lightsail      |
                      +--------+---------------+
                               |
                    +----------+----------+
                    |                     |
                    v                     v
          +-----------------+   +-----------------+
          | OpenClaw Inst 1 |   | OpenClaw Inst N |
          | (Docker)        |   | (Docker)        |
          | Port: 18789     |   | Port: 18789     |
          | EC2 / Lightsail |   | EC2 / Lightsail |
          +-----------------+   +-----------------+
```

### Components

1. **OpenClaw Container** (`ghcr.io/openclaw/openclaw:latest`)
   - Node.js AI gateway application
   - WebSocket gateway on port 18789
   - Manages AI agents, skills, and channel integrations
   - Supports 8+ AI providers (Anthropic, Gemini, OpenAI, Groq, xAI, Mistral, OpenRouter)
   - Config stored at `/home/node/.openclaw/`
   - Workspace at `/home/node/openclaw/workspace`

2. **Pipeline Server** (`server/`)
   - Go HTTP API on port 4000
   - Orchestrates OpenClaw deployments via Makefile/Terraform
   - Forwards webhook events to frontend
   - Auto-approves devices when pairing is required
   - Runs as systemd service on the server instance

3. **Infrastructure** (`terraform/`)
   - EC2 config: `terraform/ec2/` (default)
   - Lightsail config: `terraform/lightsail/` (alternative)
   - EKS config: `terraform/` (root)
   - Kubernetes manifests: `k8s/`

## Key File Paths

```
openclaw-pipeline/
  Makefile                          # All deployment targets (100+)
  docker-compose.yml                # Docker Compose for local + remote
  .env.example                      # Environment variables template
  openclaw.json                     # Optional local OpenClaw config

  terraform/
    ec2/                            # EC2 infrastructure (default)
      main.tf                       # Instance, security group, elastic IP
      variables.tf                  # Region, instance type, key name
      outputs.tf                    # IP, SSH command, dashboard URL
      user-data.sh                  # Docker + Docker Compose bootstrap
    lightsail/                      # Lightsail infrastructure (alternative)
      main.tf                       # Instance, static IP, firewall, key pair
      variables.tf                  # Region, bundle, key paths
      outputs.tf                    # IP, SSH command, dashboard URL
      user-data.sh                  # Docker + Docker Compose bootstrap
      terraform.tfvars.example      # Example config
    main.tf, vpc.tf, eks.tf, ...    # EKS infrastructure

  scripts/
    deploy-ec2.sh                   # Deploy OpenClaw to instance (EC2/Lightsail)
    deploy-server.sh                # Deploy Go pipeline server
    ec2-approve.sh                  # Auto-approve browser devices
    setup-cloudflare-tunnel.sh      # Setup HTTPS tunnel
    stop-cloudflare-tunnel.sh       # Stop tunnel
    setup-docker-env.sh             # Generate .env file
    webhook-notify.sh               # Send events to pipeline server

  server/
    main.go                         # HTTP server entry point
    handler/handler.go              # Request handlers
    runner/pipeline.go              # Pipeline execution (async make)
    webhook/notifier.go             # Event forwarding
    Dockerfile                      # Multi-stage Go build

  k8s/
    namespace.yaml                  # openclaw namespace
    deployment.yaml                 # Pod spec with health checks
    service.yaml                    # NLB LoadBalancer
    configmap.yaml                  # Non-sensitive config
    secret.yaml                     # API keys
    pvc.yaml                        # Persistent volumes
    storageclass.yaml               # GP3 storage class
```

## Environment Variables

### Required (at least one)
- `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code OAuth token
- `ANTHROPIC_API_KEY` — Anthropic API key
- `GEMINI_API_KEY` — Google Gemini API key
- `OPENAI_API_KEY` — OpenAI API key

### Optional API Keys
- `GROQ_API_KEY`, `XAI_API_KEY`, `MISTRAL_API_KEY`, `OPENROUTER_API_KEY`

### Configuration
- `OPENCLAW_GATEWAY_TOKEN` — Gateway auth token (auto-generated)
- `GATEWAY_PORT` — Gateway port (default: 18789)
- `DEFAULT_MODEL` — AI model (default: claude-sonnet-4-5-20250929)
- `DEFAULT_PROVIDER` — AI provider (default: anthropic)
- `EXEC_ASK` — Command execution mode: on=ask, off=auto

### Pipeline Server
- `SERVER_PORT` — API port (default: 4000)
- `FRONTEND_URL` — Frontend URL for webhooks (default: http://localhost:3000)
- `PIPELINE_DIR` — Path to pipeline repo

### Deployment Control
- `TF_DIR` — Terraform directory (terraform/ec2 or terraform/lightsail)
- `TF_STATE` — Terraform state file path
- `NAME` — Deployment name for multi-instance (default: main)
- `CLOUDFLARE` — Enable Cloudflare tunnel (true/false)
- `SKIP_APPROVAL` — Skip auto-approval (true/false)

## Makefile Target Reference

### EC2 (Default)
- `make ec2-full-setup` — Complete setup from scratch
- `make deploy-ec2` — Deploy/update OpenClaw
- `make ec2-create-key` / `ec2-delete-key` — SSH key management
- `make ec2-config` / `ec2-init` / `ec2-plan` / `ec2-setup` / `ec2-destroy` — Infrastructure
- `make ec2-logs` / `ec2-shell` / `ec2-tunnel` / `ec2-url` / `ec2-restart` — Management

### Lightsail (Alternative)
- `make ls-full-setup` — Complete setup: key + config + instance + deploy
- `make deploy-ls` — Deploy/update OpenClaw
- `make ls-create-key` / `ls-delete-key` — SSH key management
- `make ls-config` / `ls-init` / `ls-plan` / `ls-setup` / `ls-destroy` — Infrastructure
- `make ls-logs` / `ls-shell` / `ls-tunnel` / `ls-url` / `ls-restart` — Management
- `make ls-approve` / `ls-cloudflare-tunnel` / `ls-cloudflare-stop` — Access

### Pipeline Server
- `make server-full-setup` — EC2 setup (default)
- `make server-ls-full-setup` — Lightsail setup (alternative)
- `make server-deploy` / `server-ls-deploy` — Deploy server
- `make server-logs` / `server-ls-logs` — View logs
- `make server-url` / `server-ls-url` — Show URLs

### Docker (Local)
- `make quick-docker` — All-in-one local start
- `make install-docker` / `update-docker` / `logs-docker` / `docker-shell`
- `make open` / `approve` / `start`

### EKS (Production)
- `make quick-deploy` — All-in-one EKS deploy
- `make deploy-init` / `deploy-plan` / `deploy-apply` / `deploy-destroy`
- `make k8s-apply` / `k8s-status` / `k8s-logs` / `k8s-shell` / `k8s-secret` / `k8s-url`

## Deployment Flows

### EC2 Full Setup (~3 min)
```
make ec2-full-setup
  [1/4] ec2-create-key         # AWS CLI key pair (5s)
  [2/4] ec2-config             # Create terraform.tfvars (instant)
  [3/4] ec2-setup              # Terraform apply + wait for Docker (120s)
  [4/4] deploy-ec2             # Copy files, pull image, start container (30s)
```

### Lightsail Full Setup (~2-3 min)
```
make ls-full-setup
  [1/4] ls-create-key          # ssh-keygen locally (5s)
  [2/4] ls-config              # Create terraform.tfvars (instant)
  [3/4] ls-setup               # Terraform apply + wait for Docker (120s)
  [4/4] deploy-ls              # Copy files, pull image, start container (30s)
        + auto-approve         # Background device approval
        + cloudflare (optional)# HTTPS tunnel
```

### Pipeline Server Launch Flow
```
POST /launch {"name":"main","claude_code_oauth_token":"..."}
  -> Go server validates request
  -> Runs `make ec2-full-setup` asynchronously
  -> Sends webhook events to frontend as deployment progresses
  -> Auto-approves devices when PairingRequired event received
  -> Sends Completed/Failed event when done
```

## Common Operations

### Deploy new instance
```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... NAME=my-instance
```

### Update existing instance
```bash
make deploy-ec2 NAME=my-instance
```

### View logs
```bash
make ec2-logs NAME=my-instance
```

### SSH into instance
```bash
make ec2-shell NAME=my-instance
```

### Destroy instance
```bash
make ec2-destroy NAME=my-instance
```

### Switch between EC2 and Lightsail
The deploy scripts support a `TF_DIR` environment variable:
- EC2: `TF_DIR=terraform/ec2` (default for ec2-* targets)
- Lightsail: `TF_DIR=terraform/lightsail` (default for ls-* targets)

## Troubleshooting Patterns

### Instance not accessible
1. Check instance is running: `make ec2-shell` or `make ls-shell`
2. Check container status: `docker compose ps`
3. Check container logs: `docker compose logs`
4. Verify port is open: `curl http://localhost:18789`

### Deployment fails
1. Check AWS credentials: `aws sts get-caller-identity`
2. Check Terraform state: `terraform -chdir=terraform/ec2 show`
3. Check SSH key exists and has correct permissions (400)
4. Check user-data script completed: `cat /var/log/cloud-init-output.log`

### Container unhealthy
1. SSH into instance
2. Check Docker resources: `docker stats`
3. Check disk space: `df -h`
4. Restart: `docker compose restart`

## AWS Resources Created

### EC2
- EC2 instance (Amazon Linux 2023 AMI)
- Security group (ports 22, 18789, 4000)
- Elastic IP (free while attached)
- SSH key pair (created via AWS CLI)

### Lightsail
- Lightsail instance (Amazon Linux 2023)
- Static IP (free while attached)
- Key pair (imported from local SSH key)
- Firewall rules (ports 22, 18789, 4000)

### EKS
- VPC (10.0.0.0/16) with public/private subnets
- EKS cluster (v1.31) with managed node group
- IAM roles (cluster, node, EBS CSI driver)
- Network Load Balancer
- EBS persistent volumes (config 1GB, workspace 10GB)
