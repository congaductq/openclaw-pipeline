# Pipeline Server

The pipeline server is a Go HTTP API that orchestrates OpenClaw deployments. It provides endpoints to launch instances, approve devices, check status, and forward webhook events to the frontend.

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Go](https://go.dev/dl/) >= 1.23 (for building)

## Quick Start

### EC2 (Recommended)

```bash
make server-full-setup FRONTEND_URL=http://your-frontend:3000
```

This creates an SSH key, provisions an EC2 instance (t3.xlarge — 4 vCPU, 16GB RAM), installs tools, builds the Go server, and starts it as a systemd service.

### Lightsail (Alternative)

```bash
make server-ls-full-setup FRONTEND_URL=http://your-frontend:3000
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/launch` | Launch a new OpenClaw instance |
| `POST` | `/approve` | Approve pending browser device |
| `GET` | `/status` | List running deployments |
| `GET` | `/health` | Health check |
| `POST` | `/webhook/event` | Receive deployment events |
| `GET` | `/swagger` | Swagger UI |
| `GET` | `/swagger.json` | OpenAPI spec |

### Launch Instance

```bash
curl -X POST http://<SERVER_IP>:4000/launch \
  -H 'Content-Type: application/json' \
  -d '{"name":"main","claude_code_oauth_token":"sk-ant-oat01-...","cloudflare":true}'
```

**Parameters:**
- `name` — Deployment name (default: auto-increments)
- `token` — Gateway token (auto-generated if empty)
- `claude_code_oauth_token` — Claude OAuth token
- `cloudflare` — Enable Cloudflare tunnel (bool)

### Approve Device

```bash
curl -X POST http://<SERVER_IP>:4000/approve \
  -H 'Content-Type: application/json' \
  -d '{"name":"main"}'
```

### Check Status

```bash
curl http://<SERVER_IP>:4000/status
```

## Deployment - EC2 (Default)

### Step-by-Step

```bash
# 1. Create SSH key
make ec2-create-key

# 2. Create Terraform config
make ec2-config

# 3. Create EC2 instance (t3.xlarge — 4 vCPU, 16GB RAM)
make server-setup

# 4. Deploy pipeline server
make server-deploy FRONTEND_URL=http://your-frontend:3000
```

### Management

| Command | Description |
|---------|-------------|
| `make server-full-setup` | Complete setup from scratch |
| `make server-deploy` | Deploy/update server |
| `make server-logs` | Tail systemd logs |
| `make server-url` | Show API & Swagger URLs |
| `make server-destroy` | Destroy EC2 instance |

## Deployment - Lightsail (Alternative)

### Step-by-Step

```bash
# 1. Create SSH key
make ls-create-key

# 2. Create Terraform config
make ls-config

# 3. Create Lightsail instance ($80/mo, 16GB RAM, 4 vCPU)
make server-ls-setup

# 4. Deploy pipeline server
make server-ls-deploy FRONTEND_URL=http://your-frontend:3000
```

### Management

| Command | Description |
|---------|-------------|
| `make server-ls-full-setup` | Complete setup from scratch |
| `make server-ls-deploy` | Deploy/update server |
| `make server-ls-logs` | Tail systemd logs |
| `make server-ls-url` | Show API & Swagger URLs |
| `make server-ls-destroy` | Destroy Lightsail instance |

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | `4000` | API server port |
| `FRONTEND_URL` | `http://localhost:3000` | Frontend URL for webhook callbacks |
| `PIPELINE_DIR` | `/app/pipeline` | Path to openclaw-pipeline repo |
| `CLAUDE_CODE_OAUTH_TOKEN` | - | Default OAuth token for launches |

### Webhook Events

The server forwards events to `FRONTEND_URL/api/webhook/pipeline`. Event types:

| Event | Source | Description |
|-------|--------|-------------|
| `Launching` | Go server | Instance launch started |
| `Completed` | Go server | Launch completed |
| `Failed` | Go server | Launch failed |
| `CreatingKey` | Script | SSH key creation |
| `CreatingConfig` | Script | Terraform config |
| `CreatingEC2` | Script | Instance provisioning |
| `DeployingApp` | Script | App deployment |
| `PullingImage` | Script | Docker image pull |
| `StartingApp` | Script | Container start |
| `HealthCheck` | Script | Health verification |
| `CloudflareSetup` | Script | Tunnel setup |
| `AutoApproving` | Script | Device approval |
| `PairingRequired` | Script | Device pairing needed |
| `CloudflareReady` | Script | Tunnel URL ready |

## Architecture

```
Frontend <-> Pipeline Server (Go, :4000) <-> Makefile/Scripts <-> Terraform <-> AWS
                  |
            Webhook Events
```

The pipeline server runs `make ec2-full-setup` (or `make ls-full-setup`) asynchronously when a `/launch` request comes in, forwarding deployment progress events to the frontend via webhooks.

## Code Structure

```
server/
  main.go              # HTTP server setup, CORS middleware
  handler/
    handler.go         # Request handlers (Launch, Approve, Status, Health)
    swagger.go         # Swagger UI handler
  runner/
    pipeline.go        # Pipeline execution (async make commands)
  webhook/
    notifier.go        # Event forwarding to frontend
  Dockerfile           # Multi-stage build (Go -> Alpine)
  go.mod               # Go module definition
```

## Troubleshooting

**Server not starting:**
```bash
make server-logs                       # Check systemd logs
ssh -i ~/.ssh/openclaw.pem ec2-user@IP # SSH in to debug
sudo systemctl status pipeline-server  # Check service status
```

**Health check failing:**
```bash
curl http://SERVER_IP:4000/health
# Expected: {"status":"ok"}
```

**Webhook events not arriving:**
- Verify `FRONTEND_URL` is correct and reachable from server
- Check server logs for HTTP errors
- Ensure the frontend endpoint `/api/webhook/pipeline` exists
