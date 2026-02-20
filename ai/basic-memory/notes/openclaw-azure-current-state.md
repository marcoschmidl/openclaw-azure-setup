---
title: OpenClaw Azure Setup - Current State
permalink: openclaw-azure-current-state
tags:
- openclaw
- azure
- current-state
- infrastructure
---

# OpenClaw Azure Setup - Current State

## Observations

- [scope] Repo deployt OpenClaw auf Azure per Terraform als Single-Root-Modul (`main.tf`).
- [runtime] OpenClaw laeuft als systemd Host-Prozess auf Ubuntu VM, Nginx laeuft als Docker-Container.
- [security] Secrets liegen in Azure Key Vault (`github-pat`, `anthropic-key`, `admin-username`, `admin-password`).
- [network] Zugriff ist auf SSH + HTTPS begrenzt und laut Doku auf aktuelle Client-IP eingeschraenkt.
- [provisioning] Erstkonfiguration laeuft ueber `cloud-init.yml` plus `templates/*`.
- [workflow] Standardfluss fuer IaC ist `make init`, `make fmt`, `make validate`, `make plan`, `make deploy`.
- [testing] Es gibt keine Unit-Tests; effektive Gates sind `terraform validate` und `bash -n` fuer Shell-Skripte.
- [operations] Makefile deckt Deploy, VM-Lifecycle, OpenClaw Start/Stop und Logs/Debugging ab.
- [hardening] Security-Hardening-Backlog ist zu grossen Teilen als DONE markiert in `TODO-security-hardening.md`.
- [roadmap] `PLAN.md` listet weitere Verbesserungen mit Prioritaeten (Dokukorrektur, Nginx Rate Limits, Healthchecks, Terraform Validations).
- [ai-meta] Repo hat agentische Leitplanken in `AGENTS.md` und provider-neutrale Skill-Konventionen unter `ai/skills/`.

## Relations

- documented_in [[README]]
- documented_in [[AGENTS]]
- documented_in [[PLAN]]
- documented_in [[TODO Security Hardening]]
- relates_to [[Basic Memory in diesem Repo]]
- relates_to [[Security State]]
- relates_to [[Deploy Workflow]]
- relates_to [[Ops Runbook]]
- relates_to [[Known Risks]]
