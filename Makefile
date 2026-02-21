# ==========================================================
# OpenClaw GitHub Agent — Makefile
# ==========================================================
# Provides convenient targets for deploying, managing, and
# debugging the OpenClaw Azure VM setup.
#
# Architecture: Terraform (infra) -> Cloud-Init (bootstrap) -> Ansible (config)
#
# Usage:
#   cp .env.example .env        # Enter secrets (optional)
#   make deploy                 # Deploy infrastructure (Terraform)
#   make wait-for-cloud-init    # Wait for bootstrap
#   make configure              # Configure VM (Ansible)
#   make openclaw-start         # Start services on VM
#   make help                   # Show all targets
# ==========================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env file if it exists (contains GITHUB_TOKEN, ANTHROPIC_API_KEY).
# Using ?= so that environment variables (e.g. GITHUB_TOKEN=xxx make deploy)
# take precedence over values from the .env file.
ifneq (,$(wildcard .env))
  GITHUB_TOKEN    ?= $(shell grep '^GITHUB_TOKEN=' .env 2>/dev/null | cut -d= -f2-)
  ANTHROPIC_API_KEY ?= $(shell grep '^ANTHROPIC_API_KEY=' .env 2>/dev/null | cut -d= -f2-)
endif

# -- Variables (can be overridden via environment or command line) --
RG            ?= rg-openclaw
VM            ?= vm-openclaw
TF_VARS       ?=
EXTRA_TF_VARS ?=
ALL_TF_VARS   = $(strip $(TF_VARS) $(EXTRA_TF_VARS))

# Pass secrets via TF_VAR_ environment variables (not visible in ps aux)
ifneq ($(strip $(GITHUB_TOKEN)),)
  export TF_VAR_github_pat := $(GITHUB_TOKEN)
endif

ifneq ($(strip $(ANTHROPIC_API_KEY)),)
  export TF_VAR_anthropic_key := $(ANTHROPIC_API_KEY)
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
	@echo "  Next steps:"
	@echo "    make wait-for-cloud-init   # Wait for bootstrap (~2 min)"
	@echo "    make configure             # Configure VM (Ansible)"
	@echo "    make openclaw-start        # Start services"
	@echo ""
	@echo "  Password:  make show-password"
	@echo "  SSH:       make ssh"
	@echo ""

.PHONY: redeploy-vm
redeploy-vm: init ## Recreate the VM (applies new cloud-init)
	terraform apply $(ALL_TF_VARS) -replace=azurerm_linux_virtual_machine.main -auto-approve
	@echo ""
	@echo "[make] VM recreated. Run: make wait-for-cloud-init && make configure && make openclaw-start"

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
logs: ## Show OpenClaw service logs (last 100 lines)
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching OpenClaw logs from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'sudo journalctl -u openclaw --no-pager -n 100'

.PHONY: logs-nginx
logs-nginx: ## Show Nginx container logs (last 100 lines)
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Fetching Nginx logs from $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'sudo -u openclaw docker logs --tail 100 openclaw-nginx 2>&1'

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
	ssh "$$USER@$$FQDN" 'sudo -u openclaw docker ps -a'

.PHONY: devices-list
devices-list: ## List pending/paired Control UI devices
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	KV=$$(terraform output -raw keyvault_name 2>/dev/null); \
	echo "[make] Listing pending Control UI devices on $$FQDN..."; \
	ssh "$$USER@$$FQDN" "sudo -u openclaw bash -c 'PASS=\$$(az keyvault secret show --vault-name \"$$KV\" --name admin-password --query value -o tsv) && export OPENCLAW_CONFIG_PATH=/home/openclaw/openclaw/config/openclaw.json && /home/openclaw/.local/bin/openclaw devices list --url ws://127.0.0.1:18789 --password \"\$$PASS\"'"

.PHONY: approve-device
approve-device: ## Approve pending Control UI device (use REQUEST_ID=<id>)
	@if [ -z "$(REQUEST_ID)" ]; then \
		echo "Error: REQUEST_ID is required"; \
		echo "Usage: make approve-device REQUEST_ID=<request-id>"; \
		exit 1; \
	fi
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	KV=$$(terraform output -raw keyvault_name 2>/dev/null); \
	echo "[make] Approving device request $(REQUEST_ID) on $$FQDN..."; \
	ssh "$$USER@$$FQDN" "sudo -u openclaw bash -c 'PASS=\$$(az keyvault secret show --vault-name \"$$KV\" --name admin-password --query value -o tsv) && export OPENCLAW_CONFIG_PATH=/home/openclaw/openclaw/config/openclaw.json && /home/openclaw/.local/bin/openclaw devices approve $(REQUEST_ID) --url ws://127.0.0.1:18789 --password \"\$$PASS\"'"

# ==========================================================
# OpenClaw Start / Stop (on VM via SSH)
# ==========================================================

.PHONY: openclaw-start
openclaw-start: ## Start OpenClaw + Nginx on the VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Starting OpenClaw on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'sudo -u openclaw bash -c "cd /home/openclaw/openclaw && ./start.sh"'

.PHONY: openclaw-stop
openclaw-stop: ## Stop OpenClaw + Nginx on the VM
	@FQDN=$$(terraform output -raw fqdn 2>/dev/null); \
	USER=$$(terraform output -raw admin_username 2>/dev/null); \
	echo "[make] Stopping OpenClaw on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'sudo -u openclaw bash -c "cd /home/openclaw/openclaw && ./stop.sh"'

# ==========================================================
# Ansible Configuration
# ==========================================================

.PHONY: configure
configure: ansible-inventory ansible-deps ## Configure VM via Ansible playbook
	$(call check_tool,ansible-playbook)
	@FQDN=$$(terraform output -raw fqdn); \
	USER=$$(terraform output -raw admin_username); \
	KV=$$(terraform output -raw keyvault_name); \
	echo "[make] Running Ansible playbook against $$FQDN..."; \
	KEYVAULT_NAME=$$KV VM_FQDN=$$FQDN ADMIN_USERNAME=$$USER \
	  ansible-playbook -i ansible/inventory.yml ansible/playbook.yml \
	  $(if $(TAGS),--tags $(TAGS),)

.PHONY: ansible-inventory
ansible-inventory: ## Generate Ansible inventory from Terraform outputs
	@FQDN=$$(terraform output -raw fqdn); \
	USER=$$(terraform output -raw admin_username); \
	printf "all:\n  hosts:\n    openclaw-vm:\n      ansible_host: %s\n      ansible_user: %s\n      ansible_ssh_private_key_file: ~/.ssh/id_rsa\n" \
	  "$$FQDN" "$$USER" > ansible/inventory.yml; \
	echo "[make] Inventory written to ansible/inventory.yml"

.PHONY: ansible-deps
ansible-deps: ## Install Ansible Galaxy collections
	ansible-galaxy collection install -r ansible/requirements.yml

.PHONY: ansible-lint
ansible-lint: ## Lint Ansible playbook and roles
	$(call check_tool,ansible-lint)
	ansible-lint ansible/playbook.yml

.PHONY: ansible-check
ansible-check: ansible-inventory ## Dry-run Ansible playbook (no changes)
	$(call check_tool,ansible-playbook)
	@FQDN=$$(terraform output -raw fqdn); \
	USER=$$(terraform output -raw admin_username); \
	KV=$$(terraform output -raw keyvault_name); \
	KEYVAULT_NAME=$$KV VM_FQDN=$$FQDN ADMIN_USERNAME=$$USER \
	  ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --check --diff

.PHONY: wait-for-cloud-init
wait-for-cloud-init: ## Wait for cloud-init to finish on VM
	@FQDN=$$(terraform output -raw fqdn); \
	USER=$$(terraform output -raw admin_username); \
	echo "[make] Waiting for cloud-init on $$FQDN..."; \
	ssh "$$USER@$$FQDN" 'cloud-init status --wait'

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

.PHONY: memory-sync-template
memory-sync-template: ## Generate Basic Memory update template
	./ai/skills/basic-memory-state-sync/run.sh

.PHONY: install-pre-commit
install-pre-commit: ## Install local git pre-commit hook for memory checks
	cp .githooks/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "[make] Installed .git/hooks/pre-commit"

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
	@echo "  cp .env.example .env         # Enter secrets (optional)"
	@echo "  make deploy                  # Deploy infrastructure (Terraform)"
	@echo "  make wait-for-cloud-init     # Wait for bootstrap"
	@echo "  make configure               # Configure VM (Ansible)"
	@echo "  make openclaw-start          # Start OpenClaw on VM"
	@echo ""
	@echo "Day-2 config change:"
	@echo "  make configure               # Re-run Ansible (idempotent)"
	@echo "  make configure TAGS=nginx    # Only update Nginx"
	@echo ""
