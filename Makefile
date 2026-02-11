.PHONY: help install-docker onboard-docker docker-build docker-shell docker-clean clean update-docker logs-docker test-docker setup-docker-env reset-env clone-config sync-docker-config quick-docker start open approve deploy-init deploy-plan deploy-apply deploy-destroy k8s-apply k8s-status k8s-logs k8s-shell k8s-secret quick-deploy

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
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

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

docker-clean: ## Clean Docker resources
	docker-compose down -v
	docker image prune -f

clean: ## Full reset (containers, volumes, .env)
	@docker-compose down -v 2>/dev/null || true
	@rm -f .env
	@echo "Cleaned: containers, volumes, paired devices, .env"
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

quick-docker: setup-docker-env start ## First-time setup + start

quick-deploy: setup-docker-env deploy-init deploy-apply k8s-secret k8s-apply ## First-time EKS deploy (all-in-one)

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
	@echo "Service endpoint:"
	@kubectl get svc openclaw -n openclaw -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "(pending)"
	@echo ":$(GATEWAY_PORT)"

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
