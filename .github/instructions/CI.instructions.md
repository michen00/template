---
applyTo: '.github/workflows/*.yml'
---

# Workflow Notes for AI Agents

## .github/workflows/

- `CI.yml` is similar to local `make check`, which now runs `make tidy`, both pre-commit hook stages, and tests. CI still runs `.github/scripts/ci-ruff-args.sh` before `nox -s precommit` to modify ruff args for stricter checking and GitHub-optimized output formatting, while local `make check` uses the default args from `.pre-commit-config.yaml`.
- Cache resets rely on touching `.github/workflows/.cache-buster` (see `make bust-ci-cache`).
- **Documentation Consistency:** Keep guidance documents (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/CI.instructions.md`, `.specify/memory/constitution.md`, and `README.md`) internally consistent with workflow behavior. When shared infrastructure changes overlap with derived-project guidance, review any downstream documentation and update them as needed.
