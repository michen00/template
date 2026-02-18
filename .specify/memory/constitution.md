<!--
Sync Impact Report
===================
Version change: N/A → 1.0.0 (initial creation)
Modified principles: N/A (all new)
Added sections:
  - Core Principles (5 principles)
  - Technology Stack & Constraints
  - Development Workflow & Quality Gates
  - Governance
Removed sections: None
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ no changes needed (Constitution Check
    section is generic and will be filled per-feature)
  - .specify/templates/spec-template.md ✅ no changes needed (requirements and
    success criteria align with principles)
  - .specify/templates/tasks-template.md ✅ no changes needed (phase structure
    and parallel markers align with principles)
Follow-up TODOs: None
-->

# Template Constitution

## Core Principles

### I. Template Integrity

Every change to this repository propagates to all future derived projects.
Contributors MUST treat modifications as high-impact decisions.

- All file additions, removals, or renames MUST be tested by running
  `setup.sh` in a disposable directory and verifying the derived project
  passes `make check`.
- Hidden dotfiles (`.AGENTS.md`, `.CLAUDE.md`, `.github/.copilot-instructions.md`)
  are instructions for derived projects. Non-hidden counterparts are for this
  template. Contributors MUST NOT confuse the two scopes.
- The `src/template/` directory name is a placeholder. It MUST NOT be renamed
  except within `setup.sh` logic.

### II. Manifest-Driven Distribution

`manifest.txt` is the single source of truth for which files ship to derived
projects.

- Every new file intended for derived projects MUST be added to `manifest.txt`.
- Every deleted file MUST be removed from `manifest.txt`.
- Files omitted from the manifest are template-only and will not appear in
  derived projects.
- No wildcards or comments are permitted in the manifest; one file path per
  line.

### III. Quality Gates (NON-NEGOTIABLE)

All code MUST pass `make check` before being committed. This command runs
formatting, linting, type checking, and tests.

- `ruff` enforces linting and formatting rules (`.ruff.toml`).
- `mypy` enforces strict static type checking (`pyproject.toml`).
- `pytest` runs the test suite with coverage reporting.
- Pre-commit hooks MUST remain active; contributors MUST NOT bypass them
  with `--no-verify`.
- CI via GitHub Actions reproduces these checks on every pull request.

### IV. Conventional Commits

All commits MUST follow the Conventional Commits specification:
`<type>(<scope>): <subject>`.

- Types: `feat`, `fix`, `docs`, `chore`, `style`, `test`, `build`, `ci`,
  `refactor`, `perf`, `revert`.
- Subject line MUST be imperative mood, lowercase start, and under 51
  characters.
- Body lines MUST wrap at 72 characters.
- Each commit MUST represent one atomic logical change.
- `git-cliff` generates the changelog from these commits; manual edits to
  `CHANGELOG.md` are prohibited.

### V. Simplicity & YAGNI

Start simple. Reject speculative complexity.

- Do not add features, abstractions, or configurability beyond what is
  currently required.
- Three similar lines of code are preferable to a premature abstraction.
- Error handling and validation SHOULD exist only at system boundaries
  (user input, external APIs), not for impossible internal states.
- If a simpler alternative exists, it MUST be chosen unless a concrete,
  documented justification is provided.

## Technology Stack & Constraints

- **Language**: Python >=3.11 (defined in `.python-version` and
  `pyproject.toml`).
- **Package Manager**: `uv` for dependency management, virtual environments,
  and lock files.
- **Linting/Formatting**: `ruff` (replaces black, isort, flake8, autoflake).
- **Type Checking**: `mypy` in strict mode with Pydantic plugin.
- **Testing**: `pytest` with `pytest-cov` and `pytest-xdist`; `nox` for
  reproducible CI environments.
- **Pre-commit**: Hooks for security scanning (gitleaks, talisman), code
  quality (ruff, pylint, shellcheck, markdownlint, yamllint, codespell,
  typos), type checking (mypy), and commit message validation (gitlint).
- **CI/CD**: GitHub Actions with dependency caching and Dependabot.
- **Changelog**: `git-cliff` auto-generates from conventional commits.
- **CLI Framework**: Typer for example scripts.

Adding or removing a dependency requires updating `pyproject.toml`, running
`uv lock`, and verifying with `make check`.

## Development Workflow & Quality Gates

### Local Development

1. `make develop` installs all dependencies, configures git hooks, and sets
   up the virtual environment.
2. Contributors work in feature branches and open pull requests.
3. Before committing, contributors MUST run `make check` locally.

### Instruction File Synchronization

When making significant changes, the following files MUST be kept in sync:

- `AGENTS.md` and `.AGENTS.md`
- `CLAUDE.md` and `.CLAUDE.md`
- `.github/copilot-instructions.md` and `.github/.copilot-instructions.md`
- `.github/instructions/CI.instructions.md`
- `README.md`

Failing to synchronize these files is a constitution violation.

### Template Instantiation Testing

Any change to `setup.sh`, `manifest.txt`, or files included in the manifest
SHOULD be validated by running:

```bash
bash setup.sh my-test-project  # in a temporary directory
cd my-test-project
make check
```

## Governance

This constitution is the authoritative reference for all development
practices in this repository. It supersedes ad-hoc conventions, verbal
agreements, and conflicting documentation.

- **Amendments**: Any change to this constitution MUST be documented with a
  version bump, rationale, and updated `LAST_AMENDED_DATE`.
- **Versioning**: Follows semantic versioning. MAJOR for principle removals
  or incompatible redefinitions; MINOR for new principles or material
  expansions; PATCH for wording clarifications and typo fixes.
- **Compliance**: All pull requests and code reviews MUST verify adherence
  to these principles. Violations MUST be flagged and resolved before merge.
- **Runtime Guidance**: For day-to-day development guidance, refer to
  `CLAUDE.md` (Claude Code), `AGENTS.md` (general agents), and
  `.github/copilot-instructions.md` (GitHub Copilot).

**Version**: 1.0.0 | **Ratified**: 2026-02-17 | **Last Amended**: 2026-02-17
