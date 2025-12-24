# Claude Code Instructions for `template` Repository

## 1. Repository Identity & Purpose

**This is a TEMPLATE repository.**

- Its primary purpose is to be cloned and instantiated into new Python projects via `setup.sh`.
- **CRITICAL:** Any changes made here will propagate to all future projects created from this template.
- The core logic for instantiation is in `setup.sh` and `manifest.txt`.
- Think of this as a "meta-project" - you're not building an application, you're maintaining a template.

## 2. Core Rules & Constraints

### A. The "Template" Placeholder

- The string `template` is used as a placeholder for the project name throughout the codebase.
- **DO NOT** rename `src/template` unless you are specifically working on the `setup.sh` logic itself.
- When adding new source files, place them in `src/template/`.
- When adding new tests, place them in `tests/`.
- The `setup.sh` script will handle renaming during instantiation.

### B. The Manifest (`manifest.txt`)

- **CRITICAL:** `manifest.txt` is the source of truth for which files are copied to new projects.
- **Rule:** If you add a new file that should be part of generated projects, you **MUST** add it to `manifest.txt`.
- **Rule:** If you delete a file, remove it from `manifest.txt`.
- Files not in `manifest.txt` will not be copied to new projects (they stay template-only).
- The manifest uses one file path per line (no comments, no wildcards).

### C. Setup Script (`setup.sh`)

- This script handles the renaming and copying process when creating new projects.
- **Caution:** Be extremely careful when modifying this script. It performs destructive actions (renaming, deleting, moving files).
- Test any changes to `setup.sh` thoroughly in a disposable directory.
- The script attempts to generate a fresh `.gitignore` from GitHub templates during setup using `.github/scripts/concat_gitignores.sh`. If this fails (no internet, GitHub down, etc.), it falls back to using the static `.gitignore` from the manifest.

### D. Hidden Files (`.AGENTS.md`, `.CLAUDE.md`, etc.)

- Hidden dotfiles (starting with `.`) are instructions for projects **derived from** this template.
- Non-hidden files (`AGENTS.md`, `CLAUDE.md`) are instructions for working **on the template itself**.
- When editing hidden instruction files, remember you're writing instructions for future projects, not this template.

## 3. Development Workflow

### Environment Setup

- The project uses `uv` for dependency management.
- Python version: >=3.11 (defined in `.python-version` and `pyproject.toml`).
- Virtual environment: `.venv` (automatically managed by `uv`).

### Common Commands (Makefile)

The `Makefile` is the primary entry point for development tasks:

- **Install Dependencies:** `make develop` (installs dev deps, git hooks, and configures git)
- **Run All Checks (CI):** `make check` (runs format-all and test)
- **Run Tests:** `make test` or `nox -s test`
- **Linting:** `make lint` (ruff check --fix)
- **Formatting:** `make format` (lint + ruff format) or `make format-all` (pre-commit + format-unsafe)
- **Clean:** `make clean` (removes build artifacts and caches)

### Testing the Template

- Run `make check` to ensure the template passes all checks.
- Consider testing the instantiation process:

  ```bash
  # In a temporary directory
  bash /path/to/template/setup.sh my-test-project
  cd my-test-project
  make check
  ```

## 4. Project Structure

```text
template/
├── src/template/           # Source code (placeholder package)
├── tests/                  # Test suite
├── .github/                # CI/CD workflows and instructions
│   ├── .copilot-instructions.md
│   ├── copilot-instructions.md
│   └── instructions/
│       └── CI.instructions.md
├── manifest.txt            # Allowlist of files for new projects
├── setup.sh                # Instantiation script
├── pyproject.toml          # Project configuration
├── uv.lock                 # Locked dependencies
├── Makefile                # Task runner
├── AGENTS.md               # Instructions for AI agents (this template)
├── .AGENTS.md              # Instructions for AI agents (derived projects)
├── CLAUDE.md               # Instructions for Claude (this template)
└── .CLAUDE.md              # Instructions for Claude (derived projects)
```

## 5. Contribution Guidelines

### Commit Messages

- Follow **Conventional Commits** format: `<type>(<scope>): <subject>`
  - **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
  - **Subject:** Imperative mood, <=50 characters
  - **Atomic Commits:** One logical change per commit

### Code Style

- Enforced by `ruff` (linting and formatting) and `mypy` (type checking).
- Run `make format` before committing.
- Run `make check` to verify all checks pass.

### Changelog

- Managed automatically via `git cliff` based on conventional commits.
- Do not manually edit `CHANGELOG.md`.

### Documentation Sync

When making significant changes to the template, update these files to keep them in sync:

- `AGENTS.md` and `.AGENTS.md`
- `CLAUDE.md` and `.CLAUDE.md`
- `.github/copilot-instructions.md` and `.github/.copilot-instructions.md`
- `.github/instructions/CI.instructions.md`
- `README.md`

## 6. Specific Task Instructions

### Adding a New File to the Template

1. Create the file in the appropriate location.
2. If the file should be copied to new projects, add its path to `manifest.txt`.
3. Test by running `setup.sh` in a temporary directory.

### Modifying `setup.sh`

1. Make changes carefully - this script performs destructive operations.
2. Test in a temporary directory before committing.
3. Consider edge cases (special characters in project names, missing dependencies, etc.).

### Updating the `.gitignore`

The template includes a script at `.github/scripts/concat_gitignores.sh` that generates `.gitignore` files from GitHub's official templates.

- **During setup:** The script automatically tries to generate a fresh `.gitignore` from upstream templates. If it fails, the static `.gitignore` is used.
- **Manual update:** Run `bash .github/scripts/concat_gitignores.sh` from the template root to regenerate `.gitignore` with the latest templates.

### Adding a Dependency

1. Add it to `pyproject.toml` (dependencies or optional-dependencies).
2. Run `uv lock` to update `uv.lock`.
3. Run `make develop` to sync the virtual environment.
4. Verify with `make check`.

### Modifying CI/CD

- Edit `.github/workflows/CI.yml` for workflow changes.
- Note: `.github/scripts/ci-ruff-args.sh` modifies ruff args for CI to provide better GitHub integration.
- The `.github/workflows/.cache-buster` file can be modified to invalidate caches.

### Updating Instructions for AI Assistants

- **For this template:** Edit `AGENTS.md`, `CLAUDE.md`, `.github/.copilot-instructions.md`
- **For derived projects:** Edit `.AGENTS.md`, `.CLAUDE.md`, `.github/copilot-instructions.md`
- Keep these files in sync with actual repository structure and workflows.

## 7. Working with Claude Code

### Preferred Workflow

1. Use tools (Read, Edit, Write, Glob, Grep) instead of bash commands for file operations.
2. Read files before editing them.
3. Use `make` commands instead of direct tool invocations (e.g., `make test` not `pytest`).
4. When making significant changes, use TodoWrite to track progress.
5. Run `make check` before considering a task complete.

### Git Operations

- When creating commits:
  1. Run `git status` and `git diff` to understand changes.
  2. Review `git log` to match commit message style.
  3. Stage relevant files with `git add`.
  4. Create commit with conventional commit message.
  5. Do not push unless explicitly requested.

### Key Reminders

- This is a template - changes affect all future projects.
- Always update `manifest.txt` when adding/removing files.
- Keep instruction files in sync: `AGENTS.md`, `CLAUDE.md`, `.AGENTS.md`, `.CLAUDE.md`, `.github/.copilot-instructions.md`, `.github/copilot-instructions.md`, `.github/instructions/CI.instructions.md`, and `README.md`.
- Test changes by instantiating a new project with `setup.sh`.
- Hidden dotfiles are for derived projects, not this template.
