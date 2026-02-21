---
title: Deploy Workflow
permalink: deploy-workflow
tags:
- openclaw
- azure
- deploy
- terraform
- ansible
---

# Deploy Workflow

## Observations

- [entrypoint] Primary operator flow uses Make targets, not ad-hoc Terraform or Ansible calls.
- [core-sequence] Full deployment: `make init` -> `make fmt` -> `make validate` -> `make plan` -> `make deploy` -> `make wait-for-cloud-init` -> `make configure` -> `make openclaw-start`.
- [terraform] Terraform is used in a single root module (`main.tf`) with local state files in repo root.
- [cloud-init] Cloud-init is minimal (31 lines): installs Python3, pip, ACL. No application configuration.
- [ansible] `make configure` runs Ansible playbook over SSH to fully configure the VM (Docker, Node.js, Nginx, OpenClaw, firewall, security hardening).
- [secrets] Optional secrets are read from `.env` and passed as `TF_VAR_*` to Terraform. Runtime secrets come from Azure Key Vault.
- [apply] `deploy.sh` now shows `terraform plan` output and asks for confirmation before applying.
- [reprovision] For cloud-init changes, use `make redeploy-vm`. For config-only changes, use `make configure` (no VM recreation needed).

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- documented_in [[README]]
- documented_in [[Makefile]]
- documented_in [[AGENTS]]
