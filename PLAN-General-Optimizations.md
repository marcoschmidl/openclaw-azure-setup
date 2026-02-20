# Code Review & Optimization Plan

> Generated from a full code review against Azure/Terraform Context7 docs.
> Date: 2026-02-20

---

## Overall Assessment

The project is **well-built**. The architecture (Terraform + cloud-init + systemd + Docker-Nginx)
follows established patterns and is cleanly implemented. Code quality is high: good comments,
consistent logging, clean separation of concerns. The setup is **production-ready for a
single-user or small-team environment**.

For a larger production deployment, consider: remote state with encryption, Let's Encrypt
(instead of self-signed certs), and dedicated VNet peering.

---

## What's Done Right

### Terraform (`main.tf`)

- Correct use of `SystemAssigned` Managed Identity (per azurerm docs)
- RBAC-based Key Vault (best practice over Access Policies)
- `depends_on` for Key Vault Secrets on the Role Assignment — correct and necessary
- `custom_data = base64encode(templatefile(...))` — exactly right per Terraform docs
- Sensitive marking on variables (`github_pat`, `anthropic_key`, `admin_password`)
- NSG with IP-locking instead of open ports
- Auto-shutdown as cost protection

### Cloud-Init (`cloud-init.yml`)

- `$${distro_id}` double-dollar escaping for `templatefile()` — correct
- `daemon.json` written via `write_files` before Docker install in `runcmd` — correct order
- Good package selection (fail2ban, unattended-upgrades, debugging tools)

### Docker / Nginx

- `docker-compose.yml`: exemplary security hardening (`read_only`, `cap_drop: ALL`,
  `no-new-privileges`, memory limits)
- `nginx.conf`: proper WebSocket support, security headers, HTTP-to-HTTPS redirect

### Systemd Service (`openclaw.service`)

- `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=true`, `PrivateTmp=true`
- `ReadWritePaths` correctly scoped
- `EnvironmentFile=-` with dash prefix for optional `.env`

### Shell Scripts

- Consistent logging helpers (`log`, `warn`, `err`, `step`) across all scripts
- `set -euo pipefail` in all scripts
- `stop.sh` cleans up secrets from disk

---

## Findings & Optimization Suggestions

### Priority Legend

| Symbol | Meaning |
|--------|---------|
| **P0** | High — should fix before production use |
| **P1** | Medium — recommended improvement |
| **P2** | Low — nice to have / cosmetic |

---

### P0-1: Key Vault Retry Logic in `start.sh`

**File:** `templates/start.sh`

**Problem:** After VM start, Azure RBAC role assignments can take up to 10 minutes to
propagate. If `start.sh` runs immediately after first boot, `az keyvault secret show` may
fail because the VM's managed identity doesn't have access yet. There is no retry mechanism.

**Fix:** Add retry logic before the first Key Vault access:

```bash
# Retry logic for Key Vault access (RBAC propagation delay)
MAX_KV_RETRIES=12
KV_RETRY=0
while ! az keyvault secret show --vault-name "$KEYVAULT" --name "admin-username" \
        --query value -o tsv &>/dev/null; do
    KV_RETRY=$((KV_RETRY + 1))
    if [ "$KV_RETRY" -ge "$MAX_KV_RETRIES" ]; then
        err "Key Vault not accessible after ${MAX_KV_RETRIES} retries (waited $((KV_RETRY * 30))s)"
    fi
    warn "Key Vault not yet accessible, retrying in 30s... ($KV_RETRY/$MAX_KV_RETRIES)"
    sleep 30
done
```

---

### P0-2: Key Vault Purge Protection

**File:** `main.tf` (line ~247)

**Problem:** `purge_protection_enabled` is not set on the Key Vault. Currently
`purge_soft_delete_on_destroy = true` is configured in the provider features block,
which permanently deletes the vault on `terraform destroy`. This is convenient for
dev but risky for production — accidental destroys permanently delete all secrets.

**Fix (for production):**

```hcl
resource "azurerm_key_vault" "main" {
  # ... existing config ...
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}
```

> Note: Once purge protection is enabled, it **cannot be disabled**. Only enable this
> when you're confident in the setup. For dev/iteration, the current config is fine.

---

### P1-1: Explicit Deny-All NSG Rule

**File:** `main.tf` (line ~196)

**Problem:** Azure NSGs have an implicit deny-all rule at priority 65500, but an explicit
deny-all makes the intent clear and protects against misconfigurations (e.g., someone
adding a rule with a higher priority number that accidentally allows traffic).

**Fix:** Add to the NSG resource:

```hcl
security_rule {
  name                       = "Deny-All-Inbound"
  priority                   = 4096
  direction                  = "Inbound"
  access                     = "Deny"
  protocol                   = "*"
  source_port_range          = "*"
  destination_port_range     = "*"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}
```

---

### P1-2: Nginx Rate Limiting

**File:** `templates/nginx.conf`

**Problem:** No `limit_req` is configured. The dashboard is publicly reachable (albeit
behind Basic Auth + IP lock). Without rate limiting, brute-force attempts against Basic
Auth are possible if the NSG IP restriction is ever relaxed.

**Fix:** Add rate limiting:

```nginx
# At the top of the file (outside server blocks):
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

# Inside the location / block:
location / {
    limit_req zone=api burst=20 nodelay;
    # ... existing proxy_pass config ...
}
```

---

### P1-3: Token Exposure in `clone-repo.sh`

**File:** `templates/clone-repo.sh` (line ~63)

**Problem:** The GitHub PAT is passed via `git -c "http....extraheader=AUTHORIZATION: Bearer $GITHUB_TOKEN"`.
While better than embedding the token in the URL, the token still appears in the process
list (`ps aux`) during the clone operation.

**Fix:** Use `GIT_ASKPASS` or a credential helper instead:

```bash
if [ -n "$GITHUB_TOKEN" ]; then
    export GIT_ASKPASS="$WORK_DIR/.git-askpass-helper.sh"
    printf '#!/bin/bash\necho "%s"\n' "$GITHUB_TOKEN" > "$GIT_ASKPASS"
    chmod 700 "$GIT_ASKPASS"
    git clone -- "$REPO_URL"
    rm -f "$GIT_ASKPASS"
else
    git clone -- "$REPO_URL"
fi
```

---

### P1-4: Terraform State Contains Secrets

**File:** `main.tf` / project-level

**Problem:** The generated admin password and any provided secrets end up in
`terraform.tfstate` (local file, plaintext JSON). The `.gitignore` prevents committing it,
but it remains on disk unencrypted.

**Fix:** Use an Azure Storage Account backend with encryption:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "openclaw.tfstate"
  }
}
```

Or at minimum, use Terraform 1.10+ `ephemeral` variables for secrets that don't need
to persist in state.

---

### P1-5: Azure Resource Tags

**File:** `main.tf`

**Problem:** No Azure resource has tags. Tags are essential for cost tracking, environment
identification, and resource management.

**Fix:** Add a `locals` block and apply tags to all resources:

```hcl
locals {
  common_tags = {
    project     = "openclaw"
    environment = "dev"
    managed_by  = "terraform"
  }
}

# Then on each resource:
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Repeat for: vnet, nsg, public_ip, nic, key_vault, vm
```

---

### P2-1: VM Image Version Pinning

**File:** `main.tf` (line ~321)

**Problem:** `version = "latest"` in `source_image_reference` can cause unexpected diffs
on `terraform plan` when Canonical publishes a new image. Terraform may want to recreate
the VM.

**Fix:** Either pin a specific version or add a lifecycle rule:

```hcl
# Option A: Pin version
source_image_reference {
  publisher = "Canonical"
  offer     = "ubuntu-24_04-lts"
  sku       = "server"
  version   = "24.04.202501150"  # Pin to a specific version
}

# Option B: Ignore changes
lifecycle {
  ignore_changes = [source_image_reference[0].version]
}
```

---

### P2-2: Cloud-Init `final_message`

**File:** `cloud-init.yml`

**Problem:** No `final_message` configured. Makes debugging cloud-init completion harder.

**Fix:** Add at the end of the file:

```yaml
final_message: |
  cloud-init finished at $TIMESTAMP, after $UPTIME seconds.
  OpenClaw VM provisioning complete.
```

---

### P2-3: `deploy.sh` — Show Plan Before Apply

**File:** `deploy.sh` (line ~108)

**Problem:** The deploy script runs `terraform apply -auto-approve` without showing the
user what will be created/changed first. In an interactive wrapper, this is unexpected.

**Fix:** Run `terraform plan` first, then ask for confirmation:

```bash
# Step 4: Show plan
step 4 "Planning Terraform changes..."
terraform plan $(ALL_TF_VARS) -out=tfplan
echo ""
read -rp "  Apply these changes? (yes/no): " APPLY_CONFIRM
if [[ "$APPLY_CONFIRM" != "yes" ]]; then
    warn "Aborted."
    rm -f tfplan
    exit 0
fi

# Step 5: Apply
step 5 "Applying Terraform configuration..."
terraform apply tfplan
rm -f tfplan
```

---

### P2-4: `start.sh` — Health Check Timeout

**File:** `templates/start.sh` (line ~153)

**Problem:** `curl -sf http://localhost:18789/` has no `--max-time` flag. If the port is
open but the service hangs, curl could block indefinitely.

**Fix:**

```bash
while ! curl -sf --max-time 2 http://localhost:18789/ >/dev/null 2>&1; do
```

---

### P2-5: Additional Systemd Hardening

**File:** `templates/openclaw.service`

**Problem:** Some additional systemd hardening options are not enabled.

**Fix:** Add (Node.js compatible options only):

```ini
# Additional hardening (safe for Node.js)
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
```

> **Warning:** Do NOT add `MemoryDenyWriteExecute=true` — it is incompatible with Node.js
> because V8's JIT compiler requires writable+executable memory pages.

---

### P2-6: Makefile Complex Targets

**File:** `Makefile` (lines ~189-220)

**Problem:** The `devices-list` and `approve-device` targets contain complex multi-line
shell logic that is hard to read and maintain in a Makefile.

**Suggestion:** Extract into a separate `templates/devices.sh` helper script and call
it from Make targets instead.

---

## Summary Table

| ID | Priority | Issue | File |
|----|----------|-------|------|
| P0-1 | **High** | Key Vault retry logic in start.sh | `templates/start.sh` |
| P0-2 | **High** | Key Vault purge protection (prod) | `main.tf` |
| P1-1 | Medium | Explicit NSG deny-all rule | `main.tf` |
| P1-2 | Medium | Nginx rate limiting | `templates/nginx.conf` |
| P1-3 | Medium | Token exposure in clone-repo.sh | `templates/clone-repo.sh` |
| P1-4 | Medium | Terraform state encryption | `main.tf` |
| P1-5 | Medium | Azure resource tags | `main.tf` |
| P2-1 | Low | VM image version pinning | `main.tf` |
| P2-2 | Low | Cloud-init `final_message` | `cloud-init.yml` |
| P2-3 | Low | deploy.sh: show plan before apply | `deploy.sh` |
| P2-4 | Low | start.sh: health check timeout | `templates/start.sh` |
| P2-5 | Low | Additional systemd hardening | `templates/openclaw.service` |
| P2-6 | Low | Makefile complex targets | `Makefile` |

---

## Next Steps

1. Decide which findings to implement (P0s recommended first)
2. For production: prioritize P0-2 (purge protection) and P1-4 (remote state)
3. For immediate reliability: prioritize P0-1 (Key Vault retry)
4. Run validation after changes: `make fmt && make validate && bash -n templates/start.sh`
