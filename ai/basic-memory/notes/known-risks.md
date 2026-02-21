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

- [state-risk] Local Terraform state files in repo root increase risk of accidental exposure if mishandled. Remote backend deferred to a separate project.
- [single-host] Architecture relies on a single VM; failure of this VM affects the entire service.
- [self-signed-ssl] Self-signed certificate requires browser trust exception. No Let's Encrypt or CA-signed cert.
- [csp] Content Security Policy not yet strengthened (requires browser testing of OpenClaw dashboard).
- [gateway-binding] OpenClaw gateway listens on 0.0.0.0 instead of localhost (binding change requires testing host.docker.internal).
- [digest-pinning] Docker images use tags not digests (maintenance burden vs. supply-chain risk trade-off).
- [manual-ops] Some operational flows are manual and require disciplined operator adherence.
- [deploy-safety] `deploy.sh` now shows plan and asks for confirmation, reducing accidental changes. `make deploy` still uses the script.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- relates_to [[Security State]]
- relates_to [[Deploy Workflow]]
