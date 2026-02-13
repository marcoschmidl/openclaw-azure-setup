#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw GitHub Agent — Destroy Script
# ==========================================================
# Tears down all Azure resources and cleans up local
# Terraform state. This is irreversible!
#
# Resources deleted:
#   - VM, Disks, NIC, Public IP
#   - Key Vault (including all secrets)
#   - VNet, NSG
#   - Resource Group
#
# Usage:
#   ./destroy.sh
#   RESOURCE_GROUP=rg-custom ./destroy.sh
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-openclaw}"

# -- Logging helpers --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[destroy] $1${NC}"; }
warn() { echo -e "${YELLOW}[destroy] WARN: $1${NC}"; }
err()  { echo -e "${RED}[destroy] ERROR: $1${NC}"; exit 1; }
step() { echo -e "${CYAN}[destroy] [$1/$TOTAL_STEPS] $2${NC}"; }

TOTAL_STEPS=4

echo ""
echo "=========================================="
echo -e "  ${RED}OpenClaw — Destroy All Resources${NC}"
echo "=========================================="
echo ""

# -- Step 1: Check prerequisites --
step 1 "Checking prerequisites..."

log "  Checking for Azure CLI..."
command -v az &>/dev/null || err "Azure CLI not found."

log "  Checking Azure login status..."
az account show &>/dev/null 2>&1 || err "Not logged in. Run 'az login' first."
SUBSCRIPTION=$(az account show --query name -o tsv)
log "  Subscription: $SUBSCRIPTION"
echo ""

# -- Confirmation --
echo -e "  Resource Group: ${RED}$RESOURCE_GROUP${NC}"
echo ""
echo "  This will PERMANENTLY DELETE all resources:"
echo "    - VM, Disks, NIC, Public IP"
echo "    - Key Vault (including all secrets)"
echo "    - VNet, NSG"
echo "    - Local Terraform state files"
echo ""
read -rp "  Type 'yes' to confirm deletion: " CONFIRM
echo ""

if [[ "$CONFIRM" != "yes" ]]; then
    warn "Aborted. No resources were deleted."
    exit 0
fi

# -- Step 2: Terraform destroy (if state exists) --
step 2 "Running Terraform destroy..."
if [ -f "$SCRIPT_DIR/terraform.tfstate" ]; then
    log "  Terraform state file found — running terraform destroy..."
    cd "$SCRIPT_DIR"
    if terraform destroy -auto-approve; then
        log "  Terraform destroy completed successfully"
    else
        warn "Terraform destroy failed — falling back to az group delete"
    fi
else
    warn "No terraform.tfstate found — skipping terraform destroy"
fi
echo ""

# -- Step 3: Delete resource group (fallback / cleanup) --
step 3 "Deleting Azure resource group '$RESOURCE_GROUP'..."
if az group show -n "$RESOURCE_GROUP" &>/dev/null 2>&1; then
    log "  Resource group exists — deleting (async)..."
    az group delete -n "$RESOURCE_GROUP" --yes --no-wait -o none
    log "  Deletion initiated (running asynchronously in Azure)"
    log "  Check progress: az group show -n $RESOURCE_GROUP -o table"
else
    log "  Resource group '$RESOURCE_GROUP' does not exist (already deleted)"
fi
echo ""

# -- Step 4: Clean up local Terraform files --
step 4 "Cleaning up local Terraform files..."
cd "$SCRIPT_DIR"

if [ -f "terraform.tfstate" ]; then
    rm -f terraform.tfstate
    log "  Removed terraform.tfstate"
fi

if [ -f "terraform.tfstate.backup" ]; then
    rm -f terraform.tfstate.backup
    log "  Removed terraform.tfstate.backup"
fi

if [ -d ".terraform/" ]; then
    rm -rf .terraform/
    log "  Removed .terraform/ directory"
fi

log "  Local cleanup complete"

# -- Done --
echo ""
echo "=========================================="
echo -e "  ${GREEN}Destroy complete!${NC}"
echo "=========================================="
echo ""
log "All Azure resources have been deleted (or deletion is in progress)."
log "Local Terraform state has been cleaned up."
echo ""
