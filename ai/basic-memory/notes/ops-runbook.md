---
title: Ops Runbook
permalink: ops-runbook
tags:
- openclaw
- azure
- operations
- runbook
---

# Ops Runbook

## Observations

- [lifecycle] Tagesbetrieb folgt typischerweise `make start` -> `make openclaw-start` -> Arbeit -> `make openclaw-stop` -> `make stop`.
- [access] Zugriff erfolgt per `make ssh` und Dashboard-URL aus Terraform-Outputs.
- [credentials] Admin-Passwort ist ueber `make show-password` oder `make show-password-kv` abrufbar.
- [debug] Wichtige Diagnosepunkte sind `make logs`, `make logs-nginx`, `make docker-ps`, `make cloud-init-status`, `make cloud-init-logs`.
- [device-admin] Control-UI-Device-Freigaben laufen ueber `make devices-list` und `make approve-device REQUEST_ID=<id>`.
- [safety] Destruktive Aktionen (`make destroy`) sind explizit als gefaehrlich markiert.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- relates_to [[Deploy Workflow]]
- documented_in [[README]]
- documented_in [[Makefile]]
