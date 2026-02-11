.PHONY: help install-docker onboard-docker docker-build docker-shell docker-clean update-docker logs-docker test-docker setup-docker-env reset-env sync-docker-config quick-docker start open approve deploy-init deploy-plan deploy-apply deploy-destroy k8s-apply k8s-status k8s-logs k8s-shell k8s-secret quick-deploy

# Variables
GATEWAY_PORT ?= 18789

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

setup-docker-env: ## Setup Docker environment from openclaw.json (skips if .env exists)
	@if [ -f .env ]; then \
		echo ".env already exists, skipping (run 'make reset-env' to regenerate)"; \
	else \
		chmod +x scripts/setup-docker-env.sh; \
		./scripts/setup-docker-env.sh; \
	fi

reset-env: ## Force regenerate .env from openclaw.json
	@chmod +x scripts/setup-docker-env.sh
	@./scripts/setup-docker-env.sh

sync-docker-config: ## Sync openclaw.json into running Docker container
	@if [ -f ~/.openclaw/openclaw.json ]; then \
		echo "Syncing configuration into Docker container..."; \
		docker exec -u root openclaw mkdir -p /home/node/.openclaw; \
		jq '.gateway.bind = "lan" | .agents.defaults.workspace = "/home/node/openclaw/workspace"' ~/.openclaw/openclaw.json > /tmp/openclaw-docker.json; \
		docker cp /tmp/openclaw-docker.json openclaw:/home/node/.openclaw/openclaw.json; \
		rm -f /tmp/openclaw-docker.json; \
		docker exec -u root openclaw chown -R node:node /home/node/.openclaw /home/node/openclaw; \
		echo "Configuration synced to Docker container"; \
	else \
		echo "No openclaw.json found to sync"; \
	fi

approve: ## Approve pending browser device for dashboard access
	@TOKEN=$$(jq -r '.gateway.auth.token // empty' ~/.openclaw/openclaw.json 2>/dev/null); \
	REQ=$$(docker exec openclaw node /app/openclaw.mjs devices list --url ws://127.0.0.1:18789 --token $$TOKEN 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1); \
	if [ -z "$$REQ" ]; then \
		echo "No pending device requests"; \
	else \
		docker exec openclaw node /app/openclaw.mjs devices approve $$REQ --url ws://127.0.0.1:18789 --token $$TOKEN; \
		echo "Device approved - refresh dashboard"; \
	fi

open: ## Open dashboard in browser (auto-authenticates)
	@TOKEN=$$(jq -r '.gateway.auth.token // empty' ~/.openclaw/openclaw.json 2>/dev/null); \
	if [ -z "$$TOKEN" ]; then \
		echo "No gateway token found in ~/.openclaw/openclaw.json"; exit 1; \
	fi; \
	URL="http://localhost:$(GATEWAY_PORT)#token=$$TOKEN"; \
	echo "Opening dashboard..."; \
	open "$$URL" 2>/dev/null || xdg-open "$$URL" 2>/dev/null || echo "$$URL"

start: install-docker sync-docker-config open ## Start Docker (uses existing .env)
	@echo ""
	@echo "OpenClaw is running in Docker!"
	@echo "If dashboard says 'pairing required', run: make approve"

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
