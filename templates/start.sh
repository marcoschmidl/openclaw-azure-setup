#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw — Start Script
# ==========================================================
# Loads secrets from Azure Key Vault, configures Nginx Basic
# Auth, starts the OpenClaw systemd service, and launches
# the Nginx reverse proxy container.
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

TOTAL_STEPS=8
KEYVAULT="${keyvault_name}"
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$WORK_DIR/config/openclaw.json"

# Keep OpenClaw config in the repo workspace directory.
export OPENCLAW_CONFIG_PATH="$CONFIG_PATH"

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
    err "admin-username not found in Key Vault"
fi

log "  Fetching admin-password..."
ADMIN_PASS=$(az keyvault secret show --vault-name "$KEYVAULT" --name "admin-password" --query value -o tsv 2>/dev/null || echo "")
if [ -n "$ADMIN_PASS" ]; then
    log "  admin-password loaded ($${#ADMIN_PASS} chars)"
else
    err "admin-password not found in Key Vault"
fi

# -- Step 3: Write .env file for OpenClaw systemd service --
step 3 "Writing .env file for OpenClaw..."
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
echo "$ADMIN_PASS" | htpasswd -ci "$WORK_DIR/nginx/.htpasswd" "$ADMIN_USER"
log "  Basic Auth configured for user: $ADMIN_USER"

# -- Step 5: Ensure OpenClaw runtime config exists (gateway auth/password) --
step 5 "Configuring OpenClaw runtime profile..."
OPENCLAW_BIN="$HOME/.local/bin/openclaw"
if [ ! -x "$OPENCLAW_BIN" ]; then
    err "OpenClaw binary not found at $OPENCLAW_BIN"
fi
if [ -z "$ADMIN_PASS" ]; then
    err "admin-password is empty; refusing to start OpenClaw without gateway password"
fi

mkdir -p "$(dirname "$CONFIG_PATH")"
if [ ! -f "$CONFIG_PATH" ] && [ -f "$HOME/.openclaw/openclaw.json" ]; then
    cp "$HOME/.openclaw/openclaw.json" "$CONFIG_PATH"
    log "  Migrated config to $CONFIG_PATH"
fi

"$OPENCLAW_BIN" onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice skip \
    --skip-channels \
    --skip-skills \
    --skip-ui \
    --skip-health \
    --skip-daemon \
    --workspace "$WORK_DIR/workspace" \
    --gateway-bind lan \
    --gateway-port 18789 \
    --gateway-auth password \
    --gateway-password "$ADMIN_PASS" \
    --json >/dev/null
"$OPENCLAW_BIN" config set agents.defaults.model.primary "anthropic/claude-sonnet-4-5" >/dev/null
"$OPENCLAW_BIN" config set gateway.trustedProxies '["172.18.0.0/16","127.0.0.1/32","::1/128"]' >/dev/null
log "  OpenClaw profile configured"

# -- Step 6: Start OpenClaw systemd service --
step 6 "Starting OpenClaw service (systemd)..."
sudo systemctl daemon-reload
sudo systemctl start openclaw
log "  OpenClaw service started"

# Wait for OpenClaw to be ready (port 18789)
log "  Waiting for OpenClaw to become ready on port 18789..."
RETRIES=0
MAX_RETRIES=30
while ! curl -sf http://localhost:18789/ >/dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        warn "OpenClaw did not become ready within $${MAX_RETRIES}s — continuing anyway"
        warn "Check logs with: sudo journalctl -u openclaw -n 50"
        break
    fi
    sleep 2
done
if [ "$RETRIES" -lt "$MAX_RETRIES" ]; then
    log "  OpenClaw is ready (took ~$((RETRIES * 2))s)"
fi

# -- Step 7: Start Nginx reverse proxy container --
step 7 "Starting Nginx reverse proxy (Docker)..."
cd "$WORK_DIR"
docker compose up -d
log "  Nginx container started"

# -- Step 8: Verify everything is running --
step 8 "Verifying status..."
echo ""

# Check OpenClaw systemd service
OPENCLAW_STATUS=$(systemctl is-active openclaw 2>/dev/null || echo "inactive")
if [ "$OPENCLAW_STATUS" = "active" ]; then
    log "  openclaw (systemd): active"
else
    warn "openclaw (systemd): $OPENCLAW_STATUS"
fi

# Check Nginx container
NGINX_STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-nginx 2>/dev/null || echo "not found")
if [ "$NGINX_STATUS" = "running" ]; then
    log "  openclaw-nginx (docker): running"
else
    warn "openclaw-nginx (docker): $NGINX_STATUS"
fi

docker compose ps
echo ""

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
echo "    sudo journalctl -u openclaw -f    # Follow OpenClaw logs"
echo "    docker compose logs -f            # Follow Nginx logs"
echo "    docker compose ps                 # Nginx container status"
echo "    systemctl status openclaw         # OpenClaw service status"
echo "    ./stop.sh                         # Stop everything"
echo ""
