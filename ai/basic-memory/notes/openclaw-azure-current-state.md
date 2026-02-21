---
title: OpenClaw Azure Setup - Current State
permalink: openclaw-azure-current-state
tags:
- openclaw
- azure
- current-state
- infrastructure
- ansible
---

# OpenClaw Azure Setup - Current State

## Observations

- [architecture] Three-layer architecture: Terraform (infrastructure) -> Cloud-Init (minimal bootstrap) -> Ansible (full VM configuration).
- [scope] Repo deploys OpenClaw on Azure via Terraform as a single-root module (`main.tf`).
- [runtime] OpenClaw runs as a systemd host process on an Ubuntu VM; Nginx runs as a Docker container.
- [security] Secrets are stored in Azure Key Vault (`github-pat`, `anthropic-key`, `admin-username`, `admin-password`).
- [network] Access is restricted to SSH + HTTPS from the current client IP via NSG rules, with an explicit deny-all rule.
- [provisioning] Cloud-init is minimal (31 lines): installs Python3, pip, ACL for Ansible. All real configuration is in `ansible/`.
- [ansible] Full VM configuration is handled by Ansible role `openclaw` with 10 task files, 8 Jinja2 templates, and production-rated linting (5/5).
- [workflow] Standard IaC flow: `make init` -> `make fmt` -> `make validate` -> `make plan` -> `make deploy` -> `make wait-for-cloud-init` -> `make configure` -> `make openclaw-start`.
- [testing] No unit test framework; effective gates are `terraform validate`, `bash -n`, and `ansible-lint`.
- [operations] Makefile covers deploy, VM lifecycle, Ansible configuration, OpenClaw start/stop, and logs/debugging.
- [hardening] 9-layer security model: Azure NSG, UFW, DOCKER-USER iptables, fail2ban (SSH + Nginx), systemd hardening, dedicated user + scoped sudo, auto security updates, Docker hardening, container hardening.
- [ai-meta] Repo has agentic guardrails in `AGENTS.md` and provider-neutral skill conventions under `ai/skills/`.

## Relations

- documented_in [[README]]
- documented_in [[AGENTS]]
- relates_to [[Security State]]
- relates_to [[Deploy Workflow]]
- relates_to [[Ops Runbook]]
- relates_to [[Known Risks]]
