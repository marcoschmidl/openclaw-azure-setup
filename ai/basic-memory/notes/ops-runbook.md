---
title: Ops Runbook
permalink: ops-runbook
tags:
- openclaw
- azure
- operations
- runbook
- ansible
---

# Ops Runbook

## Observations

- [lifecycle] Day-to-day flow: `make start` -> `make openclaw-start` -> work -> `make openclaw-stop` -> `make stop`.
- [configure] After infrastructure changes or first deploy: `make wait-for-cloud-init` -> `make configure` (runs Ansible over SSH).
- [access] SSH via `make ssh`. Dashboard URL from Terraform outputs.
- [credentials] Admin password via `make show-password` or `make show-password-kv`.
- [debug] Key diagnostic targets: `make logs`, `make logs-nginx`, `make docker-ps`, `make cloud-init-status`, `make cloud-init-logs`.
- [ansible] Ansible targets: `make configure`, `make ansible-lint`, `make ansible-syntax-check`, `make ansible-diff`, `make ansible-tags TAGS=...`.
- [device-admin] Device approvals via `make devices-list` and `make approve-device REQUEST_ID=<id>`.
- [safety] Destructive actions (`make destroy`) are explicitly marked as dangerous. All docker/openclaw commands on VM use `sudo -u openclaw`.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- relates_to [[Deploy Workflow]]
- documented_in [[README]]
- documented_in [[Makefile]]
