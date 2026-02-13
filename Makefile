# ==========================================================
# OpenClaw GitHub Agent — Makefile
# ==========================================================
# Provides convenient targets for deploying, managing, and
# debugging the OpenClaw Azure VM setup.
#
# Usage:
#   cp .env.example .env   # Enter secrets (optional)
#   make deploy             # Deploy infrastructure
#   make status             # Check VM status
#   make ssh                # SSH into VM
#   make logs               # View container logs
#   make destroy            # Delete everything
#   make help               # Show all targets
# ==========================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env file if it exists (contains GITHUB_TOKEN, ANTHROPIC_API_KEY)
-include .env
export

# -- Variables (can be overridden via environment or command line) --
RG            ?= rg-openclaw
VM            ?= vm-openclaw
TF_VARS       ?=
EXTRA_TF_VARS ?=
TF_SECRET_VARS =
ALL_TF_VARS   = $(strip $(TF_VARS) $(EXTRA_TF_VARS) $(TF_SECRET_VARS))

# Pass secrets as Terraform variables if they are set
ifneq ($(strip $(GITHUB_TOKEN)),)
  TF_SECRET_VARS += -var="github_pat=$(GITHUB_TOKEN)"
endif

ifneq ($(strip $(ANTHROPIC_API_KEY)),)
  TF_SECRET_VARS += -var="anthropic_key=$(ANTHROPIC_API_KEY)"
endif

# -- Helper: Check if a tool is installed --
define check_tool
	@command -v $(1) >/dev/null 2>&1 || { echo "Error: $(1) not found. Please install it first."; exit 1; }
endef

# ==========================================================
# Deployment
# ==========================================================

.PHONY: init
init: ## Initialize Terraform (download providers)
	$(call check_tool,terraform)
	terraform init -input=false

.PHONY: plan
plan: init ## Show planned changes (dry-run)
	terraform plan $(ALL_TF_VARS)

.PHONY: deploy
deploy: init ## Deploy infrastructure (terraform apply)
	terraform apply $(ALL_TF_VARS) -auto-approve
	@echo ""
	@echo "=========================================="
	@echo "  Deployment complete!"
	@echo "=========================================="
	@echo ""
	@echo "  DNS:       $$(terraform output -raw fqdn 2>/dev/null)"
	@echo "  IP:        $$(terraform output -raw vm_public_ip 2>/dev/null)"
	@echo "  User:      $$(terraform output -raw admin_username 2>/dev/null)"
	@echo "  Dashboard: $$(terraform output -raw dashboard_url 2>/dev/null)"
	@echo ""
	@echo "  Password:  make show-password"
	@echo "  SSH:       make ssh"
	@echo ""

.PHONY: destroy
destroy: ## Delete all Azure resources and local state
	./destroy.sh

# ==========================================================
# VM Management
# ==========================================================

.PHONY: start
start: ## Start the VM
	$(call check_tool,az)
	@echo "[make] Starting VM $(VM) in resource group $(RG)..."
	az vm start -g $(RG) -n $(VM)
	@echo "[make] VM started."

.PHONY: stop
stop: ## Stop the VM (deallocate — no compute costs)
	$(call check_tool,az)
	@echo "[make] Deallocating VM $(VM) in resource group $(RG)..."
	az vm deallocate -g $(RG) -n $(VM)
	@echo "[make] VM deallocated (no compute costs)."

.PHONY: restart
restart: stop start ## Restart the VM (deallocate + start)

.PHONY: status
status: ## Show VM status and public IP
	$(call check_tool,az)
	@echo "[make] Querying VM status..."
	@az vm show -d -g $(RG) -n $(VM) \
		--query '{name:name, state:powerState, ip:publicIps, fqdns:fqdns}' \
		-o table 2>/dev/null || echo "[make] VM not found in resource group $(RG)."

# ==========================================================
# Access
# ==========================================================

.PHONY: ssh
ssh: ## SSH into the VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Connecting: ssh $$USER@$$FQDN"; \
	ssh "$$USER@$$FQDN"

.PHONY: show-password
show-password: ## Show admin password from Terraform state
	@terraform output -raw admin_password 2>/dev/null || echo "[make] No Terraform state found."

.PHONY: show-password-kv
show-password-kv: ## Retrieve admin password from Key Vault
	$(call check_tool,az)
	@KV=$$(terraform output -raw keyvault_name 2>/dev/null); \
	echo "[make] Fetching password from Key Vault $$KV..."; \
	az keyvault secret show --vault-name "$$KV" --name admin-password --query value -o tsv

# ==========================================================
# Logs & Debugging
# ==========================================================

.PHONY: logs
logs: ## Show OpenClaw container logs (last 100 lines)
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching OpenClaw logs from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'docker logs --tail 100 openclaw-github-agent 2>&1'

.PHONY: logs-nginx
logs-nginx: ## Show Nginx container logs (last 100 lines)
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching Nginx logs from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'docker logs --tail 100 openclaw-nginx 2>&1'

.PHONY: cloud-init-status
cloud-init-status: ## Check cloud-init provisioning status on VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Checking cloud-init status on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'cloud-init status --long'

.PHONY: cloud-init-logs
cloud-init-logs: ## Show cloud-init provisioning logs
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching cloud-init logs from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'sudo tail -80 /var/log/cloud-init-output.log'

.PHONY: docker-ps
docker-ps: ## Show Docker container status on VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching container status from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'docker ps -a'

# ==========================================================
# OpenClaw Start / Stop (on VM via SSH)
# ==========================================================

.PHONY: openclaw-start
openclaw-start: ## Start OpenClaw + Nginx on the VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Starting OpenClaw on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'cd ~/openclaw && ./start.sh'

.PHONY: openclaw-stop
openclaw-stop: ## Stop OpenClaw + Nginx on the VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Stopping OpenClaw on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'cd ~/openclaw && ./stop.sh'

# ==========================================================
# Terraform Utilities
# ==========================================================

.PHONY: output
output: ## Show all Terraform outputs
	@terraform output 2>/dev/null || echo "[make] No Terraform state found."

.PHONY: fmt
fmt: ## Format Terraform files
	terraform fmt

.PHONY: validate
validate: init ## Validate Terraform configuration
	terraform validate

# ==========================================================
# Help
# ==========================================================

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "OpenClaw — Available Targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quickstart:"
	@echo "  cp .env.example .env    # Enter secrets (optional)"
	@echo "  make deploy             # Deploy infrastructure"
	@echo "  make openclaw-start     # Start OpenClaw on VM"
	@echo "  make ssh                # SSH into VM"
	@echo ""
