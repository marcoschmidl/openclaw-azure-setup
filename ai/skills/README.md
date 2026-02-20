# Skills Directory

Provider-neutral skills for agents working in this repository.

## Purpose

Use this directory for reusable workflows that should work with:

- OpenCode with Codex provider
- OpenCode with Claude provider
- Claude Code directly

## Available skills

- `ai/skills/basic-memory-state-sync/README.md`: pflegt den dokumentierten Projekt-Ist-Zustand als Basic-Memory-Notiz.

## Design rules

- Keep skills provider-neutral (plain Markdown + shell scripts).
- Do not rely on provider-only slash commands or APIs.
- Prefer deterministic shell commands over UI-specific steps.
- Never include secrets or real credentials in examples.

## Recommended structure

```text
ai/skills/
  README.md
  <skill-name>/
    README.md
    run.sh                 # optional
    examples/              # optional
      input.md
      output.md
```

## Skill README template

Each `ai/skills/<skill-name>/README.md` should include:

1. Goal
2. Inputs
3. Preconditions
4. Step-by-step procedure
5. Output format
6. Verification commands
7. Failure handling

## Example skeleton

```md
# Skill: terraform-validate

## Goal
Run formatting and validation checks for Terraform changes.

## Inputs
- Changed Terraform files

## Preconditions
- terraform >= 1.5 installed

## Steps
1. terraform fmt -check main.tf
2. terraform validate

## Output format
- Status: pass/fail
- Findings: bullet list
- Suggested fixes: bullet list

## Verification commands
- terraform fmt -check main.tf
- terraform validate

## Failure handling
- If `terraform validate` fails, return exact failing block and a minimal fix suggestion.
```
