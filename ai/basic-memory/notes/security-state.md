---
title: Security State
permalink: security-state
tags:
- openclaw
- azure
- security
- hardening
---

# Security State

## Observations

- [perimeter] Network Security Group erlaubt laut Doku nur SSH und HTTPS von der erlaubten Client-IP.
- [auth] Dashboard ist per Nginx Basic Auth geschuetzt.
- [secrets] Laufzeit-Secrets kommen aus Azure Key Vault statt aus persistenten lokalen Klartextdateien.
- [identity] VM nutzt Managed Identity fuer Key-Vault-Zugriff.
- [host] OpenClaw Service ist mit systemd Hardening-Optionen konfiguriert (`NoNewPrivileges`, `ProtectSystem`, `ProtectHome`).
- [container] Nginx-Container laeuft mit eingeschraenkten Security-Settings laut Repo-Dokumentation.
- [os] fail2ban fuer SSH und unattended-upgrades sind im Hardening-Backlog als umgesetzt dokumentiert.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- documented_in [[README]]
- documented_in [[TODO Security Hardening]]
- documented_in [[PLAN]]
