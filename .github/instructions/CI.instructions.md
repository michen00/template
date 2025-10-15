---
applyTo: ".github/workflows/*.yml"
---

# Workflow Notes for AI Agents

## .github/workflows/

- `CI.yml` mirrors local `make check`; keep Makefile targets stable so the job stays green.
- `lint-github-actions.yml` runs `actionlint` via prebuilt Docker image—no extra steps needed beyond keeping workflow YAML valid.
- `greet-new-contributors.yml` posts a welcome message on first-time PRs; do not add secrets or heavy jobs here.
- Cache resets rely on touching `.github/workflows/.cache-buster` (see `make bust-ci-cache`).
- When adding workflows, list them in `manifest.txt` so `setup.sh` copies them into generated projects.
