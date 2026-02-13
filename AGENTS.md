# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure-as-code repo that deploys the OpenClaw GitHub agent on an Azure VM (Ubuntu 24.04) with Docker, Nginx reverse proxy (SSL + Basic Auth), Azure Key Vault for secrets, and auto-shutdown. Documentation uses ASCII-safe German (ue/oe/ae instead of umlauts).

## Commands

### Deployment
```bash
make deploy              # terraform init + apply (reads .env for secrets)
make plan                # dry-run / preview changes
make destroy             # interactive destroy via destroy.sh
```

### Validation (run before PRs)
```bash
make fmt                 # terraform fmt
make validate            # terraform validate
bash -n deploy.sh destroy.sh templates/start.sh templates/stop.sh  # syntax-check shell scripts
```

### VM Lifecycle
```bash
make start / stop / restart / status
make ssh                 # SSH into VM
make show-password       # admin password from tfstate
make show-password-kv    # admin password from Key Vault
```

### OpenClaw on VM
```bash
make openclaw-start      # start containers via SSH
make openclaw-stop       # stop containers via SSH
make logs                # openclaw container logs
make logs-nginx          # nginx container logs
make docker-ps           # container status
make cloud-init-status   # provisioning status
```

### Override variables
```bash
make deploy EXTRA_TF_VARS='-var="vm_size=Standard_B2ms"'
make deploy EXTRA_TF_VARS='-var="allowed_ip=1.2.3.4"'
```

## Architecture

Single `main.tf` Terraform root module (no child modules). All Azure resources in one file:
- Resource Group, VNet/Subnet/NSG, Public IP with DNS label, NIC
- Key Vault (RBAC mode) with optional secrets (`github-pat`, `anthropic-key`) and always-present admin credentials
- Linux VM with system-assigned managed identity (for Key Vault access without stored credentials)
- Auto-shutdown schedule

### Template rendering pipeline
`main.tf` renders `cloud-init.yml` via `templatefile()`, injecting the contents of `templates/*` files as template variables. Some templates are double-rendered: `nginx.conf`, `start.sh`, and `clone-repo.sh` pass through `templatefile()` first (for `${fqdn}` / `${keyvault_name}` interpolation), then get embedded into `cloud-init.yml`. Others (`docker-compose.yml`, `openclaw.json`, `stop.sh`) are read verbatim with `file()`.

### Runtime on the VM
`cloud-init` installs Docker, Azure CLI, writes config files to `~/openclaw/`, generates a self-signed SSL cert, and pre-pulls images. At runtime:
1. `start.sh` authenticates via managed identity, fetches secrets from Key Vault, writes a `.env` for Docker Compose, sets up htpasswd, and runs `docker compose up -d`
2. `stop.sh` runs `docker compose down` and removes the `.env` and `.htpasswd` files (secrets never persist on disk)
3. Two containers: `openclaw-nginx` (SSL termination + Basic Auth proxy) and `openclaw-github-agent` (the agent on internal port 18789)

### Secrets flow
`.env` file (local) -> Makefile reads it -> passes as `-var` to Terraform -> stored in Key Vault -> `start.sh` on VM fetches from Key Vault at runtime -> written to ephemeral `.env` in `~/openclaw/` -> cleaned up by `stop.sh`.

## Coding Conventions

- **Terraform**: format with `terraform fmt` before commit. Resource names use `openclaw-*` prefix (e.g., `vnet-openclaw`, `nsg-openclaw`). Keep all resources in `main.tf`.
- **Shell scripts**: `#!/bin/bash` + `set -euo pipefail`. Constants uppercase (`KEYVAULT`, `TOTAL_STEPS`). Use colored log/warn/err/step helpers consistently.
- **Filenames**: lowercase, hyphenated (`cloud-init.yml`, `clone-repo.sh`).
- **Commits**: Conventional Commits format (e.g., `feat(terraform): add configurable vm size`, `fix(makefile): handle missing terraform outputs`).
- **Templates with `$$`**: In Terraform-rendered shell templates (`start.sh`, `clone-repo.sh`), use `$$` to escape literal `$` for shell variable expansion (Terraform's `templatefile()` interprets single `$`).

## Pre-PR Checklist

- `make fmt` + `make validate` + `make plan`
- `bash -n deploy.sh destroy.sh templates/start.sh templates/stop.sh`
- Include a short `make plan` summary in the PR when changing Terraform resources.

## Key Terraform Variables

All have sensible defaults; `admin_password` and `dns_label` auto-generate if empty. `github_pat` and `anthropic_key` are optional — corresponding Key Vault secrets are only created when non-empty. `allowed_ip` auto-detects via ipify.org if not set.

## Prerequisites

- Terraform >= 1.5
- Azure CLI (logged in via `az login`)
- SSH key (default `~/.ssh/id_rsa.pub`, configurable via `ssh_public_key_path` variable)
