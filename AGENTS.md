# AGENTS.md

Guidance for agentic coding tools operating in this repository.

Canonical AI docs also exist under `ai/` (`ai/AGENTS.md`, `ai/CLAUDE.md`, `ai/skills/`).

## 1) Project intent and architecture

- This repo deploys OpenClaw on Azure using Terraform.
- OpenClaw runs as a **systemd host process** on an Ubuntu VM.
- Nginx runs as a Docker container and provides SSL + Basic Auth reverse proxying.
- Azure Key Vault stores secrets (`github-pat`, `anthropic-key`, admin credentials).
- `cloud-init.yml` writes templates and provisions the VM at first boot.

## 2) Cursor/Copilot repository rules

- Checked for Cursor rules in `.cursor/rules/`: none found.
- Checked for `.cursorrules`: none found.
- Checked for Copilot instructions in `.github/copilot-instructions.md`: none found.
- If those files are later added, treat them as highest-priority repo-local agent rules.

## 3) Setup and prerequisites

- Required tools: `terraform` (>= 1.5), `az`, `bash`, `ssh`.
- Optional local secrets file: `.env` (from `.env.example`).
- Authenticate Azure CLI before infra operations: `az login`.
- Terraform providers are pinned in `main.tf` and `.terraform.lock.hcl`.

## 4) Build, lint, validate, test commands

### Core workflow

```bash
make init
make fmt
make validate
make plan
make deploy
```

### Lint/validation commands

```bash
make fmt
make validate
bash -n deploy.sh destroy.sh templates/start.sh templates/stop.sh templates/clone-repo.sh
```

### "Single test" / targeted checks (important for agents)

Use these when you only changed one area:

```bash
# Single shell script syntax check
bash -n templates/start.sh

# Check multiple specific scripts only
bash -n deploy.sh templates/clone-repo.sh

# Format-check a single Terraform file via standard formatter
terraform fmt -check main.tf

# Validate full Terraform graph after any TF change
terraform validate
```

Notes:
- There is no dedicated unit test framework in this repo today.
- Treat `bash -n` and `terraform validate` as the effective test gates.

## 5) Deployment and safety conventions

- Prefer `make ...` targets over ad-hoc commands.
- `make destroy` / `./destroy.sh` is destructive; do not run unless explicitly required.
- Never commit secrets (`.env`, `*.tfvars`, state outputs containing sensitive values).
- Do not alter `.gitignore` to allow secret files.

## 6) Code style guidelines

### Terraform (`main.tf`)

- Keep infrastructure in the existing single-root-module style unless explicitly refactoring.
- Run `terraform fmt` after edits; keep canonical HCL formatting.
- Use clear variable descriptions and preserve sensitive flags for secret inputs.
- Naming convention: Azure resources use `openclaw`-prefixed names where applicable.
- Preserve provider/version constraints unless there is a deliberate upgrade.
- Prefer `locals` for resolved defaults and reused computed values.
- Keep comments concise and focused on non-obvious intent.
- Avoid introducing unnecessary abstraction or over-modularization.

### Shell (`*.sh` and `templates/*.sh`)

- Shebang + strict mode required: `#!/bin/bash` and `set -euo pipefail`.
- Quote variable expansions unless intentional word-splitting is required.
- Use uppercase for constants/env-like vars (`KEYVAULT`, `WORK_DIR`, `TOTAL_STEPS`).
- Keep helper logging functions (`log`, `warn`, `err`, `step`) consistent.
- Fail fast for hard prerequisites; use warnings only for optional behavior.
- For commands that can fail non-fatally, handle explicitly (`|| true` with reason).
- Use readable step-based flow in long operational scripts.
- Keep scripts idempotent where practical (safe to re-run).

### YAML/templates (`cloud-init.yml`, `templates/*`)

- Preserve indentation strictly; cloud-init is whitespace-sensitive.
- Keep template variable names explicit and aligned with `main.tf` injection keys.
- When embedding shell in Terraform templates, handle `$` escaping correctly.
- Prefer comments that explain provisioning intent, not obvious syntax.

### Makefile

- Add new targets as `.PHONY` with `##` help text.
- Reuse existing variables (`RG`, `VM`, `ALL_TF_VARS`) instead of duplicating logic.
- Keep target output operator-friendly and concise.

## 7) Imports, types, naming, and formatting specifics

- Imports: N/A for Terraform/HCL; for shell, prefer direct command usage with prerequisite checks.
- Types: explicitly set Terraform variable `type` for non-trivial or sensitive inputs.
- Naming:
  - Files: lowercase, hyphen-separated (`clone-repo.sh`, `cloud-init.yml`).
  - Terraform resources/data: descriptive names (`main`, `my_ip`, `admin_password`).
  - Env vars: uppercase snake case.
- Formatting:
  - HCL via `terraform fmt`.
  - Shell formatting should stay consistent with existing indentation style.
  - Repository line endings are LF (`.gitattributes`).

## 8) Error handling expectations

- Prefer explicit checks before side-effecting operations (`command -v`, login checks, file existence checks).
- Use clear actionable error messages (what failed + how to fix).
- In Terraform, favor validation/postcondition-style guardrails when adding risky inputs.
- In scripts, separate hard failures (`err`) from recoverable paths (`warn`).

## 9) Security and secret handling

- Never print full secret values in logs.
- `.env` is local-only and ignored by git.
- Key Vault is source of truth for runtime secrets on VM.
- `start.sh` may materialize temporary local secret files; `stop.sh` cleans them.
- Preserve restrictive file permissions for secret-bearing files (`chmod 600`).

## 10) Change checklist for agents

Before finishing a change:

```bash
make fmt
make validate
bash -n deploy.sh destroy.sh templates/start.sh templates/stop.sh templates/clone-repo.sh
make plan
```

For small edits, run the smallest relevant targeted checks first, then full validation if Terraform changed.

## 11) Cross-provider skills (OpenCode + Claude)

- Source of truth for reusable workflows: `ai/skills/`.
- Skill files must be provider-neutral Markdown plus optional executable scripts.
- Preferred skill layout:
  - `ai/skills/<skill-name>/README.md` (goal, inputs, steps, output format).
  - `ai/skills/<skill-name>/run.sh` (optional automation).
  - `ai/skills/<skill-name>/examples/` (optional examples).
- Keep skills usable by both Codex and Claude: avoid provider-only commands/features.
- If `CLAUDE.md` exists, treat it as a thin pointer to `AGENTS.md` + `ai/skills/`.
