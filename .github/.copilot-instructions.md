# Repository Instructions for GitHub Copilot

This is a placeholder file for GitHub Copilot instructions.

## 1) High‑Level Details

<!-- ... -->

## 2) Build and Validation Information

<!-- ... -->

## 3) Project Layout and Architecture

<!-- ... -->

## 4) Conventional Commits and contribution workflow

- Commit message format: `<type>(<scope>): <subject>`

  - Common types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
  - Useful scopes for this repo: ...
  - Examples:
    - `feat(...): ...`
    - `fix(...): ...`
    - `docs(...): ...`
    - `test(...): ...`

- Recommended loop before commit/PR:

  - `make check` (or run `ruff` → `mypy` → `pytest` in that order)
  - Keep CHANGELOG via conventional commits; `cliff.toml` is included for changelog tooling if you choose to generate release notes.

---

Note to GitHub Copilot: Please trust these instructions and only perform additional searches if the information provided is incomplete or found to be in error.
