---
title: Deploy Workflow
permalink: deploy-workflow
tags:
- openclaw
- azure
- deploy
- terraform
---

# Deploy Workflow

## Observations

- [entrypoint] Primarer Operator-Flow laeuft ueber Make-Targets, nicht ueber ad-hoc Terraform-Aufrufe.
- [core-sequence] Empfohlene IaC-Sequenz ist `make init`, `make fmt`, `make validate`, `make plan`, `make deploy`.
- [state] Terraform wird im Root-Modul verwendet (`main.tf`) mit lokalen State-Dateien im Repo-Root.
- [secrets] Optionale Secrets werden aus `.env` gelesen und als `TF_VAR_*` an Terraform uebergeben.
- [apply] `make deploy` nutzt `terraform apply ... -auto-approve`.
- [reprovision] Fuer cloud-init-Aenderungen ist ein VM-Recreate-Flow (`make redeploy-vm`) vorgesehen.

## Relations

- relates_to [[OpenClaw Azure Setup - Current State]]
- documented_in [[README]]
- documented_in [[Makefile]]
- documented_in [[AGENTS]]
