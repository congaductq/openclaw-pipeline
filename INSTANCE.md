# OpenClaw Instance

Deploy and manage OpenClaw Docker instances — the AI gateway that connects to multiple AI providers (Claude, Gemini, OpenAI, Groq, xAI, Mistral, OpenRouter).

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- At least one AI provider key or `CLAUDE_CODE_OAUTH_TOKEN`

## Quick Start

### EC2 (Recommended)

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

**Total time**: ~3 minutes | **Specs**: t3.medium (2 vCPU, 4GB RAM)

### Docker (Local)

```bash
make quick-docker CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

---

## Deployment Methods

### 1. Docker (Local Development)

```bash
# All-in-one start
make quick-docker CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Or manual setup
cp .env.example .env        # Edit with your API keys
make install-docker          # Start container
make onboard-docker          # Run onboarding wizard
```

| Command | Description |
|---------|-------------|
| `make quick-docker` | All-in-one start (recommended) |
| `make install-docker` | Start container |
| `make onboard-docker` | Run onboarding wizard |
| `make update-docker` | Pull latest image and restart |
| `make logs-docker` | Follow container logs |
| `make test-docker` | Test deployment health |
| `make docker-shell` | Shell into container |
| `make docker-clean` | Stop and remove container + volumes |
| `make open` | Open dashboard in browser (auto-authenticates) |
| `make approve` | Approve pending browser device |
| `make start` | Start with config sync |
| `make setup-docker-env` | Generate `.env` |
| `make reset-env` | Force regenerate `.env` |
| `make clone-config` | Generate `.env` from `openclaw.json` |
| `make sync-docker-config` | Sync `openclaw.json` into running container |
| `make verify-auth` | Verify auth-profiles.json |
| `make check-model` | Show model configuration |

### 2. EC2 (Default - Recommended)

Variable pricing. Flexible instance types and full EC2 feature set.

#### One-Command Setup

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

This command:
1. Creates SSH key pair via AWS CLI
2. Configures Terraform
3. Launches EC2 instance (~2 min)
4. Auto-installs Docker
5. Deploys OpenClaw (~30 sec)
6. Shows your dashboard URL

#### Step-by-Step

```bash
make ec2-create-key    # Create SSH key pair via AWS CLI
make ec2-config        # Create terraform.tfvars
make ec2-setup         # Create EC2 instance (~2 min)
make deploy-ec2        # Deploy OpenClaw
make ec2-url           # Show dashboard URL
```

#### EC2 Commands

| Command | Description |
|---------|-------------|
| `make ec2-full-setup` | Complete setup from scratch |
| `make deploy-ec2` | Deploy/update OpenClaw |
| `make ec2-logs` | Tail container logs |
| `make ec2-shell` | SSH into instance |
| `make ec2-tunnel` | SSH tunnel (localhost access) |
| `make ec2-cloudflare-tunnel` | Cloudflare HTTPS tunnel |
| `make ec2-cloudflare-stop` | Stop Cloudflare tunnel |
| `make ec2-url` | Show dashboard URL |
| `make ec2-restart` | Restart containers |
| `make ec2-approve` | Approve pending device |
| `make ec2-plan` | Preview infrastructure changes |
| `make ec2-destroy` | Destroy instance |

#### EC2 Pricing (us-west-2, approximate)

| Instance | vCPU | RAM | Cost/Month |
|----------|------|-----|------------|
| t3.micro | 2 | 1GB | ~$8 |
| t3.small | 2 | 2GB | ~$15 |
| **t3.medium** | **2** | **4GB** | **~$30** (default) |
| t3.large | 2 | 8GB | ~$60 |
| t3.xlarge | 4 | 16GB | ~$120 |

Change instance type in `terraform/ec2/terraform.tfvars`:
```hcl
instance_type = "t3.large"  # ~$60/mo — 2 vCPU, 8GB RAM
```

### 3. Lightsail (Alternative)

Fixed monthly pricing. Simple and predictable.

#### One-Command Setup

```bash
make ls-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

This command:
1. Creates SSH key pair locally
2. Configures Terraform
3. Launches Lightsail instance (~1-2 min)
4. Auto-installs Docker
5. Deploys OpenClaw (~30 sec)
6. Shows your dashboard URL

#### Step-by-Step

```bash
make ls-create-key     # Create SSH key pair
make ls-config         # Create terraform.tfvars
make ls-setup          # Create Lightsail instance
make deploy-ls         # Deploy OpenClaw
make ls-url            # Show dashboard URL
```

#### Lightsail Commands

| Command | Description |
|---------|-------------|
| `make ls-full-setup` | Complete setup from scratch |
| `make deploy-ls` | Deploy/update OpenClaw |
| `make ls-logs` | Tail container logs |
| `make ls-shell` | SSH into instance |
| `make ls-tunnel` | SSH tunnel (localhost access) |
| `make ls-cloudflare-tunnel` | Cloudflare HTTPS tunnel |
| `make ls-cloudflare-stop` | Stop Cloudflare tunnel |
| `make ls-url` | Show dashboard URL |
| `make ls-restart` | Restart containers |
| `make ls-approve` | Approve pending device |
| `make ls-plan` | Preview infrastructure changes |
| `make ls-destroy` | Destroy instance |

#### Lightsail Pricing

| Bundle | RAM | vCPU | SSD | Cost/Month |
|--------|-----|------|-----|------------|
| `nano_3_0` | 512MB | 1 | 20GB | $3.50 |
| `micro_3_0` | 1GB | 1 | 40GB | $5 |
| `small_3_0` | 2GB | 1 | 60GB | $10 |
| **`medium_3_0`** | **4GB** | **2** | **80GB** | **$20** (default) |
| `large_3_0` | 8GB | 2 | 160GB | $40 |
| `xlarge_3_0` | 16GB | 4 | 320GB | $80 |
| `2xlarge_3_0` | 32GB | 8 | 640GB | $160 |

Change bundle in `terraform/lightsail/terraform.tfvars`:
```hcl
bundle_id = "large_3_0"  # $40/mo — 8GB RAM, 2 vCPU
```

### 4. EKS (Production at Scale)

Managed Kubernetes for auto-scaling and high availability.

```bash
make quick-deploy   # All-in-one: Terraform + K8s deploy (~15 min)
```

| Command | Description |
|---------|-------------|
| `make deploy-init` | Initialize Terraform |
| `make deploy-plan` | Preview infrastructure changes |
| `make deploy-apply` | Create EKS cluster (~15 min) |
| `make deploy-destroy` | Destroy all AWS resources |
| `make k8s-apply` | Deploy OpenClaw to Kubernetes |
| `make k8s-status` | Show resource status |
| `make k8s-logs` | Tail pod logs |
| `make k8s-shell` | Shell into pod |
| `make k8s-secret` | Create K8s secret from `.env` |
| `make k8s-url` | Show dashboard URL |

---

## Configuration

### Environment Variables (`.env`)

```bash
# Gateway
OPENCLAW_GATEWAY_TOKEN=<auto-generated>
GATEWAY_PORT=18789

# API Keys (at least one required)
ANTHROPIC_API_KEY=
GEMINI_API_KEY=
OPENAI_API_KEY=
GROQ_API_KEY=
XAI_API_KEY=
MISTRAL_API_KEY=
OPENROUTER_API_KEY=

# Claude Code OAuth (alternative to API key)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Model
DEFAULT_MODEL=claude-sonnet-4-5-20250929
DEFAULT_PROVIDER=anthropic

# Security
EXEC_ASK=on
LOG_LEVEL=info
LOG_FORMAT=json
```

### OpenClaw Configuration (`openclaw.json`)

Optional local config file for gateway, agent defaults, channel integrations (Discord, Zalo), and plugin configuration. Sync to container with:

```bash
make sync-docker-config   # Docker
make deploy-ec2           # EC2 (auto-syncs)
make deploy-ls            # Lightsail (auto-syncs)
```

---

## Secure Access (Tunneling)

Modern browsers require HTTPS or localhost for the control UI. Two tunnel options:

### SSH Tunnel (Local Access)

```bash
make ec2-tunnel NAME=main   # EC2
make ls-tunnel NAME=main    # Lightsail
# Then access: http://localhost:18789
```

- Instant setup, no extra tools needed
- Access from your machine only
- Press Ctrl+C to close

### Cloudflare Tunnel (Public HTTPS)

```bash
make ec2-cloudflare-tunnel NAME=main   # EC2
make ls-cloudflare-tunnel NAME=main    # Lightsail
# Provides: https://random-name.trycloudflare.com
```

- Automatic HTTPS/SSL certificate
- Shareable URL for team access
- Works on mobile devices
- Installs `cloudflared` on the instance automatically

Auto-enable during setup:
```bash
make ec2-full-setup CLOUDFLARE=true CLAUDE_CODE_OAUTH_TOKEN=...
```

| Feature | SSH Tunnel | Cloudflare Tunnel |
|---------|-----------|-------------------|
| Setup | Instant | ~30 seconds |
| Access | localhost only | Public URL |
| HTTPS | No (localhost) | Yes (automatic) |
| Sharing | Not shareable | Shareable link |
| Mobile | No | Yes |
| Persistence | While connected | Until stopped |

---

## Multiple Instances

Deploy independent instances with the `NAME` parameter:

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... NAME=claude
make ec2-full-setup GEMINI_API_KEY=... NAME=gemini
make ec2-full-setup OPENAI_API_KEY=sk-... NAME=openai
```

Each gets its own EC2 instance, elastic IP, and configuration.

Manage specific instances:
```bash
make ec2-logs NAME=claude       # Logs for Claude instance
make ec2-shell NAME=gemini      # SSH to Gemini instance
make ec2-restart NAME=openai    # Restart OpenAI instance
make ec2-destroy NAME=claude    # Destroy Claude instance
```

---

## Cost Comparison

| Feature | EC2 | Lightsail | EKS |
|---------|-----|-----------|-----|
| Monthly cost | ~$30 variable | $20 fixed | $75+ |
| Setup time | ~3 min | ~2 min | ~15 min |
| Deploy time | ~30 sec | ~30 sec | ~5 min |
| Pricing | Per-hour | Predictable | Per-hour + cluster fee |
| Static IP | Elastic IP (free while attached) | Included | NLB hostname |
| Storage | Separate (gp3) | Included (80GB) | EBS volumes |
| Auto-scaling | Manual | No | Automatic |
| Best for | Most use cases | Fixed pricing | Production at scale |

---

## Troubleshooting

### SSH Key Issues

**Key already exists:**
```bash
# EC2
make ec2-delete-key && make ec2-create-key

# Lightsail
make ls-delete-key && make ls-create-key
```

**Permission denied:**
```bash
chmod 400 ~/.ssh/openclaw.pem   # EC2
chmod 400 ~/.ssh/openclaw-ls    # Lightsail
```

### Container Issues

**Container not starting:**
```bash
make ec2-shell               # SSH into instance
cd /home/ec2-user/openclaw
docker compose logs          # Check logs
docker compose ps            # Check status
```

**Dashboard not loading:**
```bash
# Verify container is running
make ec2-shell
docker compose ps    # Status should be "Up"

# Test locally on instance
curl http://localhost:18789
```

### Terraform Issues

**State locked:**
```bash
cd terraform/ec2    # or terraform/lightsail
terraform force-unlock <LOCK_ID>
```

**Region mismatch:**
Ensure the region in `terraform.tfvars` matches your AWS CLI config.

### Performance

**Upgrade EC2 instance:**
```bash
vim terraform/ec2/terraform.tfvars
# Change: instance_type = "t3.large"
cd terraform/ec2
terraform apply
```

**Upgrade Lightsail bundle:**
```bash
vim terraform/lightsail/terraform.tfvars
# Change: bundle_id = "large_3_0"
cd terraform/lightsail
terraform apply
```

---

## Advanced Topics

### Custom Domain

Point your DNS A record to the elastic/static IP:
```bash
make ec2-url   # Get the elastic IP
# In DNS: A record -> openclaw.yourdomain.com -> <ELASTIC_IP>
# Access: http://openclaw.yourdomain.com:18789
```

### Backup

**EC2 AMI:**
```bash
aws ec2 create-image \
  --instance-id <INSTANCE_ID> \
  --name "openclaw-backup-$(date +%Y%m%d)"
```

**Lightsail snapshot:**
```bash
aws lightsail create-instance-snapshot \
  --instance-name openclaw-main \
  --instance-snapshot-name "backup-$(date +%Y%m%d)"
```

### Update Workflow

```bash
make deploy-ec2   # EC2: pull latest image + restart (~30 sec)
make deploy-ls    # Lightsail: pull latest image + restart (~30 sec)
```
