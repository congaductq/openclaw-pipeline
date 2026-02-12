# OpenClaw EC2 Deployment

**Deploy OpenClaw to AWS EC2 in 3 minutes using only the command line.**

Fast, simple deployment using a single EC2 instance with Docker Compose. Perfect for development, demos, and small teams.

---

## Table of Contents

- [Quick Start](#-quick-start) (Most Important!)
- [Prerequisites](#-prerequisites)
- [Deployment Methods](#-deployment-methods)
- [Command Reference](#-command-reference)
- [Configuration](#-configuration)
- [Troubleshooting](#-troubleshooting)
- [Cost & Performance](#-cost--performance)
- [Advanced Topics](#-advanced-topics)

---

## 🚀 Quick Start

### One-Command Deploy (Easiest!)

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-YOUR_TOKEN_HERE
```

**Optional: Multiple deployments**
```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... NAME=claude
make ec2-full-setup GEMINI_API_KEY=... NAME=gemini
```

**That's it!** This single command:
1. Creates SSH key pair via AWS CLI
2. Configures Terraform
3. Launches EC2 instance (~2 min)
4. Auto-installs Docker
5. Deploys OpenClaw (~30 sec)
6. Shows your dashboard URL

**Total time**: ~3 minutes
**No web console needed!**

---

## ✅ Prerequisites

Before starting, ensure you have:

1. **AWS CLI configured**
   ```bash
   aws configure  # Enter your credentials
   aws sts get-caller-identity  # Verify it works
   ```

2. **Terraform installed**
   ```bash
   terraform version  # Should show v1.5+
   ```

That's it! No SSH keys or web console access needed.

---

## 📋 Deployment Methods

### Method 1: Fully Automated (Recommended)

**One command does everything:**

```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

**What it does:**
- [1/5] Creates SSH key `openclaw` in AWS
- [2/5] Saves private key to `~/.ssh/openclaw.pem`
- [3/5] Creates Terraform config
- [4/5] Launches EC2 instance (t3.small)
- [5/5] Deploys OpenClaw

**Output:**
```
================================================================
  ✓ Complete! OpenClaw is running on EC2
================================================================

🔗 Click to open (auto-login):
   http://54.123.45.67:18789#token=abc123...

📋 Manual access:
   URL:   http://54.123.45.67:18789
   Token: abc123...
```

**Important:** Modern browsers require HTTPS or localhost for the control UI. Choose one of two tunnel options:

**Option 1: SSH Tunnel (Local Access)**
```bash
make ec2-tunnel NAME=main
# Then access: http://localhost:18789
```

**Option 2: Cloudflare Tunnel (Public HTTPS - Recommended)**
```bash
make ec2-cloudflare-tunnel NAME=main
# Provides: https://random-name.trycloudflare.com
```

See [TUNNEL-OPTIONS.md](TUNNEL-OPTIONS.md) for detailed comparison.

---

### Method 2: Step-by-Step

If you prefer more control:

```bash
# Step 1: Create SSH key
make ec2-create-key

# Step 2: Create Terraform config
make ec2-config

# Step 3: Setup infrastructure
make ec2-setup

# Step 4: Deploy application
make deploy-ec2 CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...

# Step 5: Get URL
make ec2-url
```

---

### Method 3: Using Existing SSH Key

If you already have an AWS key pair:

```bash
# Skip ec2-create-key, just configure
make ec2-config

# Edit the config to use your existing key
vim terraform/ec2/terraform.tfvars
# Change: key_name = "your-existing-key"

# Deploy
make quick-ec2 CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

---

## 📖 Command Reference

### Setup Commands (One-Time)

| Command | Description | Time |
|---------|-------------|------|
| `make ec2-create-key` | Create SSH key pair via CLI | 5 sec |
| `make ec2-delete-key` | Delete SSH key pair | 5 sec |
| `make ec2-config` | Create terraform.tfvars | instant |
| `make ec2-init` | Initialize Terraform | 10 sec |
| `make ec2-setup` | Create EC2 instance | ~2 min |
| `make ec2-destroy` | Destroy EC2 instance | ~1 min |

### Deployment Commands

| Command | Description | Time |
|---------|-------------|------|
| `make deploy-ec2` | Deploy/update OpenClaw | ~30 sec |
| `make quick-ec2` | Setup + deploy (needs key) | ~3 min |
| `make ec2-full-setup` | Complete setup from scratch | ~3 min |

### Management Commands

| Command | Description |
|---------|-------------|
| `make ec2-tunnel` | Create SSH tunnel (local access) |
| `make ec2-cloudflare-tunnel` | Setup Cloudflare Tunnel (public HTTPS) |
| `make ec2-cloudflare-stop` | Stop Cloudflare Tunnel |
| `make ec2-logs` | Tail container logs |
| `make ec2-shell` | SSH to EC2 instance |
| `make ec2-restart` | Restart containers |
| `make ec2-url` | Show dashboard URL |

### Planning Commands

| Command | Description |
|---------|-------------|
| `make ec2-plan` | Preview infrastructure changes |

---

## ⚙️ Configuration

### Default Configuration

The default setup creates:
- **Instance**: t3.small (2 vCPU, 2GB RAM)
- **Region**: us-west-2
- **Storage**: 20GB gp3
- **Ports**: 22 (SSH), 18789 (OpenClaw)
- **Static IP**: Yes (Elastic IP)

### Customizing Configuration

Edit `terraform/ec2/terraform.tfvars`:

```hcl
# Change instance size
instance_type = "t3.medium"  # 2 vCPU, 4GB RAM

# Change region
aws_region = "us-east-1"

# Increase storage
volume_size = 50  # GB

# Use different key
key_name = "my-custom-key"

# Disable Elastic IP (dynamic IP)
use_elastic_ip = false
```

Apply changes:
```bash
cd terraform/ec2
terraform apply
```

---

## 🔧 Troubleshooting

### SSH Key Issues

**Error: Key pair already exists**
```bash
# Option 1: Delete and recreate
make ec2-delete-key
make ec2-create-key

# Option 2: Use existing key
# Edit terraform/ec2/terraform.tfvars
# Set: key_name = "your-existing-key"
```

**Error: Permission denied (publickey)**
```bash
# Check key permissions
ls -la ~/.ssh/openclaw.pem  # Should be -r-------- (400)

# Fix permissions
chmod 400 ~/.ssh/openclaw.pem
```

### Deployment Issues

**Error: Container not starting**
```bash
# SSH to EC2 and check logs
make ec2-shell
cd /home/ec2-user/openclaw
docker compose logs
docker compose ps
```

**Error: Can't connect to dashboard**
```bash
# 1. Check if container is running
make ec2-shell
docker compose ps

# 2. Check if port 18789 is open
# It should be open by default in security group

# 3. Get the correct URL
make ec2-url
```

**Error: Terraform state locked**
```bash
# Force unlock (use with caution)
cd terraform/ec2
terraform force-unlock <LOCK_ID>
```

### Connection Issues

**Dashboard not loading**
```bash
# 1. Verify EC2 is running
make ec2-shell  # Should connect successfully

# 2. Check container health
ssh -i ~/.ssh/openclaw.pem ec2-user@<IP>
docker compose ps  # Status should be "Up"

# 3. Test local access on EC2
ssh -i ~/.ssh/openclaw.pem ec2-user@<IP>
curl http://localhost:18789  # Should return HTML
```

**Slow performance**
```bash
# Upgrade instance size
vim terraform/ec2/terraform.tfvars
# Change: instance_type = "t3.medium"
cd terraform/ec2
terraform apply
```

---

## 💰 Cost & Performance

### Monthly Cost Estimates

| Instance Type | vCPU | RAM | Storage | Cost/Month |
|---------------|------|-----|---------|------------|
| t3.micro | 2 | 1GB | 20GB | ~$8 |
| **t3.small** ⭐ | 2 | 2GB | 20GB | **~$15** |
| t3.medium | 2 | 4GB | 20GB | ~$30 |
| t3.large | 2 | 8GB | 20GB | ~$60 |

**Additional costs:**
- Elastic IP: $0 (while attached to running instance)
- Data transfer: ~$0.09/GB outbound (first 100GB/month free)

### Performance

- **Setup time**: 2-3 minutes (first time)
- **Deploy time**: 30 seconds (updates)
- **Restart time**: 5 seconds
- **Boot time**: ~60 seconds (cold start)

**Recommended for:**
- ✅ Development
- ✅ Demos
- ✅ Small teams (1-10 users)
- ✅ Testing

**Not recommended for:**
- ❌ High-traffic production
- ❌ Auto-scaling requirements
- ❌ Multi-region deployments

For production at scale, consider EKS deployment instead.

---

## 🌐 Advanced Topics

### Using a Custom Domain

1. **Point DNS to Elastic IP:**
   ```bash
   # Get your Elastic IP
   make ec2-url

   # In your DNS provider (e.g., Cloudflare):
   # A Record: openclaw.yourdomain.com → <ELASTIC_IP>
   ```

2. **Access via domain:**
   ```
   http://openclaw.yourdomain.com:18789
   ```

3. **Optional: Add HTTPS** (requires nginx + Let's Encrypt)

### Changing Ports

1. **Update .env:**
   ```bash
   vim .env
   # Change: GATEWAY_PORT=8080
   ```

2. **Update Terraform:**
   ```bash
   vim terraform/ec2/terraform.tfvars
   # Change: gateway_port = 8080
   ```

3. **Apply changes:**
   ```bash
   cd terraform/ec2
   terraform apply
   make deploy-ec2
   ```

### Using Subdomains

Same as custom domain - just point the subdomain to your Elastic IP:
```
A Record: api.openclaw.yourdomain.com → <ELASTIC_IP>
```

### Backup & Restore

**Backup volumes:**
```bash
# Create AMI snapshot
aws ec2 create-image \
  --instance-id <INSTANCE_ID> \
  --name "openclaw-backup-$(date +%Y%m%d)"
```

**Restore from snapshot:**
```bash
# Launch new instance from AMI in AWS Console
# Or update terraform/ec2/main.tf to use the AMI
```

### Auto-Start on Reboot

Docker Compose is configured to restart on boot automatically:
```yaml
restart: unless-stopped
```

### Monitoring

**View logs:**
```bash
make ec2-logs
```

**Monitor resources:**
```bash
make ec2-shell
docker stats
htop
```

**CloudWatch metrics:**
- AWS Console → CloudWatch → EC2 Metrics
- Monitor: CPU, Network, Disk

### Scaling

**Vertical scaling (more resources):**
```bash
# Edit terraform.tfvars
instance_type = "t3.medium"  # or t3.large

# Apply
cd terraform/ec2
terraform apply
```

**Horizontal scaling:**
- Use EKS deployment instead
- Or manually deploy multiple EC2 instances with load balancer

### Multiple Deployments (Different AI Providers)

Deploy multiple independent OpenClaw instances for different AI providers using the `NAME` parameter:

**Deploy for Claude:**
```bash
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-... NAME=claude
```

**Deploy for Gemini:**
```bash
make ec2-full-setup GEMINI_API_KEY=... NAME=gemini
```

**Deploy for OpenAI:**
```bash
make ec2-full-setup OPENAI_API_KEY=sk-... NAME=openai
```

Each deployment gets:
- Unique EC2 instance: `openclaw-claude`, `openclaw-gemini`, `openclaw-openai`
- Unique security group
- Unique Elastic IP
- Independent configuration

**No file editing needed!** The `NAME` parameter automatically creates separate deployments.

**Manage specific deployments:**
```bash
# View logs for specific deployment
make ec2-logs NAME=claude

# SSH to specific deployment
make ec2-shell NAME=gemini

# Restart specific deployment
make ec2-restart NAME=openai

# Destroy specific deployment
make ec2-destroy NAME=claude
```

**List all deployments:**
```bash
aws ec2 describe-instances \
  --filters "Name=tag:ManagedBy,Values=terraform" \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,State.Name]' \
  --output table
```

---

## 🔄 Update Workflow

### Regular Updates

```bash
# Update OpenClaw (30 seconds)
make deploy-ec2
```

### Infrastructure Updates

```bash
# Preview changes
make ec2-plan

# Apply changes
cd terraform/ec2
terraform apply
```

### Full Rebuild

```bash
# Destroy and recreate
make ec2-destroy
make ec2-full-setup CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

---

## 🆚 EC2 vs EKS Comparison

| Feature | EC2 (This Guide) | EKS |
|---------|-----------------|-----|
| **Setup Time** | 2-3 min | 15-20 min |
| **Deploy Time** | 30 sec | 5+ min |
| **Monthly Cost** | $15-20 | $75+ |
| **Complexity** | Simple | Complex |
| **Auto-scaling** | Manual | Automatic |
| **High Availability** | Single instance | Multi-AZ |
| **Maintenance** | Low | Medium |
| **Best For** | Dev/demos/small teams | Production at scale |

**Recommendation**: Start with EC2, migrate to EKS when you need:
- Auto-scaling
- High availability
- Multi-region deployment
- Team size > 10

---

## 📚 Additional Resources

- **Main README**: [README.md](README.md)
- **Terraform configs**: `terraform/ec2/`
- **Deployment script**: `scripts/deploy-ec2.sh`
- **Docker Compose**: `docker-compose.yml`

---

## 🆘 Getting Help

**Check logs:**
```bash
make ec2-logs
```

**SSH for debugging:**
```bash
make ec2-shell
```

**Common issues:**
- Port 18789 blocked? Check security group
- Container not starting? Check logs with `make ec2-logs`
- Can't SSH? Verify key permissions: `chmod 400 ~/.ssh/openclaw.pem`

**Still stuck?**
- Check the [Troubleshooting](#-troubleshooting) section above
- Review deployment logs
- Verify AWS credentials: `aws sts get-caller-identity`

---

## ✨ Next Steps

After successful deployment:

1. **Access dashboard** - Click the URL from deployment output
2. **Approve devices** - Use the gateway token to authenticate
3. **Deploy agents** - Start using OpenClaw for your workflows
4. **Set up monitoring** - Enable CloudWatch if needed
5. **Configure backups** - Create AMI snapshots periodically

For production deployments, consider:
- Setting up HTTPS with nginx + Let's Encrypt
- Using custom domain with DNS
- Enabling CloudWatch monitoring
- Regular backups with AMI snapshots
- Migrating to EKS when scaling needs increase

---

**Happy deploying!** 🚀
