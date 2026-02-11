# OpenClaw Deployment Pipeline

## Quick Start

```bash
make quick-docker
```

Auto-generates `.env` with a new token and starts the container. Pass API keys inline:

```bash
make quick-docker OPENAI_API_KEY=xxx
```

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
| `make approve` | Approve pending browser device for dashboard |

## AWS EKS Deployment

Deploy OpenClaw to a managed Kubernetes cluster on AWS.

### Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### 1. Configure Terraform

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your preferred region, instance type, etc.
```

### 2. Create EKS Cluster

```bash
make deploy-init     # Initialize Terraform
make deploy-plan     # Preview changes
make deploy-apply    # Create VPC + EKS cluster (~15 min)
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region ap-southeast-1 --name openclaw
```

### 4. Create Secrets

Option A — from `.env` file:
```bash
make setup-docker-env   # Generate .env if not exists
make k8s-secret         # Create K8s secret from .env
```

Option B — edit `k8s/secret.yaml` directly and apply:
```bash
kubectl apply -f k8s/secret.yaml
```

### 5. Deploy to Kubernetes

```bash
make k8s-apply
```

### 6. Access Dashboard

```bash
# Get the NLB endpoint
kubectl get svc openclaw -n openclaw

# Open: http://<NLB-HOSTNAME>:18789
```

### EKS Commands

| Command | Description |
|---------|-------------|
| `make deploy-init` | Initialize Terraform |
| `make deploy-plan` | Preview infrastructure changes |
| `make deploy-apply` | Create/update AWS infrastructure |
| `make deploy-destroy` | Destroy all AWS resources |
| `make k8s-apply` | Deploy OpenClaw to Kubernetes |
| `make k8s-status` | Show all resources in openclaw namespace |
| `make k8s-logs` | Tail pod logs |
| `make k8s-shell` | Shell into running pod |
| `make k8s-secret` | Create K8s secret from `.env` file |
