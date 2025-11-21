---
applyTo: ".github/workflows/*.yml"
---

# Workflow Notes for AI Agents

## .github/workflows/

- `CI.yml` mirrors local `make check`; keep Makefile targets stable so the job stays green.
- Cache resets rely on touching `.github/workflows/.cache-buster` (see `make bust-ci-cache`).
- When adding workflows, list them in `manifest.txt` so `setup.sh` copies them into generated projects.
- **Documentation Sync:** Ensure `AGENTS.md`, `.github/copilot-instructions.md`, `.github/instructions/CI.instructions.md`, and `README.md` are kept updated and synced with code changes.
