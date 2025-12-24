---
applyTo: ".github/workflows/*.yml"
---

# Workflow Notes for AI Agents

## .github/workflows/

- `CI.yml` is similar to local `make check`, but CI runs `.github/scripts/ci-ruff-args.sh` before `nox -s precommit` to modify ruff args for stricter checking and GitHub-optimized output formatting. Locally, `make check` uses the default args from `.pre-commit-config.yaml`.
- Cache resets rely on touching `.github/workflows/.cache-buster` (see `make bust-ci-cache`).
- When adding workflows, list them in `manifest.txt` so `setup.sh` copies them into generated projects.
- **Documentation Sync:** Ensure `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/CI.instructions.md`, and `README.md` are kept updated and synced with code changes.
