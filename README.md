# OpenClaw GitHub Agent — Azure VM Deployment

Deploys an Ubuntu 24.04 VM on Azure with Docker, OpenClaw running in a container,
Nginx reverse proxy (Basic Auth + SSL), Key Vault for secrets, and auto-shutdown.

## Architecture

```
Browser / SSH                       Azure
──────────────                ──────────────────────────
                              ┌─ Resource Group ────────┐
https://<fqdn>  ──────────►   │  VM (Ubuntu 24.04)      │
  (Basic Auth)                │  ├── Docker             │
                              │  │   ├── Nginx (SSL)    │
ssh user@<fqdn> ──────────►   │  │   │   └► :443/:80    │
  (Key or Password)           │  │   └── OpenClaw       │
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
                              │  NSG: SSH+HTTPS only    │
                              │       from your IP      │
                              │                         │
                              │  Auto-Shutdown 22:00    │
                              └─────────────────────────┘
```

## Quickstart

```bash
# 1. Configure secrets (optional)
cp .env.example .env
#    Fill in GITHUB_TOKEN and ANTHROPIC_API_KEY

# 2. Deploy
make deploy

# 3. Start OpenClaw on the VM
make openclaw-start

# 4. Open the dashboard
#    URL and password from make output / make show-password
```

## Make Targets

```
make help               Show all targets

Deployment:
  make deploy           Deploy infrastructure (terraform apply)
  make plan             Show planned changes (dry-run)
  make destroy          Delete all resources

VM Management:
  make start            Start the VM
  make stop             Stop the VM (deallocate)
  make restart          Restart the VM
  make status           Show VM status

Access:
  make ssh              SSH into the VM
  make show-password    Show admin password
  make show-password-kv Retrieve password from Key Vault

OpenClaw:
  make openclaw-start   Start OpenClaw + Nginx on VM
  make openclaw-stop    Stop OpenClaw + Nginx on VM

Logs & Debugging:
  make logs             OpenClaw container logs
  make logs-nginx       Nginx container logs
  make docker-ps        Container status on VM
  make cloud-init-status  Cloud-init status
  make cloud-init-logs    Cloud-init logs

Terraform:
  make output           Show all Terraform outputs
  make fmt              Format Terraform files
  make validate         Validate Terraform configuration
```

## Deployment Options

### Option A: Makefile (recommended)

```bash
cp .env.example .env       # Fill in secrets (optional)
make deploy                # terraform init + apply
```

### Option B: deploy.sh (interactive)

```bash
./deploy.sh                # Prompts for secrets interactively
```

### Option C: Terraform directly

```bash
terraform init
terraform apply -var-file="secrets.tfvars"
```

> **Note:** `GITHUB_TOKEN` and `ANTHROPIC_API_KEY` are optional. If omitted,
> the corresponding Key Vault secrets will not be created. The admin password
> is auto-generated if not provided.

## .env File

```bash
# .env (do not commit!)
GITHUB_TOKEN=ghp_xxx
ANTHROPIC_API_KEY=sk-ant-xxx
```

Automatically loaded by the Makefile and passed as Terraform variables.

## Terraform Variables

| Variable | Default | Description |
|---|---|---|
| `location` | `westeurope` | Azure region |
| `vm_size` | `Standard_B2s` | VM size (2 vCPU, 4 GB RAM) |
| `admin_username` | `clawadmin` | SSH + dashboard username |
| `admin_password` | *(auto-generated)* | SSH + dashboard password |
| `github_pat` | *(empty)* | GitHub PAT (optional) |
| `anthropic_key` | *(empty)* | Anthropic API key (optional) |
| `dns_label` | *(auto-generated)* | DNS label for the public IP |
| `allowed_ip` | *(auto-detected)* | IP for SSH/HTTPS access |
| `ssh_public_key_path` | `~/.ssh/id_rsa.pub` | Path to SSH public key |
| `auto_shutdown_time` | `2200` | Auto-shutdown time (UTC) |

## Daily Workflow

```bash
make start               # Start the VM
make openclaw-start      # Start OpenClaw + Nginx
#    Open https://<fqdn> in your browser
make openclaw-stop       # When done
make stop                # Deallocate VM (no compute costs)
```

## Costs

| State | Cost (approx.) |
|---|---|
| VM running (Standard_B2s) | ~EUR 0.04/h |
| VM deallocated | ~EUR 1.50/mo (disk only) |
| Key Vault | ~EUR 0.03/mo |
| **Typical: 4h/day usage** | **~EUR 6.50/mo** |

Auto-shutdown at 22:00 UTC prevents forgotten running VMs.

## Security

- **NSG**: SSH + HTTPS only from your IP, everything else blocked
- **Basic Auth**: Dashboard protected via Nginx with password
- **SSL**: Self-signed certificate on Azure FQDN
- **Key Vault**: Secrets never stored on disk, loaded by `start.sh` and removed by `stop.sh`
- **Managed Identity**: VM authenticates to Key Vault without credentials
- **Container Isolation**: Nginx + OpenClaw run in Docker
- **Auto-Shutdown**: Failsafe against forgotten VMs
- **Dual Auth**: SSH via key or password

## Files

| File | Description |
|---|---|
| `Makefile` | Build targets for all operations |
| `main.tf` | Terraform configuration (entire infrastructure) |
| `cloud-init.yml` | VM provisioning template (references templates/) |
| `.env.example` | Template for secrets |
| `deploy.sh` | Interactive wrapper for Terraform |
| `destroy.sh` | Deletes all resources + Terraform state |
| `templates/docker-compose.yml` | Docker Compose: Nginx + OpenClaw containers |
| `templates/openclaw.json` | OpenClaw agent configuration |
| `templates/nginx.conf` | Nginx reverse proxy (SSL + Basic Auth) |
| `templates/start.sh` | Loads Key Vault secrets, sets htpasswd, starts Docker |
| `templates/stop.sh` | Stops Docker, removes local secrets |
| `templates/clone-repo.sh` | Clones GitHub repos (optionally with PAT auth) |

## Customization

### Change VM size

```bash
make deploy EXTRA_TF_VARS='-var="vm_size=Standard_B2ms"'
```

### Use a different LLM model

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

### Update NSG rule for a new IP

```bash
make deploy EXTRA_TF_VARS='-var="allowed_ip=NEW.IP.ADDRESS"'
```

## Troubleshooting

```bash
make cloud-init-status   # Check cloud-init status
make cloud-init-logs     # Show cloud-init logs
make docker-ps           # Container status
make logs                # OpenClaw logs
make logs-nginx          # Nginx logs
```

On the VM directly:
```bash
docker exec openclaw-nginx nginx -t    # Test Nginx config
curl -k https://localhost               # Test dashboard locally
az login --identity                     # Test managed identity
```

## Cleanup

```bash
make destroy             # Interactive: deletes everything + Terraform state
```
