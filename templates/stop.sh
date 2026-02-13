#!/bin/bash
set -euo pipefail

# ==========================================================
# OpenClaw — Stop Script
# ==========================================================
# Stops all Docker containers and removes the local .env file
# containing secrets (secrets remain safe in Key Vault).
#
# Usage:
#   cd ~/openclaw && ./stop.sh
# ==========================================================

# -- Logging helpers --
log()  { echo -e "\033[0;32m[stop.sh] $1\033[0m"; }
warn() { echo -e "\033[1;33m[stop.sh] WARN: $1\033[0m"; }

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"

log "Stopping OpenClaw..."
log "  Working directory: $WORK_DIR"
echo ""

# -- Step 1: Show current container status --
log "Current container status:"
cd "$WORK_DIR"
docker compose ps 2>/dev/null || true
echo ""

# -- Step 2: Stop and remove containers --
log "Stopping Docker containers..."
docker compose down
log "  Containers stopped and removed"

# -- Step 3: Clean up local secrets --
if [ -f "$WORK_DIR/.env" ]; then
    rm -f "$WORK_DIR/.env"
    log "  Removed .env file (secrets cleaned up)"
else
    log "  No .env file found (already clean)"
fi

# -- Step 4: Clean up htpasswd --
if [ -f "$WORK_DIR/nginx/.htpasswd" ]; then
    rm -f "$WORK_DIR/nginx/.htpasswd"
    log "  Removed htpasswd file"
fi

# -- Done --
echo ""
log "OpenClaw stopped. Secrets removed from disk."
log "  Secrets remain safe in Azure Key Vault."
log "  Run ./start.sh to restart."
echo ""
