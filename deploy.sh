#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw GitHub Agent — Deployment Wrapper
# ==========================================================
# Interactive wrapper around Terraform. Optionally prompts for
# secrets and then runs terraform init + apply.
#
# Prerequisites:
#   - Terraform >= 1.5 installed
#   - Azure CLI installed and logged in (az login)
#
# Usage:
#   ./deploy.sh                                    # interactive
#   GITHUB_TOKEN=ghp_xxx ./deploy.sh               # partial via ENV
#   terraform apply -var-file="secrets.tfvars"      # direct (no wrapper)
#
# Note: GITHUB_TOKEN and ANTHROPIC_API_KEY are optional.
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -- Logging helpers --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy] $1${NC}"; }
warn() { echo -e "${YELLOW}[deploy] WARN: $1${NC}"; }
err()  { echo -e "${RED}[deploy] ERROR: $1${NC}"; exit 1; }
step() { echo -e "${CYAN}[deploy] [$1/$TOTAL_STEPS] $2${NC}"; }

TOTAL_STEPS=5

echo ""
echo "=========================================="
echo "  OpenClaw Azure VM Deployment"
echo "=========================================="
echo ""

# -- Step 1: Check prerequisites --
step 1 "Checking prerequisites..."

log "  Checking for Terraform..."
command -v terraform &>/dev/null || err "Terraform not found. Install: https://developer.hashicorp.com/terraform/install"
TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)
log "  Terraform found: $TERRAFORM_VERSION"

log "  Checking for Azure CLI..."
command -v az &>/dev/null || err "Azure CLI not found. Install: https://aka.ms/installazurecli"
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
log "  Azure CLI found: $AZ_VERSION"

log "  Checking Azure login status..."
az account show &>/dev/null 2>&1 || err "Not logged in. Run 'az login' first."
SUBSCRIPTION=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
log "  Subscription: $SUBSCRIPTION ($SUBSCRIPTION_ID)"
echo ""

# -- Step 2: Collect secrets (optional) --
step 2 "Collecting secrets (optional — press Enter to skip)..."
TF_VARS=()

if [ -z "${GITHUB_TOKEN:-}" ]; then
    read -rsp "  GitHub PAT (Enter to skip): " GITHUB_TOKEN
    echo ""
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
    TF_VARS+=(-var "github_pat=${GITHUB_TOKEN}")
    log "  GitHub PAT provided (${#GITHUB_TOKEN} chars)"
else
    warn "GITHUB_TOKEN not set — skipping"
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    read -rsp "  Anthropic API Key (Enter to skip): " ANTHROPIC_API_KEY
    echo ""
fi
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    TF_VARS+=(-var "anthropic_key=${ANTHROPIC_API_KEY}")
    log "  Anthropic API Key provided (${#ANTHROPIC_API_KEY} chars)"
else
    warn "ANTHROPIC_API_KEY not set — skipping"
fi
echo ""

# -- Step 3: Terraform init --
step 3 "Initializing Terraform..."
cd "$SCRIPT_DIR"
terraform init -input=false
log "  Terraform initialized"
echo ""

# -- Step 4: Terraform apply --
step 4 "Applying Terraform configuration..."
log "  This will create all Azure resources. Please wait..."
echo ""
terraform apply ${TF_VARS[@]+"${TF_VARS[@]}"} -auto-approve
log "  Terraform apply completed"
echo ""

# -- Step 5: Display results --
step 5 "Collecting deployment outputs..."

FQDN=$(terraform output -raw fqdn 2>/dev/null || echo "n/a")
ADMIN_USER=$(terraform output -raw admin_username 2>/dev/null || echo "n/a")
KV_NAME=$(terraform output -raw keyvault_name 2>/dev/null || echo "n/a")
PUBLIC_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "n/a")

echo "=========================================="
echo -e "  ${GREEN}Deployment complete!${NC}"
echo "=========================================="
echo ""
echo "  VM:            $PUBLIC_IP"
echo "  DNS:           $FQDN"
echo "  Key Vault:     $KV_NAME"
echo ""
echo "  ---- Admin Credentials ----"
echo "  Username:      $ADMIN_USER"
echo "  Password:      (use 'make show-password' or 'terraform output -raw admin_password')"
echo "  (Stored in Key Vault: admin-username, admin-password)"
echo ""
echo "  ---- SSH ----"
echo "  ssh $ADMIN_USER@$FQDN"
echo ""
echo "  ---- Dashboard (Browser) ----"
echo "  https://$FQDN"
echo "  Login: $ADMIN_USER / <password>"
echo "  (Self-signed certificate — browser warning is expected)"
echo ""
echo "  ---- Start OpenClaw (on VM) ----"
echo "  cd ~/openclaw && ./start.sh"
echo ""
echo "  ---- Retrieve password from Key Vault ----"
echo "  az keyvault secret show --vault-name $KV_NAME --name admin-password --query value -o tsv"
echo ""
echo "  ---- Stop / Start VM ----"
echo "  $(terraform output -raw stop_vm 2>/dev/null)"
echo "  $(terraform output -raw start_vm 2>/dev/null)"
echo ""
log "Note: Wait ~5 min for cloud-init to finish installing Docker and Azure CLI on the VM."
log "Check progress: ssh $ADMIN_USER@$FQDN 'cloud-init status --long'"
echo ""
