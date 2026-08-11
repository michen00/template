---
applyTo: '.github/workflows/*.yml'
---

# Workflow Notes for AI Agents

## .github/workflows/

- `CI.yml` covers the same ground as local `make check` (which runs `make tidy`, both pre-commit hook stages, and tests), but fans it out across three parallel jobs: `precommit` (trufflehog plus `nox -s precommit`), `mypy` (`nox -s mypy`), and `pytest` (`nox -s test`). CI still runs `.github/scripts/ci-ruff-args.sh` before the pre-commit session to modify ruff args for stricter checking and GitHub-optimized output formatting, while local `make check` uses the default args from `.pre-commit-config.yaml`.
- **`run-ci` is the required status context and its name is load-bearing.** It is named `Run CI (3.13)` to reproduce exactly what the previous single job rendered under a one-element `python-version` matrix, so branch protection needs no re-pointing. Renaming it leaves a required context that never reports, which blocks every pull request; renaming it to something not required silently un-gates the branch. Check `gh api repos/OWNER/REPO/rulesets` before touching it. The job set can otherwise grow freely behind it.
- mypy runs in exactly one place in CI — the `mypy` nox session, which invokes it through its pre-commit hook so the hook's `additional_dependencies` stay the single source of truth. It is deliberately not also in the `precommit` session; putting it back there would run it twice.
- `pr-mechanical-checks.yml` is the deterministic gate on the pull request title and the branch's commit subjects. It is read-only (`contents: read`) and runs the stdlib-only modules in `checks/` on a bare interpreter, with no project install. Anything that needs to write belongs in a separate `workflow_run` workflow, whose definition GitHub takes from the default branch rather than from the pull request.
- Cache resets rely on touching `.github/workflows/.cache-buster` (see `make bust-ci-cache`). That file is folded into both the uv and the pre-commit cache keys, so it now invalidates both.
- Hook version bumps are Dependabot's job via the `pre-commit` ecosystem in `.github/dependabot.yml`. `.pre-commit-config.yaml` sets `autoupdate_schedule: quarterly` so pre-commit.ci, which cannot be stood down entirely, does not open the same bump.
- `lint-github-actions.yml` is `workflow_dispatch`-only: actionlint is already enforced on every push and pull request by its pinned pre-commit hook, which CI runs. Keep the workflow's pinned image tag in step with the hook's `rev`.
- **Documentation Consistency:** Keep guidance documents (`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/CI.instructions.md`, `.specify/memory/constitution.md`, and `README.md`) internally consistent with workflow behavior. When shared infrastructure changes overlap with derived-project guidance, review any downstream documentation and update them as needed.
