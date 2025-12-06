# Agent Instructions for `template` Repository

## 1. Repository Identity & Purpose

**This is a TEMPLATE repository.**

- Its primary purpose is to be cloned and instantiated into _new_ Python projects.
- **CRITICAL:** Any changes made here will propagate to all future projects created from this template.
- The core logic for instantiation is in `setup.sh` and `manifest.txt`.

## 2. Core Rules & Constraints

### A. The "Template" Placeholder

- The string `template` is used as a placeholder for the project name.
- **DO NOT** rename `src/template` unless you are working on the `setup.sh` logic itself.
- When adding new source files, place them in `src/template/`.
- When adding new tests, place them in `tests/`.

### B. The Manifest (`manifest.txt`)

- **CRITICAL:** `manifest.txt` is the source of truth for which files are copied to a new project.
- **Rule:** If you add a new file that should be part of the generated project, you **MUST** add it to `manifest.txt`.
- **Rule:** If you delete a file, remove it from `manifest.txt`.

### C. Setup Script (`setup.sh`)

- This script handles the renaming and copying process.
- **Caution:** Be extremely careful when modifying this script. It performs destructive actions (renaming, deleting).

## 3. Development Workflow

### Environment Setup

- The project uses `uv` for dependency management.
- Python version: >=3.11 (defined in `.python-version` and `pyproject.toml`).

### Common Commands (Makefile)

The `Makefile` is the primary entry point for development tasks.

- **Install Dependencies:** `make develop` (installs dev deps and git hooks)
- **Run All Checks (CI):** `make check` (runs ruff, mypy, tests)
- **Run Tests:** `make test` or `nox -s test`
- **Linting:** `make lint` (ruff, pylint)
- **Formatting:** `make format` (ruff)
- **Clean:** `make clean`

### Testing

- Tests are located in `tests/`.
- Uses `pytest`.
- `tests/test_.py` is a placeholder test. Keep it or ensure there is at least one test to verify the test runner works.

## 4. Project Structure

- `src/template/`: Source code for the template package.
- `tests/`: Test suite.
- `.github/`: GitHub Actions workflows and Copilot instructions.
- `manifest.txt`: Allowlist of files to include in new projects.
- `setup.sh`: Instantiation script.
- `pyproject.toml`: Project configuration (build, deps, tools).
- `uv.lock`: Locked dependencies.

## 5. Contribution Guidelines

- **Commit Messages:** Follow Conventional Commits (e.g., `feat(core): add new utility`). Summaries should be <=50 characters.
- **Changelog:** Managed via `git cliff`.
- **Code Style:** Enforced by `ruff` and `mypy`.

## 6. Specific Task Instructions

### Adding a Dependency

1. Add it to `pyproject.toml` (dependencies or dev-dependencies).
2. Run `uv lock` (or `make develop` which usually handles sync).

### Modifying CI

- Edit `.github/workflows/CI.yml`.
- Note that `.github/workflows/.cache-buster` is used to reset caches.
- **CI Ruff Args:** Before running pre-commit in CI, `.github/scripts/ci-ruff-args.sh` modifies `.pre-commit-config.yaml` with stricter ruff args for better GitHub integration. This means CI behavior differs slightly from local `make check`, which uses the default args.

### Updating Instructions

- Consider updating `.github/copilot-instructions.md` when you make significant changes to how the project works, so that agents working on _derived_ projects have accurate information.
