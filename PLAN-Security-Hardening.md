# Konsolidierter Security & Hardening Plan

Stand: 2026-02-20 — Zusammenfassung aus `TODO-security-hardening.md` (abgeschlossen),
bisherigem `PLAN.md` (offen) und neuem Security-Audit.

---

## Bereits umgesetzt (aus TODO-security-hardening.md)

| # | Thema | Status |
|---|-------|--------|
| A | Docker daemon.json mit Log-Rotation | DONE |
| B | Unattended-Upgrades (automatische Security-Patches) | DONE |
| C | fail2ban für SSH | DONE |
| D | Erweiterte systemd-Hardening (ProtectSystem, ProtectHome etc.) | DONE |
| E | System-Tools für Debugging (htop, tmux, etc.) | DONE |
| F | .bash_profile für Login-Shells | DONE |
| G | ipify.org Fallback (IP-Erkennung) | DONE |

---

## Offene Punkte — nach Priorität

### KRITISCH

#### 1. Terraform State in Remote Encrypted Backend

**Problem:** `terraform.tfstate` und `terraform.tfstate.backup` liegen lokal im Klartext
und enthalten: Admin-Passwort, SSH-Key, Azure Subscription-ID, base64-encodete cloud-init-
Daten. Die Dateien sind `0644` (world-readable). Jeder Benutzer auf dem Entwicklerrechner
kann sie lesen.

**Betroffene Dateien:**
- `main.tf` — Backend-Block hinzufügen
- Neues Setup-Script oder Doku für Azure Storage Account

**Änderung main.tf** — Backend-Konfiguration am Anfang der Datei (vor `provider "azurerm"`):

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "openclaw-tfstate-rg"
    storage_account_name = "openclawstate"
    container_name       = "tfstate"
    key                  = "openclaw.tfstate"
  }
}
```

**Voraussetzungen (einmalig per CLI):**

```bash
# Resource Group + Storage Account für State
az group create -n openclaw-tfstate-rg -l westeurope
az storage account create -n openclawstate -g openclaw-tfstate-rg -l westeurope \
    --sku Standard_LRS --encryption-services blob --min-tls-version TLS1_2
az storage container create -n tfstate --account-name openclawstate

# State migrieren
terraform init -migrate-state
```

**Sofort-Fix** (bis Remote-Backend steht):

```bash
chmod 600 terraform.tfstate terraform.tfstate.backup
```

---

#### 2. deploy.sh: Plan vor Apply zeigen

**Problem:** `deploy.sh` macht `terraform apply -auto-approve` ohne Plan-Review. Eine
Fehlkonfiguration könnte Key Vault zerstören und alle Secrets unwiderruflich löschen
(wegen `purge_soft_delete_on_destroy = true`).

**Betroffene Dateien:**
- `deploy.sh` — Step 4 ersetzen
- `.gitignore` — `tfplan` und `crash.log` hinzufügen

**Änderung deploy.sh Step 4 (Zeilen 97-102 ersetzen):**

```bash
# -- Step 4: Terraform plan + apply --
step 4 "Planning infrastructure changes..."
echo ""
terraform plan -out=tfplan -input=false
echo ""

log "  Plan complete. Review the changes above."
echo ""
read -rp "  Apply these changes? (yes/no): " APPLY_CONFIRM
echo ""

if [[ "$APPLY_CONFIRM" != "yes" ]]; then
    warn "Aborted. No resources were created."
    rm -f tfplan
    exit 0
fi

log "  Applying Terraform plan..."
terraform apply tfplan
rm -f tfplan
log "  Terraform apply completed"
```

**Zusätzlich deploy.sh Zeile 49** — jq-Check verbessern:

```bash
# Vorher:
TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)

# Nachher:
if command -v jq &>/dev/null; then
    TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1)
else
    TERRAFORM_VERSION=$(terraform version | head -1)
fi
```

**Änderung .gitignore** — hinzufügen:

```
tfplan
crash.log
crash.*.log
```

---

### HOCH

#### 3. Pipe-to-Shell in cloud-init ersetzen

**Problem:** Drei `curl | sh`-Aufrufe ohne Integritätsprüfung:

```bash
curl -fsSL https://get.docker.com | sh                      # Zeile 138
curl -sL https://aka.ms/InstallAzureCLIDeb | bash            # Zeile 145
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -    # Zeile 148
```

Supply-Chain-Angriff möglich wenn ein Upstream-Script kompromittiert wird. Keine
Versionspinning, keine GPG-Signaturprüfung.

**Betroffene Datei:** `cloud-init.yml`

**Änderung — Docker Installation (Zeile 138 ersetzen):**

```yaml
  # Docker — via official apt repository (version-pinned)
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update -qq
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**Änderung — Azure CLI (Zeile 145 ersetzen):**

```yaml
  # Azure CLI — via official apt repository (GPG-verified)
  - curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
  - chmod a+r /etc/apt/keyrings/microsoft.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/azure-cli.list
  - apt-get update -qq
  - apt-get install -y azure-cli
```

**Änderung — Node.js (Zeile 148 ersetzen):**

```yaml
  # Node.js 22 — via official apt repository (GPG-verified)
  - curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  - apt-get update -qq
  - apt-get install -y nodejs
```

---

#### 4. Secrets nicht als CLI-Argumente übergeben

**Problem:** Mehrere Stellen exponieren Secrets via Kommandozeile, sichtbar in
`ps aux` / `/proc/<pid>/cmdline`:

| Datei | Zeile | Problem |
|-------|-------|---------|
| `templates/start.sh` | 131 | `--gateway-password "$ADMIN_PASS"` |
| `templates/start.sh` | 98 | `echo "$ADMIN_PASS" \| htpasswd` |
| `templates/clone-repo.sh` | 61 | Token in `git -c` Argument |

**Betroffene Dateien:**
- `templates/start.sh`
- `templates/clone-repo.sh`

**Änderung start.sh Zeile 98** — `echo` durch `printf` ersetzen:

```bash
# Vorher:
echo "$ADMIN_PASS" | htpasswd -ci "$WORK_DIR/nginx/.htpasswd" "$ADMIN_USER"

# Nachher:
printf '%s' "$ADMIN_PASS" | htpasswd -ci "$WORK_DIR/nginx/.htpasswd" "$ADMIN_USER"
```

**Änderung start.sh Zeilen 117-132** — Passwort über Umgebungsvariable statt CLI:

```bash
# Vorher:
"$OPENCLAW_BIN" onboard \
    ...
    --gateway-password "$ADMIN_PASS" \
    --json >/dev/null

# Nachher:
OPENCLAW_GATEWAY_PASSWORD="$ADMIN_PASS" "$OPENCLAW_BIN" onboard \
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
    --json >/dev/null
```

> **Hinweis:** Prüfen ob OpenClaw die Env-Variable `OPENCLAW_GATEWAY_PASSWORD`
> unterstützt. Falls nicht, ist `--gateway-password` mit Prozess-Lebensdauer < 1s
> akzeptabel aber dokumentiert als Known Limitation.

**Änderung clone-repo.sh Zeile 61** — Credential Helper statt CLI-Argument:

```bash
# Vorher:
git -c "http.https://github.com/.extraheader=AUTHORIZATION: Bearer $GITHUB_TOKEN" clone -- "$REPO_URL"

# Nachher:
GIT_ASKPASS_SCRIPT=$(mktemp)
printf '#!/bin/sh\necho "%s"\n' "$GITHUB_TOKEN" > "$GIT_ASKPASS_SCRIPT"
chmod 700 "$GIT_ASKPASS_SCRIPT"
GIT_ASKPASS="$GIT_ASKPASS_SCRIPT" git clone -- "$(echo "$REPO_URL" | sed "s|https://github.com|https://x-access-token@github.com|")"
rm -f "$GIT_ASKPASS_SCRIPT"
```

---

#### 5. Nginx Rate Limiting (Brute-Force-Schutz)

**Problem:** Kein Rate Limiting auf Basic Auth Endpoint. Wenn die NSG-IP kompromittiert
ist oder mehrere Personen den Zugang teilen, gibt es keinen Schutz gegen Brute-Force.

**Betroffene Datei:** `templates/nginx.conf`

**Änderung:** Vor dem ersten `server {}` Block einfügen:

```nginx
# Rate limiting — protect Basic Auth from brute-force attacks
limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=5r/s;
```

Im HTTPS server block nach `auth_basic_user_file` einfügen:

```nginx
    # Apply rate limiting (returns 429 Too Many Requests when exceeded)
    limit_req zone=auth_limit burst=10 nodelay;
    limit_req_status 429;
```

---

#### 6. Nginx SSL Hardening

**Problem:** Fehlende TLS Best Practices — keine Server Cipher Preference, kein Session
Cache, Session Tickets aktiv.

**Betroffene Datei:** `templates/nginx.conf`

**Änderung:** Nach der `ssl_ciphers` Zeile hinzufügen:

```nginx
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
```

| Directive | Zweck |
|---|---|
| `ssl_prefer_server_ciphers on` | Server wählt den stärksten gemeinsamen Cipher |
| `ssl_session_cache shared:SSL:10m` | Shared Session Cache zwischen Workers (schnellere Reconnects) |
| `ssl_session_timeout 10m` | Sessions werden nach 10 Minuten invalidiert |
| `ssl_session_tickets off` | Verhindert Forward Secrecy Bypass durch Session Tickets |

---

#### 7. Self-signed Zertifikat: Stärkerer Key + Renewal-Hinweis

**Problem:** RSA 2048-bit (Minimum), kein Upgrade-Pfad zu Let's Encrypt, kein
Renewal-Mechanismus (365 Tage, dann abgelaufen).

**Betroffene Datei:** `cloud-init.yml` (Zeilen 177-182)

**Änderung — Stärkerer Key:**

```bash
# Vorher:
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \

# Nachher:
openssl req -x509 -nodes -days 365 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
```

ECDSA P-256 ist schneller und sicherer als RSA 2048. Equivalent zu RSA 3072+.

**Optional (Zukunft):** Let's Encrypt Integration mit certbot. Erfordert:
- DNS-Eintrag auf die öffentliche IP
- Port 80 offen für ACME Challenge (aktuell nur 443 in NSG)
- certbot certonly --standalone oder --nginx

---

#### 8. Docker Compose Health Check für Nginx

**Problem:** Kein Health Check für den Nginx Container. Docker erkennt nicht ob Nginx
tatsächlich Traffic ausliefert.

**Betroffene Datei:** `templates/docker-compose.yml`

**Änderung:** Nach dem `security_opt` Block einfügen:

```yaml
    healthcheck:
      test: ["CMD-SHELL", "wget --no-check-certificate --server-response -qO /dev/null https://localhost/ 2>&1 | grep -q 'HTTP/' || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

> **Hinweis:** Prüft ob Nginx eine HTTP-Antwort gibt (auch 401 gilt als gesund = Nginx
> läuft). `wget` ist in `nginx:alpine` verfügbar, `curl` nicht.

---

#### 9. Hardcodierten Model-Namen entfernen

**Problem:** `start.sh` Zeile 133 setzt bei jedem Start das Model auf
`anthropic/claude-sonnet-4-5`, egal was in `openclaw.json` steht.

**Betroffene Datei:** `templates/start.sh`

**Änderung:** Zeile 133 entfernen:

```bash
# DIESE ZEILE ENTFERNEN:
"$OPENCLAW_BIN" config set agents.defaults.model.primary "anthropic/claude-sonnet-4-5" >/dev/null
```

Das Model wird durch `templates/openclaw.json` definiert.

---

#### 10. Dokumentation korrigieren (README.md + AGENTS.md)

**Problem:** README sagt "OpenClaw running in a container" — tatsächlich läuft es als
systemd Host-Prozess. AGENTS.md spricht von "Two containers". Falsche Architektur-
Dokumentation führt zu falschen Security-Annahmen.

**Betroffene Dateien:**
- `README.md` — Zeile 3-4 + Architektur-Diagramm
- `AGENTS.md` — "Two containers" Zeile

**Änderung README.md Zeile 3-4:**

```
# Vorher:
Deploys an Ubuntu 24.04 VM on Azure with Docker, OpenClaw running in a container,
Nginx reverse proxy (Basic Auth + SSL), Key Vault for secrets, and auto-shutdown.

# Nachher:
Deploys an Ubuntu 24.04 VM on Azure with OpenClaw as a systemd host process,
Nginx reverse proxy in Docker (Basic Auth + SSL), Key Vault for secrets, and auto-shutdown.
```

**Änderung Architektur-Diagramm:**

```
│  ├── Docker              │
│  │   └── Nginx (SSL)     │
│  │       └► :443/:80     │
│  ├── OpenClaw (systemd)  │
│  │   ├── Config          │
│  │   └── Workspace       │
```

**Änderung AGENTS.md:**

```
# Vorher:
Two containers: `openclaw-nginx` (...) and `openclaw-github-agent` (...)

# Nachher:
One container (`openclaw-nginx` for SSL + Basic Auth) plus the OpenClaw systemd service (port 18789)
```

---

### MITTEL

#### 11. Terraform Variable Validation

**Problem:** Keine `validation {}` Blöcke. Ungültige Werte werden erst bei `apply`
erkannt statt bei `plan`.

**Betroffene Datei:** `main.tf`

**Änderung:**

```hcl
variable "location" {
  default     = "westeurope"
  description = "Azure region for all resources"
  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region name (lowercase, no spaces)."
  }
}

variable "vm_size" {
  default     = "Standard_B2s"
  description = "VM size (2 vCPU, 4 GB RAM)"
  validation {
    condition     = can(regex("^Standard_", var.vm_size))
    error_message = "VM size must start with 'Standard_'."
  }
}

variable "auto_shutdown_time" {
  default     = "2200"
  description = "Daily auto-shutdown time in UTC (HHMM)"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.auto_shutdown_time))
    error_message = "Auto-shutdown time must be in HHMM format (0000-2359)."
  }
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Path to the SSH public key"
  validation {
    condition     = can(regex("\\.(pub|pem)$", var.ssh_public_key_path))
    error_message = "SSH public key path must end in .pub or .pem."
  }
}
```

---

#### 12. systemd Resource Limits

**Problem:** Kein `MemoryMax` oder `CPUQuota`. OpenClaw kann beliebigen Code ausführen —
ein Runaway-Prozess kann die VM lahmlegen inklusive SSH.

**Betroffene Datei:** `templates/openclaw.service`

**Änderung:** Im `[Service]` nach `ReadWritePaths` hinzufügen:

```ini
# Resource limits — prevent runaway processes from exhausting VM resources
MemoryMax=3G
MemoryHigh=2G
CPUQuota=150%
TasksMax=256
```

| Limit | Wert | Begründung |
|---|---|---|
| `MemoryMax` | 3G | Hard Limit. Standard_B2s hat 4 GB — 1 GB für OS/Docker/SSH |
| `MemoryHigh` | 2G | Soft Limit. Memory Pressure, kein Kill |
| `CPUQuota` | 150% | 1.5 von 2 Cores — 0.5 bleibt für System |
| `TasksMax` | 256 | Fork-Bomb-Schutz |

---

#### 13. fail2ban für Nginx Basic Auth

**Problem:** fail2ban schützt nur SSH. Kein Brute-Force-Schutz auf OS-Ebene für das
Web-Dashboard. Zusammen mit Rate Limiting (Punkt 5) = Defense-in-Depth.

**Betroffene Dateien:**
- `cloud-init.yml` — `nginx-http-auth` Jail + Log-Verzeichnis
- `templates/docker-compose.yml` — Log-Volume mounten
- `templates/nginx.conf` — Explizite Log-Pfade

**Änderung cloud-init.yml jail.local:**

```yaml
      [DEFAULT]
      bantime = 3600
      findtime = 600
      maxretry = 5
      backend = auto

      [sshd]
      enabled = true
      port = ssh
      filter = sshd
      backend = systemd

      [nginx-http-auth]
      enabled = true
      port = http,https
      filter = nginx-http-auth
      logpath = /home/${admin_username}/openclaw/nginx/logs/error.log
      backend = auto
```

**Änderung docker-compose.yml volumes:**

```yaml
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/.htpasswd:/etc/nginx/.htpasswd:ro
      - ./nginx/logs:/var/log/nginx
```

**Änderung nginx.conf** — im HTTPS server block:

```nginx
    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;
```

**Änderung cloud-init.yml runcmd** (vor `chown -R`):

```yaml
  - mkdir -p /home/${admin_username}/openclaw/nginx/logs
```

> **Hinweis:** Der `nginx-http-auth` Filter ist in fail2ban standardmäßig enthalten.
> Er erkennt `"no user/password was provided"` und `"user .* was not found"` Patterns
> in den Nginx Error Logs.

---

#### 14. Key Vault Soft-Delete beibehalten

**Problem:** `purge_soft_delete_on_destroy = true` löscht die Key Vault permanent bei
`terraform destroy`. Kein Recovery-Window bei versehentlichem Destroy.

**Betroffene Datei:** `main.tf`

**Änderung:**

```hcl
# Vorher:
purge_soft_delete_on_destroy = true

# Nachher:
purge_soft_delete_on_destroy = false
```

Konsequenz: Nach `terraform destroy` bleibt die Key Vault 90 Tage in Soft-Delete.
Ein erneutes `terraform apply` mit gleichem Namen schlägt fehl, bis die Vault
recovered oder endgültig gelöscht wird. Workaround:

```bash
# Vault recovern (Secrets bleiben erhalten):
az keyvault recover --name <vault-name>
# Oder endgültig löschen:
az keyvault purge --name <vault-name>
```

---

#### 15. CSP verschärfen (unsafe-inline/unsafe-eval)

**Problem:** `script-src 'unsafe-inline' 'unsafe-eval'` in der Content-Security-Policy
ermöglicht XSS wenn eine Injection-Lücke existiert.

**Betroffene Datei:** `templates/nginx.conf` (Zeile 31)

**Änderung:** Testen ob das OpenClaw Dashboard ohne `unsafe-eval` funktioniert:

```nginx
# Schritt 1: unsafe-eval entfernen, unsafe-inline durch nonce ersetzen (ideal)
# Schritt 2: Falls Dashboard bricht, mindestens unsafe-eval entfernen
# Schritt 3: Falls beides benötigt wird, als Known Limitation dokumentieren

# Minimale Verbesserung (unsafe-eval entfernen falls möglich):
Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' wss: ws:; frame-ancestors 'none'";
```

> **Test erforderlich:** OpenClaw Dashboard laden und in der Browser-Console
> prüfen ob CSP-Violations auftreten.

---

#### 16. Admin-Username nicht loggen

**Problem:** `start.sh` loggt den Admin-Username im Klartext. Erleichtert Angriffe
wenn jemand Zugriff auf Logs erhält (nur noch Passwort fehlt).

**Betroffene Datei:** `templates/start.sh` (Zeile 69)

**Änderung:**

```bash
# Vorher:
log "  admin-username loaded: $ADMIN_USER"

# Nachher:
log "  admin-username loaded (${#ADMIN_USER} chars)"
```

---

#### 17. OpenClaw Gateway auf localhost binden

**Problem:** Gateway bindet auf `0.0.0.0` (`--gateway-bind lan`). Docker-Container
können direkt auf Port 18789 zugreifen — ohne Basic Auth (die nur auf Nginx-Ebene ist).

**Betroffene Dateien:**
- `templates/start.sh` — `--gateway-bind` ändern
- `templates/openclaw.json` — `bind` ändern
- `templates/docker-compose.yml` — `extra_hosts` hinzufügen

**Änderung start.sh:**

```bash
# Vorher:
--gateway-bind lan \

# Nachher:
--gateway-bind local \
```

**Änderung openclaw.json:**

```json
"bind": "local"
```

**Änderung docker-compose.yml** — Nginx muss den Host erreichen:

```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**Änderung nginx.conf** — Upstream ändern:

```nginx
# Vorher:
proxy_pass http://172.17.0.1:18789;

# Nachher:
proxy_pass http://host.docker.internal:18789;
```

> **Hinweis:** `host.docker.internal` ist seit Docker 20.10 auf Linux verfügbar
> mit `host-gateway`. Muss getestet werden.

---

#### 18. Docker Image Digest-Pinning

**Problem:** `nginx:alpine` ist ein mutable Tag. Supply-Chain-Angriff möglich.

**Betroffene Dateien:**
- `templates/docker-compose.yml`
- `cloud-init.yml`

**Änderung:**

```yaml
# Vorher:
image: nginx:alpine

# Nachher (aktuellen Digest ermitteln mit `docker pull nginx:alpine && docker inspect --format='{{index .RepoDigests 0}}' nginx:alpine`):
image: nginx:alpine@sha256:<aktueller-digest>
```

> **Wartung:** Digest bei jedem Update manuell aktualisieren, oder Renovate/Dependabot
> einrichten.

---

#### 19. Lokale .env Dateiberechtigungen

**Problem:** Die lokale `.env`-Datei (auf dem Entwicklerrechner) ist `0644`. Sobald
jemand `GITHUB_TOKEN` oder `ANTHROPIC_API_KEY` einträgt, kann jeder lokale Benutzer
diese lesen.

**Betroffene Dateien:**
- `.env.example` — Hinweis hinzufügen
- `deploy.sh` — Berechtigungsprüfung

**Änderung .env.example** — Kommentar hinzufügen:

```bash
# IMPORTANT: After filling in values, restrict permissions:
#   chmod 600 .env
```

**Änderung deploy.sh** — nach dem `source .env` Block:

```bash
# Warn if .env has overly permissive permissions
if [ -f ".env" ]; then
    ENV_PERMS=$(stat -f '%A' .env 2>/dev/null || stat -c '%a' .env 2>/dev/null || echo "")
    if [ -n "$ENV_PERMS" ] && [ "$ENV_PERMS" != "600" ] && [ "$ENV_PERMS" != "400" ]; then
        warn ".env has permissions $ENV_PERMS (should be 600). Run: chmod 600 .env"
    fi
fi
```

---

#### 20. Gzip Kompression

**Problem:** Dashboard-Assets werden unkomprimiert ausgeliefert. Kein direktes
Sicherheitsproblem, aber erhöht Ladezeiten und Bandbreite.

**Betroffene Datei:** `templates/nginx.conf`

**Änderung:** Vor dem ersten `server {}` Block:

```nginx
# Gzip compression for static assets
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_min_length 1024;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml;
```

---

### NIEDRIG

#### 21. Sichere Dateilöschung (shred)

**Problem:** `rm -f` in `stop.sh` lässt Secrets auf Disk physisch wiederherstellbar.

**Betroffene Datei:** `templates/stop.sh`

**Änderung:** Beide `rm -f` Aufrufe ersetzen:

```bash
# .env cleanup
if [ -f "$WORK_DIR/.env" ]; then
    if command -v shred &>/dev/null; then
        shred -u "$WORK_DIR/.env"
    else
        rm -f "$WORK_DIR/.env"
    fi
    log "  Removed .env file (secrets cleaned up)"
else
    log "  No .env file found (already clean)"
fi

# .htpasswd cleanup
if [ -f "$WORK_DIR/nginx/.htpasswd" ]; then
    if command -v shred &>/dev/null; then
        shred -u "$WORK_DIR/nginx/.htpasswd"
    else
        rm -f "$WORK_DIR/nginx/.htpasswd"
    fi
    log "  Removed htpasswd file"
fi
```

> **Hinweis:** `shred` ist in GNU coreutils enthalten (Ubuntu 24.04 Standard). Der
> `command -v` Check ist ein Safety Net. `-u` bedeutet "shred then unlink (delete)".

---

#### 22. Dedicated Service-User + Scoped Sudo

**Problem:** `clawadmin` wird für SSH und OpenClaw-Prozess verwendet. Kompromittierung
von OpenClaw = volle SSH-Admin-Rechte. Außerdem hat `clawadmin` volle sudo-Rechte.

**Betroffene Dateien:**
- `cloud-init.yml` — User `openclaw` anlegen
- `templates/openclaw.service` — User ändern
- `templates/start.sh` — Verzeichnisrechte

**Aufwand:** Mittel — erfordert Anpassung der Verzeichnisrechte und Tests.

**Scoped Sudo (Abhängigkeit):** Falls ein dedizierter Service-User eingeführt wird,
sollte dieser nur eingeschränkte sudo-Rechte bekommen (z.B. nur `systemctl` für den
openclaw-Service). Referenz: Ansible-Playbook `tasks/user.yml:46-90`.

---

#### 23. Makefile: Bare `export` entfernen

**Problem:** `export` ohne Variablennamen exportiert ALLE Make-Variablen an Subprozesse.

**Betroffene Datei:** `Makefile` (Zeile 27)

**Änderung:**

```makefile
# Vorher:
export

# Nachher (nur die benötigten Variablen exportieren):
export TF_VAR_github_pat TF_VAR_anthropic_key TF_VAR_allowed_ip
```

---

#### 24. WebSocket Proxy-Timeout reduzieren

**Problem:** `proxy_read_timeout 86400` (24h) für WebSocket-Verbindungen vergrößert
das Fenster für Session-Hijacking.

**Betroffene Datei:** `templates/nginx.conf` (Zeile 54)

**Änderung:**

```nginx
# Vorher:
proxy_read_timeout 86400;

# Nachher (4 Stunden — genug für lange Sessions, begrenzt Hijacking-Fenster):
proxy_read_timeout 14400;
```

---

## Implementierungsreihenfolge

| Commit | Punkte | Risiko | Kategorie |
|--------|--------|--------|-----------|
| 1 | Sofort-Fix: `chmod 600 terraform.tfstate*` | Keins | KRITISCH |
| 2 | deploy.sh: Plan-Review + jq-Check (#2) | Niedrig | KRITISCH |
| 3 | Dokumentation korrigieren (#10) | Keins | HOCH |
| 4 | Nginx Security: Rate Limiting + SSL + Gzip (#5, #6, #20) | Niedrig | HOCH/MITTEL |
| 5 | Docker Health Check (#8) | Niedrig | HOCH |
| 6 | Secrets nicht als CLI-Args (#4) + Username nicht loggen (#16) | Niedrig | HOCH/MITTEL |
| 7 | Model-Name entfernen (#9) | Niedrig | HOCH |
| 8 | Terraform Variable Validation (#11) | Niedrig | MITTEL |
| 9 | systemd Resource Limits (#12) | Mittel* | MITTEL |
| 10 | fail2ban Nginx Auth + Log-Volume (#13) | Mittel* | MITTEL |
| 11 | Gateway auf localhost binden (#17) | Mittel* | MITTEL |
| 12 | Key Vault Soft-Delete (#14) | Niedrig | MITTEL |
| 13 | CSP verschärfen (#15) — nach Test | Mittel* | MITTEL |
| 14 | Lokale .env Permissions (#19) | Keins | MITTEL |
| 15 | Docker Image Pinning (#18) | Niedrig | MITTEL |
| 16 | Pipe-to-Shell ersetzen (#3) | Mittel* | HOCH |
| 17 | Self-signed Cert: ECDSA P-256 (#7) | Mittel* | HOCH |
| 18 | Sichere Dateilöschung (#21) | Keins | NIEDRIG |
| 19 | Makefile bare export (#23) | Keins | NIEDRIG |
| 20 | WebSocket Timeout (#24) | Niedrig | NIEDRIG |
| 21 | Terraform Remote Backend (#1) | Hoch** | KRITISCH |
| 22 | Dedicated Service-User (#22) | Hoch** | NIEDRIG |

*Mittel = erfordert Tests auf der VM nach Redeploy
**Hoch = erfordert Infrastruktur-Setup oder größere Architekturänderung

> **Punkt 16-17 spät im Plan:** Pipe-to-Shell und Cert-Änderungen erfordern VM-Neuaufbau
> (cloud-init wird nur beim ersten Boot ausgeführt). Besser als Batch zusammen mit
> anderen cloud-init-Änderungen deployen.
>
> **Punkt 21 zuletzt:** Remote Backend erfordert einmalige Azure-Infrastruktur und
> State-Migration. Kann unabhängig von allen anderen Änderungen gemacht werden.

---

## Verifikation

Nach allen Änderungen:

```bash
# Lokal
make fmt && make validate && make plan
bash -n deploy.sh templates/start.sh templates/stop.sh templates/clone-repo.sh

# Permissions prüfen
stat -f '%A %N' .env terraform.tfstate* 2>/dev/null

# Nach Redeploy (make redeploy-vm + ~5 min warten + make openclaw-start)
docker exec openclaw-nginx nginx -t                                          # Nginx Config OK
docker inspect --format='{{.State.Health.Status}}' openclaw-nginx            # "healthy"
sudo fail2ban-client status                                                  # Alle Jails aktiv
sudo fail2ban-client status nginx-http-auth                                  # HTTP Auth Jail
systemctl show openclaw | grep -E 'MemoryMax|MemoryHigh|CPUQuota|TasksMax'  # Limits gesetzt

# Rate Limiting testen (nach ~15 Requests sollte 429 kommen)
for i in $(seq 1 20); do curl -sk -o /dev/null -w "%{http_code}\n" https://localhost/; done

# Gzip testen
curl -sk -H "Accept-Encoding: gzip" -I https://localhost/ | grep -i content-encoding

# Gateway-Binding prüfen (sollte nur auf 127.0.0.1 lauschen)
ss -tlnp | grep 18789

# CSP testen (Browser Console auf Violations prüfen)
# Dashboard öffnen und F12 > Console
```
