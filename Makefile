.PHONY: help install-docker onboard-docker docker-build docker-shell docker-clean clean update-docker logs-docker test-docker setup-docker-env reset-env clone-config sync-docker-config quick-docker start open approve deploy-init deploy-plan deploy-apply deploy-destroy k8s-apply k8s-status k8s-logs k8s-shell k8s-secret quick-deploy ls-create-key ls-delete-key ls-config ls-init ls-plan ls-setup ls-destroy deploy-ls ls-full-setup quick-ls ls-logs ls-shell ls-tunnel ls-url ls-restart ls-approve ls-cloudflare-tunnel ls-cloudflare-stop server-ls-setup server-ls-deploy server-ls-full-setup server-ls-logs server-ls-url server-ls-destroy

# Variables — pass via CLI: make quick-docker OPENAI_API_KEY=xxx
GATEWAY_PORT ?= 18789
SETUP_ARGS :=
ifdef TOKEN
  export OPENCLAW_GATEWAY_TOKEN := $(TOKEN)
  SETUP_ARGS += --token $(TOKEN)
endif
ifdef FROM_CONFIG
  SETUP_ARGS += --from-config
endif

# Export API keys so setup-docker-env.sh receives them
ifdef ANTHROPIC_API_KEY
  export ANTHROPIC_API_KEY
endif
ifdef GEMINI_API_KEY
  export GEMINI_API_KEY
endif
ifdef OPENAI_API_KEY
  export OPENAI_API_KEY
endif
ifdef GROQ_API_KEY
  export GROQ_API_KEY
endif
ifdef XAI_API_KEY
  export XAI_API_KEY
endif
ifdef MISTRAL_API_KEY
  export MISTRAL_API_KEY
endif
ifdef OPENROUTER_API_KEY
  export OPENROUTER_API_KEY
endif
ifdef CLAUDE_CODE_OAUTH_TOKEN
  export CLAUDE_CODE_OAUTH_TOKEN
endif

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install-docker: ## Install OpenClaw via Docker
	@echo "Installing via Docker..."
	docker-compose --env-file .env up -d
	@echo "Run 'make onboard-docker' to configure"

onboard-docker: ## Run onboarding in Docker
	docker exec -it openclaw node /app/openclaw.mjs onboard --install-daemon

update-docker: ## Update Docker image
	docker-compose pull
	docker-compose up -d
	@echo "Docker image updated"

logs-docker: ## Show Docker logs
	docker logs -f openclaw

test-docker: ## Test Docker deployment
	@echo "Testing Docker deployment..."
	@echo ""
	@echo "Checking if container is running..."
	@docker ps | grep openclaw >/dev/null || (echo "Container not running"; exit 1)
	@echo "  Container is running"
	@echo ""
	@echo "Checking gateway token..."
	@TOKEN=$$(docker exec openclaw sh -c 'echo $$OPENCLAW_GATEWAY_TOKEN'); \
	if [ -z "$$TOKEN" ]; then \
		echo "  No gateway token found"; exit 1; \
	fi; \
	echo "  Gateway token is set: $${TOKEN:0:16}..."
	@echo ""
	@echo "Checking health status..."
	@docker exec openclaw node /app/openclaw.mjs gateway health --url ws://127.0.0.1:18789 >/dev/null 2>&1 && echo "  Gateway is healthy" || echo "  Gateway still warming up"
	@echo ""
	@echo "Docker deployment test passed!"
	@echo ""
	@echo "Dashboard: http://localhost:$(GATEWAY_PORT)"

docker-build: ## Build Docker image
	docker build -t openclaw:local .

docker-shell: ## Open shell in container
	docker exec -it openclaw /bin/sh

verify-auth: ## Verify auth-profiles.json in container
	@echo "Checking auth-profiles.json in container..."
	@docker exec openclaw test -f /home/node/.openclaw/agents/main/agent/auth-profiles.json && \
		echo "✓ auth-profiles.json exists" || \
		echo "✗ auth-profiles.json NOT found"
	@echo ""
	@echo "Content:"
	@docker exec openclaw cat /home/node/.openclaw/agents/main/agent/auth-profiles.json 2>/dev/null | jq '.' || \
		echo "Cannot read file (may not exist or container not running)"

check-model: ## Show current model configuration
	@echo "Model Configuration:"
	@echo "==================="
	@if [ -f .env ]; then \
		MODEL=$$(grep '^DEFAULT_MODEL=' .env 2>/dev/null | cut -d= -f2); \
		PROVIDER=$$(grep '^DEFAULT_PROVIDER=' .env 2>/dev/null | cut -d= -f2); \
		if [ -n "$$MODEL" ]; then \
			echo "  Current (.env):  $$MODEL"; \
		fi; \
		if [ -n "$$PROVIDER" ]; then \
			echo "  Provider:        $$PROVIDER"; \
		fi; \
	else \
		echo "  No .env file found"; \
	fi
	@echo "  Default (code):  claude-sonnet-4-5-20250929 (Sonnet 4.5)"
	@echo ""
	@echo "Available Claude Models:"
	@echo "  - claude-sonnet-4-5-20250929 (Sonnet 4.5) [Recommended]"
	@echo "  - claude-opus-4-6            (Opus 4.6)   [Most capable]"
	@echo "  - claude-haiku-4-5-20251001  (Haiku 4.5)  [Fastest]"
	@echo ""
	@if docker exec openclaw true 2>/dev/null; then \
		echo "Container model:"; \
		docker exec openclaw sh -c 'echo "  $$DEFAULT_MODEL"' 2>/dev/null || echo "  (not set)"; \
	else \
		echo "Container not running"; \
	fi

docker-clean: ## Clean Docker resources
	docker-compose down -v
	docker image prune -f

docker-clean-all: ## Clean ALL Docker except OpenClaw (containers, images, volumes, networks)
	@echo "⚠️  WARNING: This will remove ALL Docker resources except OpenClaw!"
	@echo ""
	@echo "What will be cleaned:"
	@echo "  - All stopped containers (except openclaw)"
	@echo "  - All unused images"
	@echo "  - All volumes (except openclaw-config, openclaw-workspace)"
	@echo "  - All unused networks"
	@echo ""
	@echo "Starting cleanup in 3 seconds... (Ctrl+C to cancel)"
	@sleep 3
	@echo ""
	@echo "[1/4] Removing non-OpenClaw containers..."
	@for container in $$(docker ps -aq 2>/dev/null); do \
		name=$$(docker inspect --format='{{.Name}}' $$container 2>/dev/null | sed 's/^\///'); \
		if [ "$$name" != "openclaw" ]; then \
			echo "  Removing: $$name"; \
			docker rm -f $$container 2>/dev/null || true; \
		fi; \
	done
	@echo "[2/4] Removing unused images..."
	@docker image prune -af 2>/dev/null || true
	@echo "[3/4] Removing non-OpenClaw volumes..."
	@for vol in $$(docker volume ls -q 2>/dev/null); do \
		case "$$vol" in \
			openclaw-config|openclaw-workspace|*openclaw*) \
				echo "  Preserving: $$vol" ;; \
			*) \
				echo "  Removing: $$vol"; \
				docker volume rm $$vol 2>/dev/null || true ;; \
		esac; \
	done
	@echo "[4/4] Removing unused networks..."
	@docker network prune -f 2>/dev/null || true
	@echo ""
	@echo "✓ Cleanup complete!"
	@echo ""
	@echo "OpenClaw Status:"
	@docker ps -a --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Container not found"
	@echo ""
	@echo "OpenClaw Volumes:"
	@docker volume ls --filter "name=openclaw" --format "table {{.Name}}\t{{.Driver}}" 2>/dev/null || echo "  No volumes found"

clean: ## Full reset (containers, volumes, .env, temp files)
	@docker-compose down -v 2>/dev/null || true
	@rm -f .env
	@rm -f /tmp/openclaw-docker.json /tmp/auth-profiles.json 2>/dev/null || true
	@rm -rf user-profiles/ auth-profiles.json 2>/dev/null || true
	@echo "Cleaned: containers, volumes, auth-profiles, .env, temp files"
	@echo "Run 'make quick-docker CLAUDE_CODE_OAUTH_TOKEN=xxx' to start fresh"

setup-docker-env: ## Generate .env (skips if exists; TOKEN=xxx ANTHROPIC_API_KEY=sk-xxx)
	@if [ -f .env ]; then \
		echo ".env already exists, skipping (run 'make reset-env' to regenerate)"; \
	else \
		chmod +x scripts/setup-docker-env.sh; \
		./scripts/setup-docker-env.sh $(SETUP_ARGS); \
	fi

reset-env: ## Force regenerate .env (TOKEN=xxx ANTHROPIC_API_KEY=sk-xxx)
	@chmod +x scripts/setup-docker-env.sh
	@./scripts/setup-docker-env.sh $(SETUP_ARGS)

clone-config: ## Generate .env from ./openclaw.json (explicit opt-in)
	@chmod +x scripts/setup-docker-env.sh
	@./scripts/setup-docker-env.sh --from-config $(SETUP_ARGS)

sync-docker-config: ## Sync ./openclaw.json into running Docker container
	@if [ -f openclaw.json ]; then \
		echo "Syncing openclaw.json into Docker container..."; \
		docker exec -u root openclaw mkdir -p /home/node/.openclaw; \
		jq '.gateway.bind = "lan" | .agents.defaults.workspace = "/home/node/openclaw/workspace"' openclaw.json > /tmp/openclaw-docker.json; \
		docker cp /tmp/openclaw-docker.json openclaw:/home/node/.openclaw/openclaw.json; \
		rm -f /tmp/openclaw-docker.json; \
		docker exec -u root openclaw chown -R node:node /home/node/.openclaw /home/node/openclaw; \
		echo "Configuration synced to Docker container"; \
	else \
		echo "No openclaw.json found in project root"; \
	fi

approve: ## Approve pending browser device for dashboard access
	@TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$TOKEN" ]; then \
		echo "No token found in .env"; exit 1; \
	fi; \
	REQ=$$(docker exec openclaw node /app/openclaw.mjs devices list --url ws://127.0.0.1:18789 --token $$TOKEN 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1); \
	if [ -z "$$REQ" ]; then \
		echo "No pending device requests"; \
	else \
		docker exec openclaw node /app/openclaw.mjs devices approve $$REQ --url ws://127.0.0.1:18789 --token $$TOKEN; \
		echo "Device approved - refresh dashboard"; \
	fi

open: ## Open dashboard in browser (auto-authenticates)
	@TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$TOKEN" ]; then \
		echo "No gateway token found in .env"; exit 1; \
	fi; \
	URL="http://localhost:$(GATEWAY_PORT)#token=$$TOKEN"; \
	echo "Opening dashboard..."; \
	open "$$URL" 2>/dev/null || xdg-open "$$URL" 2>/dev/null || echo "$$URL"

start: install-docker ## Start Docker (uses existing .env)
	@echo ""
	@echo "[1/5] Waiting for container..."
	@for i in 1 2 3 4 5; do \
		docker exec openclaw true >/dev/null 2>&1 && break; \
		sleep 2; \
	done
	@echo "[2/5] Syncing config..."
	@docker stop openclaw >/dev/null 2>&1
	@if [ -f openclaw.json ]; then \
		echo "  Found openclaw.json — syncing with Docker overrides..."; \
		TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
		jq --arg token "$$TOKEN" '.gateway.bind = "lan" | .gateway.port = 18789 | .gateway.auth.mode = "token" | .gateway.auth.token = $$token | .agents.defaults.workspace = "/home/node/openclaw/workspace" | del(.meta, .wizard)' openclaw.json > /tmp/openclaw-docker.json; \
	else \
		echo "  No openclaw.json — using minimal config..."; \
		echo '{"gateway":{"bind":"lan","port":18789}}' > /tmp/openclaw-docker.json; \
	fi
	@docker cp /tmp/openclaw-docker.json openclaw:/home/node/.openclaw/openclaw.json
	@rm -f /tmp/openclaw-docker.json
	@OAUTH=$$(grep '^CLAUDE_CODE_OAUTH_TOKEN=.' .env 2>/dev/null | cut -d= -f2); \
	if [ -n "$$OAUTH" ]; then \
		docker start openclaw >/dev/null 2>&1; sleep 2; \
		docker exec -u root openclaw mkdir -p /home/node/.openclaw/agents/main/agent; \
		printf '{"version":1,"profiles":{"anthropic:default":{"type":"api_key","provider":"anthropic","key":"%s"}},"lastGood":{"anthropic":"anthropic:default"}}' "$$OAUTH" > /tmp/auth-profiles.json; \
		docker cp /tmp/auth-profiles.json openclaw:/home/node/.openclaw/agents/main/agent/auth-profiles.json; \
		rm -f /tmp/auth-profiles.json; \
		docker restart openclaw >/dev/null 2>&1; \
	else \
		docker start openclaw >/dev/null 2>&1; \
	fi
	@sleep 2
	@docker exec -u root openclaw chown -R node:node /home/node/.openclaw /home/node/openclaw 2>/dev/null || true
	@echo "[3/5] Waiting for gateway to be healthy..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		curl -s -o /dev/null -w '' http://localhost:$(GATEWAY_PORT)/ 2>/dev/null && break; \
		echo "  attempt $$i - not ready, retrying..."; \
		sleep 3; \
	done
	@curl -s -o /dev/null http://localhost:$(GATEWAY_PORT)/ 2>/dev/null || \
		(echo "Gateway failed to start. Check: make logs-docker"; exit 1)
	@echo "  Gateway is healthy!"
	@echo "[4/5] Opening dashboard..."
	@$(MAKE) open
	@echo "[5/5] Approving browser device..."
	@sleep 5
	@$(MAKE) approve 2>/dev/null || true
	@echo ""
	@PROVIDER=""; \
	if grep -q '^CLAUDE_CODE_OAUTH_TOKEN=.' .env 2>/dev/null; then PROVIDER="Claude AI (OAuth)"; \
	elif grep -q '^ANTHROPIC_API_KEY=.' .env 2>/dev/null; then PROVIDER="Claude AI"; \
	elif grep -q '^GEMINI_API_KEY=.' .env 2>/dev/null; then PROVIDER="Gemini AI"; \
	elif grep -q '^OPENAI_API_KEY=.' .env 2>/dev/null; then PROVIDER="OpenAI"; \
	elif grep -q '^GROQ_API_KEY=.' .env 2>/dev/null; then PROVIDER="Groq AI"; \
	elif grep -q '^XAI_API_KEY=.' .env 2>/dev/null; then PROVIDER="xAI (Grok)"; \
	elif grep -q '^MISTRAL_API_KEY=.' .env 2>/dev/null; then PROVIDER="Mistral AI"; \
	elif grep -q '^OPENROUTER_API_KEY=.' .env 2>/dev/null; then PROVIDER="OpenRouter"; \
	fi; \
	if [ -n "$$PROVIDER" ]; then \
		echo "OpenClaw is running with $$PROVIDER! Dashboard: http://localhost:$(GATEWAY_PORT)"; \
	else \
		echo "OpenClaw is running! Dashboard: http://localhost:$(GATEWAY_PORT)"; \
	fi
	@if grep -q '^CLAUDE_CODE_OAUTH_TOKEN=.' .env 2>/dev/null; then \
		echo ""; \
		echo "Auth Profile Status:"; \
		docker exec openclaw test -f /home/node/.openclaw/agents/main/agent/auth-profiles.json 2>/dev/null && \
			echo "  ✓ Claude OAuth auth-profiles.json configured" || \
			echo "  ✗ auth-profiles.json not found (check logs)"; \
	fi

quick-docker: setup-docker-env start ## First-time setup + start

# ── EC2 Deployment (Fast & Simple) ──────────────────────────────

# AWS region (must match terraform/ec2/variables.tf default)
AWS_REGION ?= us-west-2

# Deployment name for multi-instance support (default: main)
# Support both NAME=foo and name=foo (case-insensitive)
ifdef name
NAME := $(name)
endif
NAME ?= main
TF_STATE := terraform-$(NAME).tfstate

# Cloudflare tunnel flag (CLOUDFLARE=true to auto-enable)
ifdef cloudflare
CLOUDFLARE := $(cloudflare)
endif
CLOUDFLARE ?= false

ec2-create-key: ## Create SSH key pair via CLI (one-time)
	@echo "Creating SSH key pair 'openclaw' in AWS ($(AWS_REGION))..."
	@mkdir -p ~/.ssh
	@if [ -f ~/.ssh/openclaw.pem ] && aws ec2 describe-key-pairs --key-names openclaw --region $(AWS_REGION) >/dev/null 2>&1; then \
		echo "SSH key already exists — skipping"; \
	else \
		chmod 644 ~/.ssh/openclaw.pem 2>/dev/null || true; \
		aws ec2 create-key-pair \
			--key-name openclaw \
			--region $(AWS_REGION) \
			--query 'KeyMaterial' \
			--output text > ~/.ssh/openclaw.pem 2>/dev/null && \
			chmod 400 ~/.ssh/openclaw.pem && \
			echo "SSH key created: ~/.ssh/openclaw.pem" || \
			(echo "Key pair 'openclaw' already exists in AWS or error occurred"; \
			 echo "  1. Use existing key (if you have ~/.ssh/openclaw.pem)"; \
			 echo "  2. Delete and recreate: make ec2-delete-key && make ec2-create-key"); \
	fi

ec2-delete-key: ## Delete SSH key pair
	@echo "Deleting SSH key pair 'openclaw' from AWS ($(AWS_REGION))..."
	@aws ec2 delete-key-pair --key-name openclaw --region $(AWS_REGION) 2>/dev/null || echo "Key pair not found in AWS"
	@rm -f ~/.ssh/openclaw.pem
	@echo "✓ Key pair deleted from AWS and local file removed"

ec2-config: ## Create terraform.tfvars for EC2
	@if [ ! -f terraform/ec2/terraform.tfvars ]; then \
		echo "Creating terraform/ec2/terraform.tfvars..."; \
		cp terraform/ec2/terraform.tfvars.example terraform/ec2/terraform.tfvars; \
		echo "✓ Config file created: terraform/ec2/terraform.tfvars"; \
	else \
		echo "terraform.tfvars already exists"; \
		CURRENT_SIZE=$$(grep '^volume_size' terraform/ec2/terraform.tfvars | sed 's/.*=[[:space:]]*//' | grep -oE '^[0-9]+'); \
		if [ -n "$$CURRENT_SIZE" ] && [ "$$CURRENT_SIZE" -lt 30 ]; then \
			echo "⚠️  Warning: volume_size = $$CURRENT_SIZE is too small (minimum 30GB)"; \
			echo "Updating volume_size to 30GB..."; \
			sed -i.bak 's/^volume_size[[:space:]]*=.*/volume_size     = 30  # Minimum 30GB for Amazon Linux 2023/' terraform/ec2/terraform.tfvars; \
			rm -f terraform/ec2/terraform.tfvars.bak; \
			echo "✓ Updated volume_size to 30GB"; \
		fi; \
	fi

ec2-init: ## Initialize Terraform for EC2
	terraform -chdir=terraform/ec2 init

ec2-plan: ## Preview EC2 infrastructure changes
	@echo "Planning deployment: $(NAME)"
	terraform -chdir=terraform/ec2 plan -state=$(TF_STATE) -var="deployment_name=$(NAME)"

ec2-setup: ec2-init ## Create EC2 instance (one-time, ~2 min)
	@echo "Creating EC2 instance: openclaw-$(NAME)"
	terraform -chdir=terraform/ec2 apply -auto-approve -state=$(TF_STATE) -var="deployment_name=$(NAME)"
	@echo ""
	@echo "================================================================"
	@terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '"  SSH: \(.ssh_command.value)"'
	@terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '"  URL: \(.dashboard_url.value)"'
	@echo "================================================================"
	@echo ""
	@echo "Waiting 60s for instance to boot and install Docker..."
	@sleep 60
	@echo "Instance ready! Deploy with: make deploy-ec2 NAME=$(NAME)"

deploy-ec2: setup-docker-env ## Deploy OpenClaw to EC2 (~30 sec)
	@chmod +x scripts/deploy-ec2.sh scripts/setup-cloudflare-tunnel.sh scripts/ec2-approve.sh 2>/dev/null || true
	@TF_STATE=$(TF_STATE) DEPLOY_NAME=$(NAME) SETUP_CLOUDFLARE=$(CLOUDFLARE) ./scripts/deploy-ec2.sh

ec2-logs: ## Tail OpenClaw logs on EC2
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP \
		"cd /home/ec2-user/openclaw && docker compose logs -f"

ec2-shell: ## SSH into EC2 instance
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	echo "Connecting to openclaw-$(NAME) ($$EC2_IP)..."; \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP

ec2-tunnel: ## Create SSH tunnel for secure localhost access
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	echo "Creating SSH tunnel to openclaw-$(NAME)..."; \
	echo ""; \
	echo "🔗 Access via localhost:"; \
	echo "   http://localhost:18789#token=$$TOKEN"; \
	echo ""; \
	echo "Press Ctrl+C to close tunnel"; \
	echo ""; \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no -L 18789:localhost:18789 -N ec2-user@$$EC2_IP

ec2-approve: ## Approve pending browser device on EC2 (run after opening chat URL)
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$EC2_IP" ]; then \
		echo "Error: No EC2 instance found for NAME=$(NAME)"; \
		exit 1; \
	fi; \
	chmod +x scripts/ec2-approve.sh; \
	./scripts/ec2-approve.sh "$$EC2_IP" "$$SSH_KEY" "$$TOKEN"

ec2-cloudflare-tunnel: ## Setup Cloudflare Tunnel for HTTPS access (no domain needed)
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	if [ -z "$$EC2_IP" ]; then \
		echo "Error: No EC2 instance found for NAME=$(NAME)"; \
		echo ""; \
		echo "Deploy an instance first:"; \
		echo "  make ec2-full-setup NAME=$(NAME) CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-..."; \
		exit 1; \
	fi; \
	chmod +x scripts/setup-cloudflare-tunnel.sh; \
	./scripts/setup-cloudflare-tunnel.sh "$$EC2_IP" "$$SSH_KEY"

ec2-cloudflare-stop: ## Stop Cloudflare Tunnel
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	chmod +x scripts/stop-cloudflare-tunnel.sh; \
	./scripts/stop-cloudflare-tunnel.sh "$$EC2_IP" "$$SSH_KEY"

ec2-restart: ## Restart OpenClaw on EC2
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP \
		"cd /home/ec2-user/openclaw && docker compose restart"

ec2-url: ## Show EC2 dashboard URL and SSH info
	@echo "OpenClaw EC2 Instance: openclaw-$(NAME)"
	@echo "========================================"
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=$(TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	echo ""; \
	echo "💬 Chat Interface (works via HTTP):"; \
	echo "   http://$$EC2_IP:18789/chat?session=main"; \
	echo ""; \
	echo "🎛️  Control UI (requires tunnel):"; \
	echo "   Run: make ec2-tunnel NAME=$(NAME)"; \
	echo "   Then: http://localhost:18789"; \
	echo ""; \
	echo "💻 SSH Access:"; \
	echo "   ssh -i $$SSH_KEY ec2-user@$$EC2_IP"; \
	echo ""; \
	echo "📋 Quick Commands:"; \
	echo "   make ec2-logs NAME=$(NAME)     # Tail logs"; \
	echo "   make ec2-shell NAME=$(NAME)    # SSH session"; \
	echo "   make ec2-tunnel NAME=$(NAME)   # Tunnel for control UI"
	@echo ""

ec2-destroy: ## Destroy EC2 instance
	@echo "Destroying deployment: $(NAME)"
	terraform -chdir=terraform/ec2 destroy -auto-approve -state=$(TF_STATE) -var="deployment_name=$(NAME)"

ec2-full-setup: ## Complete EC2 setup from scratch (key + config + instance + deploy + optional CLOUDFLARE=true)
	@echo "================================================================"
	@echo "  OpenClaw EC2 Full Setup: openclaw-$(NAME)"
	@echo "================================================================"
	@echo ""
	@echo "[1/4] Creating SSH key pair..."
	@./scripts/webhook-notify.sh creating_key "creating SSH key pair" $(NAME) 2>/dev/null || true
	@$(MAKE) ec2-create-key
	@echo ""
	@echo "[2/4] Creating Terraform config..."
	@./scripts/webhook-notify.sh creating_config "creating Terraform config" $(NAME) 2>/dev/null || true
	@$(MAKE) ec2-config
	@echo ""
	@echo "[3/4] Setting up EC2 instance..."
	@./scripts/webhook-notify.sh creating_ec2 "creating EC2 instance (~2 min)" $(NAME) 2>/dev/null || true
	@$(MAKE) ec2-setup NAME=$(NAME)
	@echo ""
	@echo "[4/4] Deploying OpenClaw (+ Cloudflare tunnel if CLOUDFLARE=true)..."
	@$(MAKE) deploy-ec2 NAME=$(NAME) CLOUDFLARE=$(CLOUDFLARE)
	@echo "================================================================"
	@echo "  Complete! openclaw-$(NAME) is running on EC2"
	@echo "================================================================"

quick-ec2: ## One-command EC2 setup + deploy (requires existing SSH key)
	@$(MAKE) ec2-setup NAME=$(NAME)
	@$(MAKE) deploy-ec2 NAME=$(NAME)
	@$(MAKE) ec2-url NAME=$(NAME)

# ── Lightsail Deployment (Alternative — Fixed Pricing) ────────────

LS_TF_DIR := terraform/lightsail
LS_TF_STATE := terraform-ls-$(NAME).tfstate

# Lightsail bundle override (BUNDLE=small_3_0 to use a smaller instance)
# Instance default: medium_3_0 ($20/mo, 4GB, 2vCPU)
# Server default:  xlarge_3_0 ($80/mo, 16GB, 4vCPU)
ifdef BUNDLE
  LS_BUNDLE_VAR := -var="bundle_id=$(BUNDLE)"
else
  LS_BUNDLE_VAR :=
endif

ls-create-key: ## Create SSH key pair for Lightsail (local keygen)
	@echo "Creating SSH key pair for Lightsail..."
	@mkdir -p ~/.ssh
	@if [ -f ~/.ssh/openclaw-ls ]; then \
		echo "SSH key already exists: ~/.ssh/openclaw-ls — skipping"; \
	else \
		ssh-keygen -t rsa -b 4096 -f ~/.ssh/openclaw-ls -N "" -C "openclaw-lightsail"; \
		chmod 400 ~/.ssh/openclaw-ls; \
		echo "SSH key created: ~/.ssh/openclaw-ls"; \
	fi

ls-delete-key: ## Delete Lightsail SSH key pair
	@echo "Deleting Lightsail SSH key pair..."
	@rm -f ~/.ssh/openclaw-ls ~/.ssh/openclaw-ls.pub
	@echo "Local key pair deleted"

ls-config: ## Create terraform.tfvars for Lightsail
	@if [ ! -f $(LS_TF_DIR)/terraform.tfvars ]; then \
		echo "Creating $(LS_TF_DIR)/terraform.tfvars..."; \
		cp $(LS_TF_DIR)/terraform.tfvars.example $(LS_TF_DIR)/terraform.tfvars; \
		echo "Config file created: $(LS_TF_DIR)/terraform.tfvars"; \
	else \
		echo "terraform.tfvars already exists"; \
	fi

ls-init: ## Initialize Terraform for Lightsail
	terraform -chdir=$(LS_TF_DIR) init

ls-plan: ## Preview Lightsail infrastructure changes
	@echo "Planning deployment: $(NAME)"
	terraform -chdir=$(LS_TF_DIR) plan -state=$(LS_TF_STATE) -var="deployment_name=$(NAME)"

ls-setup: ls-init ## Create Lightsail instance (~1-2 min)
	@echo "Creating Lightsail instance: openclaw-$(NAME)"
	terraform -chdir=$(LS_TF_DIR) apply -auto-approve -state=$(LS_TF_STATE) -var="deployment_name=$(NAME)" $(LS_BUNDLE_VAR)
	@echo ""
	@echo "================================================================"
	@terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '"  SSH: \(.ssh_command.value)"'
	@terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '"  URL: \(.dashboard_url.value)"'
	@echo "================================================================"
	@echo ""
	@echo "Waiting 60s for instance to boot and install Docker..."
	@sleep 60
	@echo "Instance ready! Deploy with: make deploy-ls NAME=$(NAME)"

deploy-ls: setup-docker-env ## Deploy OpenClaw to Lightsail (~30 sec)
	@chmod +x scripts/deploy-ec2.sh scripts/setup-cloudflare-tunnel.sh scripts/ec2-approve.sh 2>/dev/null || true
	@TF_DIR=$(LS_TF_DIR) TF_STATE=$(LS_TF_STATE) DEPLOY_NAME=$(NAME) SETUP_CLOUDFLARE=$(CLOUDFLARE) ./scripts/deploy-ec2.sh

ls-logs: ## Tail OpenClaw logs on Lightsail
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP \
		"cd /home/ec2-user/openclaw && docker compose logs -f"

ls-shell: ## SSH into Lightsail instance
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	echo "Connecting to openclaw-$(NAME) ($$EC2_IP)..."; \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP

ls-tunnel: ## Create SSH tunnel for secure localhost access
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	echo "Creating SSH tunnel to openclaw-$(NAME)..."; \
	echo ""; \
	echo "Access via localhost:"; \
	echo "   http://localhost:18789#token=$$TOKEN"; \
	echo ""; \
	echo "Press Ctrl+C to close tunnel"; \
	echo ""; \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no -L 18789:localhost:18789 -N ec2-user@$$EC2_IP

ls-approve: ## Approve pending browser device on Lightsail
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$EC2_IP" ]; then \
		echo "Error: No Lightsail instance found for NAME=$(NAME)"; \
		exit 1; \
	fi; \
	chmod +x scripts/ec2-approve.sh; \
	./scripts/ec2-approve.sh "$$EC2_IP" "$$SSH_KEY" "$$TOKEN"

ls-cloudflare-tunnel: ## Setup Cloudflare Tunnel for HTTPS access
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	if [ -z "$$EC2_IP" ]; then \
		echo "Error: No Lightsail instance found for NAME=$(NAME)"; \
		echo ""; \
		echo "Deploy an instance first:"; \
		echo "  make ls-full-setup NAME=$(NAME) CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-..."; \
		exit 1; \
	fi; \
	chmod +x scripts/setup-cloudflare-tunnel.sh; \
	./scripts/setup-cloudflare-tunnel.sh "$$EC2_IP" "$$SSH_KEY"

ls-cloudflare-stop: ## Stop Cloudflare Tunnel on Lightsail
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	chmod +x scripts/stop-cloudflare-tunnel.sh; \
	./scripts/stop-cloudflare-tunnel.sh "$$EC2_IP" "$$SSH_KEY"

ls-restart: ## Restart OpenClaw on Lightsail
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP \
		"cd /home/ec2-user/openclaw && docker compose restart"

ls-url: ## Show Lightsail dashboard URL and SSH info
	@echo "OpenClaw Lightsail Instance: openclaw-$(NAME)"
	@echo "=============================================="
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=$(LS_TF_STATE) -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
	echo ""; \
	echo "Chat Interface (works via HTTP):"; \
	echo "   http://$$EC2_IP:18789/chat?session=main"; \
	echo ""; \
	echo "Control UI (requires tunnel):"; \
	echo "   Run: make ls-tunnel NAME=$(NAME)"; \
	echo "   Then: http://localhost:18789"; \
	echo ""; \
	echo "SSH Access:"; \
	echo "   ssh -i $$SSH_KEY ec2-user@$$EC2_IP"; \
	echo ""; \
	echo "Quick Commands:"; \
	echo "   make ls-logs NAME=$(NAME)     # Tail logs"; \
	echo "   make ls-shell NAME=$(NAME)    # SSH session"; \
	echo "   make ls-tunnel NAME=$(NAME)   # Tunnel for control UI"
	@echo ""

ls-destroy: ## Destroy Lightsail instance
	@echo "Destroying deployment: $(NAME)"
	terraform -chdir=$(LS_TF_DIR) destroy -auto-approve -state=$(LS_TF_STATE) -var="deployment_name=$(NAME)"

ls-full-setup: ## Complete Lightsail setup from scratch (key + config + instance + deploy + optional CLOUDFLARE=true)
	@echo "================================================================"
	@echo "  OpenClaw Lightsail Full Setup: openclaw-$(NAME)"
	@echo "================================================================"
	@echo ""
	@echo "[1/4] Creating SSH key pair..."
	@./scripts/webhook-notify.sh creating_key "creating SSH key pair" $(NAME) 2>/dev/null || true
	@$(MAKE) ls-create-key
	@echo ""
	@echo "[2/4] Creating Terraform config..."
	@./scripts/webhook-notify.sh creating_config "creating Terraform config" $(NAME) 2>/dev/null || true
	@$(MAKE) ls-config
	@echo ""
	@echo "[3/4] Setting up Lightsail instance..."
	@./scripts/webhook-notify.sh creating_instance "creating Lightsail instance (~1-2 min)" $(NAME) 2>/dev/null || true
	@$(MAKE) ls-setup NAME=$(NAME)
	@echo ""
	@echo "[4/4] Deploying OpenClaw (+ Cloudflare tunnel if CLOUDFLARE=true)..."
	@$(MAKE) deploy-ls NAME=$(NAME) CLOUDFLARE=$(CLOUDFLARE)
	@echo "================================================================"
	@echo "  Complete! openclaw-$(NAME) is running on Lightsail"
	@echo "================================================================"

quick-ls: ## One-command Lightsail setup + deploy (requires existing SSH key)
	@$(MAKE) ls-setup NAME=$(NAME)
	@$(MAKE) deploy-ls NAME=$(NAME)
	@$(MAKE) ls-url NAME=$(NAME)

# ── Pipeline Server on Lightsail ─────────────────────────────────

server-ls-setup: ls-init ## Create Lightsail for pipeline server (~1-2 min)
	@echo "Creating Pipeline Server Lightsail instance (xlarge — 4 vCPU, 16GB RAM)..."
	@terraform -chdir=$(LS_TF_DIR) apply -auto-approve -state=terraform-ls-server.tfstate -var="deployment_name=server" -var="bundle_id=$(or $(BUNDLE),xlarge_3_0)" > /dev/null
	@echo ""
	@SERVER_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=terraform-ls-server.tfstate -raw public_ip 2>/dev/null); \
	echo "================================================================"; \
	echo "  Server IP: $$SERVER_IP"; \
	echo "  API:       http://$$SERVER_IP:$(SERVER_PORT)"; \
	echo "================================================================"
	@echo ""
	@echo "Waiting 60s for instance boot + Docker install..."
	@sleep 60
	@echo "Instance ready! Deploy with: make server-ls-deploy"

server-ls-deploy: ## Deploy Go pipeline server to Lightsail
	@chmod +x scripts/deploy-server.sh
	@TF_DIR=$(LS_TF_DIR) TF_STATE=terraform-ls-server.tfstate DEPLOY_NAME=server FRONTEND_URL=$(FRONTEND_URL) SERVER_PORT=$(SERVER_PORT) ./scripts/deploy-server.sh

server-ls-full-setup: ## Complete pipeline server setup on Lightsail (key + instance + deploy)
	@echo "================================================================"
	@echo "  Pipeline Server Full Setup (Lightsail)"
	@echo "================================================================"
	@echo ""
	@echo "[1/3] Creating SSH key pair..."
	@$(MAKE) ls-create-key
	@echo ""
	@echo "[2/3] Setting up Lightsail instance..."
	@$(MAKE) ls-config
	@$(MAKE) server-ls-setup
	@echo ""
	@echo "[3/3] Deploying pipeline server..."
	@$(MAKE) server-ls-deploy FRONTEND_URL=$(FRONTEND_URL)
	@echo "================================================================"
	@echo "  Pipeline Server is running on Lightsail!"
	@echo "================================================================"

server-ls-logs: ## Tail pipeline server logs (Lightsail)
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=terraform-ls-server.tfstate -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=$(LS_TF_DIR) output -state=terraform-ls-server.tfstate -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP "journalctl -u pipeline-server -f --no-pager"

server-ls-url: ## Show pipeline server URL (Lightsail)
	@EC2_IP=$$(terraform -chdir=$(LS_TF_DIR) output -state=terraform-ls-server.tfstate -raw public_ip 2>/dev/null); \
	echo "Pipeline Server: http://$$EC2_IP:$(SERVER_PORT)"; \
	echo "Swagger:         http://$$EC2_IP:$(SERVER_PORT)/swagger"; \
	echo "Health:          http://$$EC2_IP:$(SERVER_PORT)/health"

server-ls-destroy: ## Destroy pipeline server Lightsail instance
	terraform -chdir=$(LS_TF_DIR) destroy -auto-approve -state=terraform-ls-server.tfstate -var="deployment_name=server"

# ── Pipeline Server (Go API on EC2) ─────────────────────────────

SERVER_PORT ?= 4000
FRONTEND_URL ?= http://localhost:3000

server-setup: ec2-init ## Create EC2 for pipeline server (~2 min, 4 vCPU, 8GB+)
	@echo "Creating Pipeline Server EC2 instance (t3.xlarge — 4 vCPU, 16GB RAM)..."
	@terraform -chdir=terraform/ec2 apply -auto-approve -state=terraform-server.tfstate \
		-var="deployment_name=server" -var="instance_type=t3.xlarge"
	@echo ""
	@SERVER_IP=$$(terraform -chdir=terraform/ec2 output -state=terraform-server.tfstate -raw public_ip 2>/dev/null); \
	if ! echo "$$SERVER_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: Failed to get server IP from terraform state."; \
		exit 1; \
	fi; \
	echo "================================================================"; \
	echo "  Server IP: $$SERVER_IP"; \
	echo "  API:       http://$$SERVER_IP:$(SERVER_PORT)"; \
	echo "================================================================"
	@echo ""
	@echo "Waiting 60s for instance boot + Docker install..."
	@sleep 60
	@echo "Instance ready! Deploy with: make server-deploy"

server-deploy: ## Deploy Go pipeline server to EC2
	@chmod +x scripts/deploy-server.sh
	@TF_STATE=terraform-server.tfstate DEPLOY_NAME=server FRONTEND_URL=$(FRONTEND_URL) SERVER_PORT=$(SERVER_PORT) ./scripts/deploy-server.sh

server-full-setup: ## Complete pipeline server setup (key + EC2 + deploy)
	@echo "================================================================"
	@echo "  Pipeline Server Full Setup"
	@echo "================================================================"
	@echo ""
	@echo "[1/3] Creating SSH key pair..."
	@$(MAKE) ec2-create-key
	@echo ""
	@echo "[2/3] Setting up EC2 instance..."
	@$(MAKE) ec2-config
	@$(MAKE) server-setup
	@echo ""
	@echo "[3/3] Deploying pipeline server..."
	@$(MAKE) server-deploy FRONTEND_URL=$(FRONTEND_URL)
	@echo "================================================================"
	@echo "  Pipeline Server is running!"
	@echo "================================================================"

server-logs: ## Tail pipeline server logs
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=terraform-server.tfstate -raw public_ip 2>/dev/null); \
	SSH_KEY=$$(terraform -chdir=terraform/ec2 output -state=terraform-server.tfstate -json | jq -r '.ssh_command.value' | sed -n 's/.*-i \([^ ]*\).*/\1/p' | sed "s|^~|$$HOME|"); \
	ssh -i "$$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$$EC2_IP "journalctl -u pipeline-server -f --no-pager"

server-url: ## Show pipeline server URL
	@EC2_IP=$$(terraform -chdir=terraform/ec2 output -state=terraform-server.tfstate -raw public_ip 2>/dev/null); \
	echo "Pipeline Server: http://$$EC2_IP:$(SERVER_PORT)"; \
	echo "Swagger:         http://$$EC2_IP:$(SERVER_PORT)/swagger"; \
	echo "Health:          http://$$EC2_IP:$(SERVER_PORT)/health"

server-destroy: ## Destroy pipeline server EC2
	terraform -chdir=terraform/ec2 destroy -auto-approve -state=terraform-server.tfstate -var="deployment_name=server"

# ── AWS EKS Deployment (Production-grade) ────────────────────────

quick-deploy: setup-docker-env deploy-init deploy-apply k8s-secret k8s-apply ## First-time EKS deploy (all-in-one)
	@echo ""
	@echo "🎉 Quick deploy complete!"
	@echo ""
	@echo "To get the dashboard URL again:"
	@echo "  make k8s-url"

# ── AWS EKS Deployment ──────────────────────────────────────

deploy-init: ## Initialize Terraform
	terraform -chdir=terraform init

deploy-plan: ## Preview infrastructure changes
	terraform -chdir=terraform plan

deploy-apply: ## Apply infrastructure (creates EKS cluster)
	terraform -chdir=terraform apply
	@echo ""
	@echo "Configure kubectl:"
	@terraform -chdir=terraform output -raw kubeconfig_command
	@echo ""

deploy-destroy: ## Destroy all AWS infrastructure
	terraform -chdir=terraform destroy

# ── Kubernetes ──────────────────────────────────────────────

k8s-apply: ## Apply all Kubernetes manifests
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/storageclass.yaml
	kubectl apply -f k8s/configmap.yaml
	kubectl apply -f k8s/secret.yaml
	kubectl apply -f k8s/pvc.yaml
	kubectl apply -f k8s/deployment.yaml
	kubectl apply -f k8s/service.yaml
	@echo ""
	@echo "Waiting for deployment..."
	kubectl rollout status deployment/openclaw -n openclaw --timeout=120s
	@echo ""
	@echo "================================================================"
	@echo "  OpenClaw deployed successfully!"
	@echo "================================================================"
	@echo ""
	@HOST=$$(kubectl get svc openclaw -n openclaw -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -z "$$HOST" ]; then \
		echo "⚠️  LoadBalancer hostname not yet assigned. Run 'make k8s-status' to check."; \
		echo ""; \
		echo "To get the URL later:"; \
		echo "  make k8s-url"; \
	else \
		TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
		URL="http://$$HOST:$(GATEWAY_PORT)"; \
		if [ -n "$$TOKEN" ]; then \
			URL_WITH_TOKEN="$$URL#token=$$TOKEN"; \
			echo "Dashboard URL (with auth):"; \
			echo "  $$URL_WITH_TOKEN"; \
			echo ""; \
			echo "Dashboard URL (manual auth):"; \
			echo "  $$URL"; \
			echo "  Gateway Token: $$TOKEN"; \
		else \
			echo "Dashboard URL:"; \
			echo "  $$URL"; \
		fi; \
	fi
	@echo ""
	@echo "Useful commands:"
	@echo "  make k8s-status  - Show resource status"
	@echo "  make k8s-logs    - Tail pod logs"
	@echo "  make k8s-shell   - Open shell in pod"
	@echo "  make k8s-url     - Show dashboard URL"
	@echo "================================================================"

k8s-status: ## Show Kubernetes resource status
	kubectl get all -n openclaw

k8s-logs: ## Tail OpenClaw pod logs
	kubectl logs -f deployment/openclaw -n openclaw

k8s-shell: ## Open shell in OpenClaw pod
	kubectl exec -it deployment/openclaw -n openclaw -- /bin/sh

k8s-secret: ## Create K8s secret from .env file
	@if [ ! -f .env ]; then echo "No .env file found. Run 'make setup-docker-env' first."; exit 1; fi
	@echo "Creating Kubernetes secret from .env..."
	@kubectl create secret generic openclaw-secrets \
		--namespace=openclaw \
		--from-env-file=.env \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo "Secret created/updated in namespace openclaw"

k8s-url: ## Show OpenClaw dashboard URL with authentication
	@echo "OpenClaw Dashboard URL:"
	@echo "======================"
	@HOST=$$(kubectl get svc openclaw -n openclaw -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null); \
	if [ -z "$$HOST" ]; then \
		echo "⚠️  LoadBalancer not ready yet. Checking status..."; \
		echo ""; \
		kubectl get svc openclaw -n openclaw; \
		echo ""; \
		echo "Wait a few minutes and try again: make k8s-url"; \
	else \
		TOKEN=$$(grep '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null | cut -d= -f2); \
		URL="http://$$HOST:$(GATEWAY_PORT)"; \
		echo ""; \
		if [ -n "$$TOKEN" ]; then \
			echo "🔗 Click to open (auto-login):"; \
			echo "   $$URL#token=$$TOKEN"; \
			echo ""; \
			echo "📋 Manual access:"; \
			echo "   URL:   $$URL"; \
			echo "   Token: $$TOKEN"; \
		else \
			echo "🔗 Dashboard URL:"; \
			echo "   $$URL"; \
		fi; \
	fi
	@echo ""
