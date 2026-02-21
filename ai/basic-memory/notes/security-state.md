---
title: Security State
permalink: security-state
tags:
- openclaw
- azure
- security
- hardening
- ansible
---

# Security State

## Observations

- [model] 9-layer security model implemented: Azure NSG, UFW, DOCKER-USER iptables, fail2ban, systemd hardening, dedicated user + scoped sudo, auto security updates, Docker hardening, container hardening.
- [perimeter] NSG allows only SSH and HTTPS from the allowed client IP, with an explicit deny-all rule at priority 4096.
- [firewall] UFW on the VM denies all incoming by default; DOCKER-USER iptables chain restricts container traffic.
- [auth] Dashboard is protected by Nginx Basic Auth with rate limiting (5r/s, burst=10).
- [fail2ban] Two jails active: SSH (sshd) and Nginx Basic Auth (nginx-http-auth).
- [secrets] Runtime secrets come from Azure Key Vault via Managed Identity. No cleartext secrets persist on disk.
- [user] Dedicated `openclaw` system user with scoped sudoers (not root, not admin). `clawadmin` SSH user is not in docker group.
- [systemd] OpenClaw service hardened with NoNewPrivileges, ProtectSystem, ProtectHome, ProtectKernelTunables, ProtectKernelModules, ProtectControlGroups, RestrictSUIDSGID, MemoryMax=3G, CPUQuota=150%, TasksMax=256.
- [ssl] ECDSA P-256 self-signed cert with server cipher preference, session cache, tickets disabled.
- [nginx] Gzip compression, 4h WebSocket timeout, security headers (X-Frame-Options, X-Content-Type-Options, Referrer-Policy).
- [docker] Docker daemon hardened: no-new-privileges default, live-restore, userland proxy disabled, iptables managed. Nginx container has healthcheck.
- [scripts] `clone-repo.sh` uses GIT_ASKPASS (no CLI token). `start.sh` uses printf (no echo for secrets). `stop.sh` uses shred for secure deletion.
- [deploy] `deploy.sh` shows plan before apply. `.env.example` has chmod 600 hint.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- relates_to [[Known Risks]]
- documented_in [[README]]
- documented_in [[AGENTS]]
