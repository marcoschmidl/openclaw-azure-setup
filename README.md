# OpenClaw GitHub Agent — Azure VM Deployment

Deployt eine Ubuntu 24.04 VM auf Azure mit Docker, OpenClaw im Container,
Nginx Reverse Proxy (Basic Auth + SSL), Key Vault fuer Secrets und Auto-Shutdown.

## Architektur

```
Browser / SSH                       Azure
──────────────                ──────────────────────────
                              ┌─ Resource Group ────────┐
https://<fqdn>  ──────────►  │  VM (Ubuntu 24.04)      │
  (Basic Auth)                │  ├── Docker             │
                              │  │   ├── Nginx (SSL)    │
ssh user@<fqdn> ──────────►  │  │   │   └► :443/:80    │
  (Key oder Passwort)         │  │   └── OpenClaw       │
                              │  │       ├── Config     │
                              │  │       └── Workspace  │
                              │  └── Azure CLI          │
                              │                         │
                              │  Key Vault              │
                              │  ├── github-pat    (opt)│
                              │  ├── anthropic-key (opt)│
                              │  ├── admin-username     │
                              │  └── admin-password     │
                              │                         │
                              │  Public IP + DNS Label  │
                              │  <label>.westeurope.    │
                              │    cloudapp.azure.com   │
                              │                         │
                              │  NSG: SSH+HTTPS nur von │
                              │       deiner IP         │
                              │                         │
                              │  Auto-Shutdown 22:00    │
                              └─────────────────────────┘
```

## Quickstart

```bash
# 1. Secrets konfigurieren (optional)
cp .env.example .env
#    GITHUB_TOKEN und ANTHROPIC_API_KEY eintragen

# 2. Deployen
make deploy

# 3. OpenClaw auf der VM starten
make openclaw-start

# 4. Dashboard oeffnen
#    URL und Passwort aus make output bzw. make show-password
```

## Make Targets

```
make help               Alle Targets anzeigen

Deployment:
  make deploy           Infrastruktur deployen (terraform apply)
  make plan             Aenderungen anzeigen (Dry-Run)
  make destroy          Alle Ressourcen loeschen

VM-Verwaltung:
  make start            VM starten
  make stop             VM stoppen (deallocate)
  make restart          VM neustarten
  make status           VM-Status anzeigen

Zugriff:
  make ssh              SSH-Verbindung zur VM
  make show-password    Admin-Passwort anzeigen
  make show-password-kv Passwort aus Key Vault abrufen

OpenClaw:
  make openclaw-start   OpenClaw + Nginx auf VM starten
  make openclaw-stop    OpenClaw + Nginx auf VM stoppen

Logs & Debugging:
  make logs             OpenClaw Container-Logs
  make logs-nginx       Nginx Container-Logs
  make docker-ps        Container-Status auf VM
  make cloud-init-status  Cloud-init Status
  make cloud-init-logs    Cloud-init Logs

Terraform:
  make output           Alle Terraform Outputs
  make fmt              Terraform formatieren
  make validate         Terraform validieren
```

## Deployment-Optionen

### Option A: Makefile (empfohlen)

```bash
cp .env.example .env       # Secrets eintragen (optional)
make deploy                # terraform init + apply
```

### Option B: deploy.sh (interaktiv)

```bash
./deploy.sh                # fragt nach Secrets interaktiv
```

### Option C: Terraform direkt

```bash
terraform init
terraform apply -var-file="secrets.tfvars"
```

> **Hinweis:** `GITHUB_TOKEN` und `ANTHROPIC_API_KEY` sind optional. Werden sie
> weggelassen, werden die Key Vault Secrets nicht erstellt. Das Admin-Passwort
> wird automatisch generiert.

## .env Datei

```bash
# .env (nicht committen!)
GITHUB_TOKEN=ghp_xxx
ANTHROPIC_API_KEY=sk-ant-xxx
```

Wird automatisch vom Makefile geladen und als Terraform-Variablen weitergereicht.

## Terraform Variablen

| Variable | Default | Beschreibung |
|---|---|---|
| `location` | `westeurope` | Azure Region |
| `vm_size` | `Standard_B2s` | VM Groesse (2 vCPU, 4 GB RAM) |
| `admin_username` | `clawadmin` | SSH + Dashboard Username |
| `admin_password` | *(auto-generiert)* | SSH + Dashboard Passwort |
| `github_pat` | *(leer)* | GitHub PAT (optional) |
| `anthropic_key` | *(leer)* | Anthropic API Key (optional) |
| `dns_label` | *(auto-generiert)* | DNS Label fuer Public IP |
| `allowed_ip` | *(auto-ermittelt)* | IP fuer SSH/HTTPS-Zugriff |
| `ssh_public_key_path` | `~/.ssh/id_rsa.pub` | Pfad zum SSH Public Key |
| `auto_shutdown_time` | `2200` | Auto-Shutdown (UTC) |

## Taeglicher Workflow

```bash
make start               # VM starten
make openclaw-start      # OpenClaw + Nginx starten
#    https://<fqdn> im Browser oeffnen
make openclaw-stop       # wenn fertig
make stop                # VM deallocaten (keine Compute-Kosten)
```

## Kosten

| Zustand | Kosten (ca.) |
|---|---|
| VM laeuft (Standard_B2s) | ~EUR 0.04/h |
| VM deallocated | ~EUR 1.50/Mo (nur Disk) |
| Key Vault | ~EUR 0.03/Mo |
| **Typisch: 4h/Tag Nutzung** | **~EUR 6.50/Mo** |

Auto-Shutdown um 22:00 UTC verhindert vergessene laufende VMs.

## Sicherheit

- **NSG**: SSH + HTTPS nur von deiner IP, alles andere blockiert
- **Basic Auth**: Dashboard per Nginx-Container mit Passwort geschuetzt
- **SSL**: Self-Signed Zertifikat auf Azure FQDN
- **Key Vault**: Secrets nie auf Disk, werden bei `start.sh` geladen und bei `stop.sh` geloescht
- **Managed Identity**: VM authentifiziert sich bei Key Vault ohne Credentials
- **Container-Isolation**: Nginx + OpenClaw laufen in Docker
- **Auto-Shutdown**: Failsafe gegen vergessene VMs
- **Dual Auth**: SSH per Key oder Passwort

## Dateien

| Datei | Beschreibung |
|---|---|
| `Makefile` | Build-Targets fuer alle Operationen |
| `main.tf` | Terraform-Konfiguration (gesamte Infrastruktur) |
| `cloud-init.yml` | VM-Provisioning Template (referenziert templates/) |
| `.env.example` | Vorlage fuer Secrets |
| `deploy.sh` | Interaktiver Wrapper fuer Terraform |
| `destroy.sh` | Loescht alle Ressourcen + Terraform State |
| `templates/docker-compose.yml` | Docker Compose: Nginx + OpenClaw Container |
| `templates/openclaw.json` | OpenClaw Agent-Konfiguration |
| `templates/nginx.conf` | Nginx Reverse Proxy (SSL + Basic Auth) |
| `templates/start.sh` | Laedt Key Vault Secrets, setzt htpasswd, startet Docker |
| `templates/stop.sh` | Stoppt Docker, loescht lokale Secrets |
| `templates/clone-repo.sh` | Klont GitHub Repos (optional mit PAT-Auth) |

## Konfiguration anpassen

### VM-Groesse aendern

```bash
make deploy EXTRA_TF_VARS='-var="vm_size=Standard_B2ms"'
```

### Anderes LLM-Modell

```bash
make ssh
# on the VM:
nano ~/openclaw/config/openclaw.json
# change "model": "claude-opus-4-6"  or  "gpt-4o"
```

### OpenClaw Agent Configuration (`templates/openclaw.json`)

The agent configuration is deployed to `~/.openclaw/openclaw.json` inside the
Docker container. It controls the agent's behavior, model, and tool permissions.

| Key | Description |
|---|---|
| `gateway.host` | Bind address (`0.0.0.0` — all interfaces, so Nginx can proxy) |
| `gateway.port` | Internal port (`18789` — only exposed inside Docker network) |
| `heartbeat.enabled` | Heartbeat check (`false` — not needed in single-VM setup) |
| `agents.default.model` | LLM model to use (e.g. `claude-sonnet-4-5-20250929`) |
| `agents.default.systemPrompt` | System prompt — enforces branch-based workflow |

**Tool permissions** (`agents.default.tools`):

| Tool | `ask` | Description |
|---|---|---|
| `terminal` | `true` | Shell commands require user confirmation |
| `git_commit` | `true` | Git commits require confirmation |
| `git_push` | `true` | Git pushes require confirmation |
| `filesystem_write` | `false` | File writes are auto-allowed |
| `filesystem_delete` | `true` | File deletions require confirmation |
| `filesystem_read` | `false` | File reads are auto-allowed |
| `web_search` | `false` | Web searches are auto-allowed |

> `"ask": true` means the agent will ask for user confirmation before executing.
> `"ask": false` means the tool runs automatically without prompting.

### NSG-Regel fuer neue IP

```bash
make deploy EXTRA_TF_VARS='-var="allowed_ip=NEUE.IP.ADRESSE"'
```

## Troubleshooting

```bash
make cloud-init-status   # Cloud-init Status pruefen
make cloud-init-logs     # Cloud-init Logs anzeigen
make docker-ps           # Container-Status
make logs                # OpenClaw Logs
make logs-nginx          # Nginx Logs
```

Auf der VM direkt:
```bash
docker exec openclaw-nginx nginx -t    # Nginx Config testen
curl -k https://localhost               # Dashboard lokal testen
az login --identity                     # Managed Identity pruefen
```

## Aufraeumen

```bash
make destroy             # Interaktiv: loescht alles + Terraform State
```
