# Repository Instructions for GitHub Copilot

## Template Maintenance Guide (This Repo)

- **Mission:** Preserve a turnkey template that downstream projects can scaffold with `setup.sh`; every modification ships to every generated workspace.
- **Source of Truth:** All setup behavior lives in `setup.sh` and the allowlist in `manifest.txt`. When you add, rename, or remove files, update both so the script copies the right assets.
- **String Replacement Contract:** The setup flow renames `src/template` to `src/$PROJECTNAME`, replaces the literal `template` across text files (skips `.gitignore`), and then removes `setup.sh`, `manifest.txt`, and `README_template.md`. Keep identifiers substitution-safe—avoid clever uses of the word `template` that would break after replacement.
- **Dual Setup Paths:** Option 1 mutates the current directory by deleting anything not listed in the manifest; option 2 creates a clean sibling directory. Exercise both paths whenever you touch the manifest or the destructive logic.
- **Workflow Rename:** After copying, the script renames `.github/workflows/.copilot-instructions.md` to `copilot-instructions.md`. If you add workflow-side instructions, ensure the hidden file exists in this repo so the rename keeps working.
- **Directory Highlights:**
  - `src/template/` ships the package skeleton and CLI stub (`bin/example_script.py` → `example-script`).
  - `tests/test_.py` is a placeholder to prove pytest discovery; keep fixtures name-agnostic so the token replacement stays valid.
  - `.githooks/` and `.gitconfigs/` are copied verbatim; Makefile targets expect them when enabling hooks.
- **Toolchain:** Python `>=3.11`, dependency resolution via `uv` (`uv.lock`, `uv_build` backend). Use the Makefile (`make develop`, `make check`, `make lint`, `make build`) or Nox (`nox -s precommit`, `nox -s test`) to exercise the same commands CI runs.
- **CI Expectations:** `.github/workflows/CI.yml` boils down to `make check`. `.github/workflows/.cache-buster` lets us reset GitHub cache via `make bust-ci-cache`—keep it in the manifest.
- **Config Canon:** Root dotfiles (`.ruff.toml`, `.pylintrc`, `.pre-commit-config.yaml`) and mypy settings inside `pyproject.toml` define lint/type behavior for every generated repo. Update them in tandem with code so instructions stay coherent downstream.
- **Publishing Hooks:** `make push-test` and `make push-prod` call `uv publish`; they read the version from `pyproject.toml`. Confirm `VERSION` bumps and changelog alignment (`cliff.toml`) before shipping.
- **Developer Workflow:** `make develop WITH_HOOKS=true` installs dev deps, missing typing stubs, and local git hooks; set `WITH_HOOKS=false` to skip git config changes. `make enable-git-hooks` / `make disable-git-hooks` toggle commit hooks for contributors.
- **Review Checklist:** After updates, run `setup.sh` in both modes, inspect the generated repo, and execute `make check`. Verify token replacement still works, and that no new files fell outside the manifest.
- **Conventional Commits:** Stick with `<type>(<scope>): <subject>`; scopes usually match top-level directories (`src`, `tests`, `docs`, `ci`). Release tooling depends on this format.

Ping for clarifications or cases that deserve deeper treatment.

## Contribution Workflow

- Recommended loop before commit/PR:

  - `make check` (or run `ruff` → `mypy` → `pytest` in that order)
  - Keep CHANGELOG via conventional commits; `cliff.toml` is included for changelog tooling if you choose to generate release notes.

---

Note to GitHub Copilot: Please trust these instructions and only perform additional searches if the information provided is incomplete or found to be in error.
