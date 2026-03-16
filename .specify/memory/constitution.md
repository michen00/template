# Template Constitution

## Core Principles

### I. Template Integrity

Every change to this repository propagates to all future derived projects.
Contributors MUST treat modifications as high-impact decisions.

- All file additions, removals, or renames MUST be tested by running `setup.sh` in a disposable directory and verifying the derived project passes `make check`.
- Hidden dotfiles (`.AGENTS.md`, `.CLAUDE.md`, `.github/.copilot-instructions.md`, `.specify/memory/.constitution.md`) are instructions for derived projects. Non-hidden counterparts are for this template. Contributors MUST NOT confuse the two scopes.
- The `src/template/` directory name is a placeholder. It MUST NOT be renamed except within `setup.sh` logic.

### II. Manifest-Driven Distribution

`manifest.txt` is the single source of truth for which files ship to derived
projects.

- Every new file intended for derived projects MUST be added to `manifest.txt`.
- Every deleted file MUST be removed from `manifest.txt`.
- Files omitted from the manifest are template-only and will not appear in derived projects.
- No wildcards or comments are permitted in the manifest; one file path per line.

### III. Quality Gates (NON-NEGOTIABLE)

All code MUST pass `make check` before being committed. This command runs formatting, linting, type checking, and tests.

- `ruff` enforces linting and formatting rules (`.ruff.toml`).
- `mypy` enforces strict static type checking (`pyproject.toml`).
- `pytest` runs the test suite with coverage reporting.
- Pre-commit hooks MUST remain active; contributors MUST NOT bypass them with `--no-verify`.
- CI via GitHub Actions reproduces these checks on every pull request.

### IV. Conventional Commits

All commits MUST follow the Conventional Commits specification:
`<type>(<scope>): <subject>`.

- Types: `feat`, `fix`, `docs`, `chore`, `style`, `test`, `build`, `ci`, `refactor`, `perf`, `revert`.
- Subject line MUST be imperative mood, lowercase start, and under 51 characters.
- Body lines MUST wrap at 72 characters.
- Each commit MUST represent one atomic logical change.
- `git-cliff` generates the changelog from these commits; manual edits to `CHANGELOG.md` are prohibited.

### V. Design Philosophy

Start simple. Reject speculative complexity.

- Complexity is acceptable; complication is not. Readability comes first.
- Delay irreversible architectural decisions until enough information is available.
- Do not add features, abstractions, or configurability beyond what is currently required.
- Three similar lines of code are preferable to a premature abstraction.
- Error handling and validation SHOULD exist only at system boundaries (user input, external APIs), not for impossible internal states.
- If a simpler alternative exists, it MUST be chosen unless a concrete, documented justification is provided.

### VI. Code Quality and Structure

- Use clear module boundaries; avoid god modules.
- Favor small, composable functions with explicit inputs and outputs.
- Prefer well-understood patterns over cleverness unless measurable benefits are demonstrated.
- Keep core logic side-effect-free where practical; isolate I/O at boundaries.
- Make refactors safe through strong automated test coverage.

## Technology Stack & Constraints

- **Language**: defined in `.python-version` and `pyproject.toml`.
- **Package Manager**: `uv` for dependency management, virtual environments, and lock files.
- **Linting/Formatting**: `ruff` (replaces black, isort, flake8, autoflake).
- **Type Checking**: `mypy` in strict mode with Pydantic plugin.
- **Testing**: `pytest` with `pytest-cov` and `pytest-xdist`; `nox` for reproducible CI environments.
- **Pre-commit**: Hooks for security scanning (gitleaks, talisman), code quality (ruff, pylint, shellcheck, markdownlint, yamllint, codespell, typos), type checking (mypy), and commit message validation (gitlint).
- **CI/CD**: GitHub Actions with dependency caching and Dependabot.
- **Changelog**: `git-cliff` auto-generates from conventional commits.
- **CLI Framework**: Typer for example scripts.

Adding or removing a dependency requires updating `pyproject.toml`, running `uv lock`, and verifying with `make check`.

## Python Standards

### Type Hints

- Use modern Python 3.12+ style: built-in generics (`list[str]`, `dict[str, int]`), union syntax (`X | Y`), and abstract types from `collections.abc`.
- All function and method signatures MUST be fully annotated.
- Accept the broadest reasonable input types and return the narrowest practical types.

### Docstrings (Google Style)

- Modules, classes, functions, and methods MUST include docstrings.
- Docstrings MUST begin immediately after opening quotes with a capital letter and end with a period.
- Class docstrings SHOULD be noun phrases. Function and method docstrings SHOULD be imperative-mood verb phrases.
- Docstrings MUST NOT duplicate parameter types from annotations.
- `Returns:` is required for non-`None` returns. `Raises:` is required for intentionally raised exceptions. `Args:` is optional when signatures are self-explanatory.

### Style

- Be Pythonic. Prefer standard library solutions when they satisfy requirements.
- Raise specific exceptions and avoid silently swallowing errors in core logic.

## Development Workflow & Quality Gates

### Local Development

1. `make develop` installs all dependencies, configures git hooks, and sets up the virtual environment.
2. Contributors work in feature branches and open pull requests.
3. Before committing, contributors MUST run `make check` locally.

### Documentation Hygiene

Documentation decays with code. Any behavior-affecting change MUST update affected docstrings, READMEs, and related documentation in the same commit.

A documentation gap is a bug.

When making significant template changes, the following files MUST be kept in sync:

- `AGENTS.md` and `.AGENTS.md`
- `CLAUDE.md` and `.CLAUDE.md`
- `.github/copilot-instructions.md` and `.github/.copilot-instructions.md`
- `.github/instructions/CI.instructions.md`
- `.specify/memory/constitution.md` and `.specify/memory/.constitution.md`
- `README.md`

Failing to synchronize these files is a constitution violation.

### Template Instantiation Testing

Any change to `setup.sh`, `manifest.txt`, or files included in the manifest SHOULD be validated by running:

```bash
bash setup.sh  # interactive; prompts for setup mode and project name
cd your-project-name
make check
```

## Governance

This constitution is the authoritative reference for all development practices in this repository. It supersedes ad-hoc conventions, verbal agreements, and conflicting documentation.

- **Amendments**: Any change to this constitution MUST be documented with a version bump, rationale, updated `Last Amended` date, and a Sync Impact Report in the HTML comment at the top of this file.
- **Versioning**: Follows semantic versioning. MAJOR for principle removals or incompatible redefinitions; MINOR for new principles or material expansions; PATCH for wording clarifications and typo fixes.
- **Compliance**: All pull requests and code reviews MUST verify adherence to these principles. Violations MUST be flagged and resolved before merge.
- **Runtime Guidance**: For day-to-day development guidance, refer to `CLAUDE.md` (Claude Code), `AGENTS.md` (general agents), and `.github/copilot-instructions.md` (GitHub Copilot).

_When in doubt, choose the approach that is simplest to test._

**Version**: 1.0.0 | **Ratified**: 2026-03-15
