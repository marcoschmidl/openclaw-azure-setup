#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw — Start Script
# ==========================================================
# Loads secrets from Azure Key Vault, configures Nginx Basic
# Auth, and starts the Docker containers (OpenClaw + Nginx).
#
# This file is a Terraform template. Variables:
#   ${keyvault_name}  — Azure Key Vault name
#   ${fqdn}           — Public FQDN of this VM
#
# Usage:
#   cd ~/openclaw && ./start.sh
# ==========================================================

# -- Logging helpers --
log()  { echo -e "\033[0;32m[start.sh] $1\033[0m"; }
warn() { echo -e "\033[1;33m[start.sh] WARN: $1\033[0m"; }
err()  { echo -e "\033[0;31m[start.sh] ERROR: $1\033[0m" >&2; exit 1; }
step() { echo -e "\033[0;36m[start.sh] [$1/$TOTAL_STEPS] $2\033[0m"; }

TOTAL_STEPS=6
KEYVAULT="${keyvault_name}"
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"

log "Starting OpenClaw setup..."
log "  Working directory: $WORK_DIR"
log "  Key Vault:         $KEYVAULT"
echo ""

# -- Step 1: Authenticate with Azure using VM managed identity --
step 1 "Authenticating with Azure (managed identity)..."
if az account show &>/dev/null 2>&1; then
    log "  Already authenticated with Azure"
else
    az login --identity --output none 2>/dev/null || err "Failed to authenticate with Azure managed identity"
    log "  Azure authentication successful"
fi

# -- Step 2: Load secrets from Key Vault --
step 2 "Loading secrets from Key Vault '$KEYVAULT'..."

log "  Fetching github-pat..."
GITHUB_TOKEN=$(az keyvault secret show --vault-name "$KEYVAULT" --name "github-pat" --query value -o tsv 2>/dev/null || echo "")
if [ -n "$GITHUB_TOKEN" ]; then
    log "  github-pat loaded ($${#GITHUB_TOKEN} chars)"
else
    warn "github-pat not found in Key Vault — GITHUB_TOKEN will not be set"
fi

log "  Fetching anthropic-key..."
ANTHROPIC_API_KEY=$(az keyvault secret show --vault-name "$KEYVAULT" --name "anthropic-key" --query value -o tsv 2>/dev/null || echo "")
if [ -n "$ANTHROPIC_API_KEY" ]; then
    log "  anthropic-key loaded ($${#ANTHROPIC_API_KEY} chars)"
else
    warn "anthropic-key not found in Key Vault — ANTHROPIC_API_KEY will not be set"
fi

log "  Fetching admin-username..."
ADMIN_USER=$(az keyvault secret show --vault-name "$KEYVAULT" --name "admin-username" --query value -o tsv 2>/dev/null || echo "")
if [ -n "$ADMIN_USER" ]; then
    log "  admin-username loaded: $ADMIN_USER"
else
    warn "admin-username not found in Key Vault"
fi

log "  Fetching admin-password..."
ADMIN_PASS=$(az keyvault secret show --vault-name "$KEYVAULT" --name "admin-password" --query value -o tsv 2>/dev/null || echo "")
if [ -n "$ADMIN_PASS" ]; then
    log "  admin-password loaded ($${#ADMIN_PASS} chars)"
else
    warn "admin-password not found in Key Vault"
fi

# -- Step 3: Write .env file for Docker Compose --
step 3 "Writing .env file for Docker Compose..."
: > "$WORK_DIR/.env"
if [ -n "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN=$GITHUB_TOKEN" >> "$WORK_DIR/.env"
    log "  Added GITHUB_TOKEN to .env"
fi
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$WORK_DIR/.env"
    log "  Added ANTHROPIC_API_KEY to .env"
fi
chmod 600 "$WORK_DIR/.env"
log "  .env written and permissions set to 600"

# -- Step 4: Configure Nginx Basic Auth --
step 4 "Configuring Nginx Basic Auth (htpasswd)..."
if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASS" ]; then
    echo "$ADMIN_PASS" | htpasswd -ci "$WORK_DIR/nginx/.htpasswd" "$ADMIN_USER"
    log "  Basic Auth configured for user: $ADMIN_USER"
else
    warn "Admin credentials not found in Key Vault — Basic Auth will NOT be configured"
    warn "The dashboard will be inaccessible until credentials are set"
fi

# -- Step 5: Start Docker containers --
step 5 "Starting Docker containers (OpenClaw + Nginx)..."
cd "$WORK_DIR"
docker compose up -d
log "  Docker containers started"

# -- Step 6: Verify containers are running --
step 6 "Verifying container status..."
echo ""
docker compose ps
echo ""

# Check individual container health
OPENCLAW_STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-github-agent 2>/dev/null || echo "not found")
NGINX_STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-nginx 2>/dev/null || echo "not found")

if [ "$OPENCLAW_STATUS" = "running" ]; then
    log "  openclaw-github-agent: running"
else
    warn "openclaw-github-agent: $OPENCLAW_STATUS"
fi

if [ "$NGINX_STATUS" = "running" ]; then
    log "  openclaw-nginx: running"
else
    warn "openclaw-nginx: $NGINX_STATUS"
fi

# -- Done --
echo ""
echo "=========================================="
log "OpenClaw is up and running!"
echo "=========================================="
echo ""
echo "  Dashboard: https://${fqdn}"
echo "  Login:     $ADMIN_USER / <password>"
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f          # Follow container logs"
echo "    docker compose ps               # Container status"
echo "    ./stop.sh                       # Stop everything"
echo ""
