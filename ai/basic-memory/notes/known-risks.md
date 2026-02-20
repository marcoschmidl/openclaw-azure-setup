---
title: Known Risks
permalink: known-risks
tags:
- openclaw
- azure
- risks
- operations
---

# Known Risks

## Observations

- [state-risk] Lokale Terraform-State-Dateien im Repo-Root erhoehen das Risiko unbeabsichtigter Exposition bei falschem Handling.
- [doc-drift] `PLAN.md` nennt Dokumentationsabweichungen zwischen gewuenschter und aktueller Architektur-Beschreibung.
- [apply-safety] `make deploy` verwendet Auto-Approve; versehentliche Cloud-Aenderungen sind dadurch leichter moeglich.
- [single-host] Architektur ist stark auf eine einzelne VM fokussiert; Ausfall dieser VM betrifft den gesamten Service.
- [manual-ops] Mehrere Betriebsablaeufe sind manuell und erfordern disziplinierten Operator-Flow.
- [backlog] Einige Hardening-/Robustheitsmassnahmen sind in `PLAN.md` noch offen oder als spaetere Schritte markiert.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- relates_to [[Security State]]
- relates_to [[Deploy Workflow]]
- documented_in [[PLAN]]
