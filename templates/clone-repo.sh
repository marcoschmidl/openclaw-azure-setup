#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw — Clone Repository Helper
# ==========================================================
# Clones a GitHub repository into the OpenClaw workspace.
# If a GitHub PAT is stored in Key Vault, it will be used
# for authentication (required for private repos).
#
# This file is a Terraform template. Variables:
#   ${keyvault_name}  — Azure Key Vault name
#
# Usage:
#   ./clone-repo.sh https://github.com/org/repo.git
# ==========================================================

# -- Logging helpers --
log()  { echo -e "\033[0;32m[clone-repo.sh] $1\033[0m"; }
warn() { echo -e "\033[1;33m[clone-repo.sh] WARN: $1\033[0m"; }
err()  { echo -e "\033[0;31m[clone-repo.sh] ERROR: $1\033[0m" >&2; exit 1; }

REPO_URL="$${1:-}"
KEYVAULT="${keyvault_name}"
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$WORK_DIR/workspace"

# -- Validate arguments --
if [ -z "$REPO_URL" ]; then
    echo ""
    echo "Usage: ./clone-repo.sh <repository-url>"
    echo ""
    echo "Examples:"
    echo "  ./clone-repo.sh https://github.com/org/repo.git"
    echo "  ./clone-repo.sh https://github.com/org/private-repo.git"
    echo ""
    echo "Note: Private repos require a GitHub PAT stored in Key Vault."
    exit 1
fi

log "Cloning repository: $REPO_URL"
log "  Key Vault: $KEYVAULT"
log "  Workspace: $WORKSPACE"
echo ""

# -- Fetch GitHub token from Key Vault (optional) --
log "Checking Key Vault for GitHub PAT..."
GITHUB_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT" --name "github-pat" --query value -o tsv 2>/dev/null || echo "")

if [ -n "$GITHUB_TOKEN" ]; then
    log "  GitHub PAT found — using authenticated clone"
else
    warn "No GitHub PAT in Key Vault — cloning without authentication (public repos only)"
fi

# -- Clone into the OpenClaw workspace directory --
log "Cloning into workspace..."
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"
if [ -n "$GITHUB_TOKEN" ]; then
    git -c "http.https://github.com/.extraheader=AUTHORIZATION: Bearer $GITHUB_TOKEN" clone -- "$REPO_URL"
else
    git clone -- "$REPO_URL"
fi

# -- Verify clone --
REPO_NAME=$(basename "$REPO_URL" .git)
log "Verifying clone..."
if [ -d "$WORKSPACE/$REPO_NAME" ]; then
    log "  Repository '$REPO_NAME' cloned successfully"
else
    warn "  Clone may have failed — directory not found"
fi

echo ""
log "Done. Repository available at: $WORKSPACE/$REPO_NAME"
echo ""
