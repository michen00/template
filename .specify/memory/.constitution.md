# Project Constitution

## Core Principles

### I. Design Philosophy

Start simple. Reject speculative complexity.

- Complexity is acceptable; complication is not. Readability comes first.
- Elegant code is easy to change. Prefer modularity and reusability over monoliths and clever one-offs.
- Delay irreversible architectural decisions until enough information is available.
- Do not add features, abstractions, or configurability beyond what is currently required.
- Three similar lines of code are preferable to a premature abstraction.
- Error handling and validation SHOULD exist only at system boundaries (user input, external APIs), not for impossible internal states.
- If a simpler alternative exists, it MUST be chosen unless a concrete, documented justification is provided.

### II. Code Quality and Structure

- Use clear module boundaries; avoid god modules.
- Favor small, composable functions with explicit inputs and outputs.
- Prefer well-understood patterns over cleverness unless measurable benefits are demonstrated.
- Keep core logic side-effect-free where practical; I/O adapters (files, network, DB, APIs) are thin wrappers around the core.
- Make refactors safe through strong automated test coverage.

## Technology Stack & Constraints

- **Language**: defined in `.python-version` and `pyproject.toml`.
- **Package Manager**: `uv` for dependency management, virtual environments, and lock files.
- **Linting/Formatting**: `ruff`.
- **Type Checking**: `mypy` in strict mode.
- **Testing**: `pytest` with coverage reporting.
- **Pre-commit**: Hooks for code quality, security scanning, type checking, and commit message validation.
- **CI/CD**: GitHub Actions.
- **Changelog**: `git-cliff` auto-generates from conventional commits.

Adding or removing a dependency requires updating `pyproject.toml`, running `uv lock`, and verifying with `make check`.

## Python Standards

### Type Hints

- Use modern Python 3.12+ style: built-in generics (`list[str]`, `dict[str, int]`), union syntax (`X | Y`), and abstract types from `collections.abc`.
- All function and method signatures MUST be fully annotated.
- Accept the broadest reasonable input types and return the narrowest practical types.

### Docstrings (Google Style)

- Modules, classes, functions, and methods MUST include docstrings. Test modules are the exception; see below.
- Docstrings MUST begin immediately after opening quotes with a capital letter and end with a period.
- Module docstrings SHOULD be noun phrases summarizing what the module provides, as class docstrings are (`Frame loading and S3 caching.`). Ruff `D401` does not check them. A test module needs a docstring only when it adds information a reader needs, such as how to run the tests, an unusual setup, or an external dependency; `Tests for foo.bar.` adds nothing. `tests/**` is exempt from `D100`.
- Class docstrings SHOULD be noun phrases. Function and method docstrings SHOULD be imperative-mood verb phrases. Exception: any callable returning `bool` MAY use a "Whether ..." state-predicate docstring.
- `@property` docstrings for non-boolean return types SHOULD be noun phrases describing the computed value.
- Class names SHOULD be noun-like. Function and method names SHOULD be verb-like for dynamic actions. Exception: any callable returning `bool` MAY use stative-predicate names such as `is_ready`, `has_data`, or `can_retry`.
- `@property` names for non-boolean return types SHOULD be noun-like. Boolean properties MAY use bare adjectives such as `valid` or `empty`.
- **Test functions and methods invert the imperative-mood rule.** They MUST be named `test_*` (pytest's collection contract). Their docstrings MUST state a truth-apt proposition in the present-tense indicative -- the falsifiable claim the test body exists to refute -- not an imperative verb phrase. `Identical flat dicts score 1.0.`, `Unknown nested keys are rejected.` (passive), and `The schema rejects unknown nested keys.` (active) are all correct; `Reject unknown nested keys.` (imperative) and `Assert that identical flat dicts score 1.0.` (framing verb) are not. Active and passive voice are equally acceptable -- pick whichever reads as the clearest claim; a trailing `..., so <why it matters>` clause is OPTIONAL. This inversion covers test function and method docstrings only. Module docstrings follow the module rule above. `tests/**/test_*.py` is exempt from `D401` so declarative first lines pass lint; because per-file ignores are file-scoped, that exemption also lifts `D401` from non-test helper functions defined in those files. Dedicated helper modules (`conftest.py`, `_*.py`) keep imperative-mood enforcement.
- Docstrings MUST NOT duplicate parameter types from annotations.
- A one-line docstring MAY omit `Args:`, `Returns:`, and `Raises:` when the name and annotations say everything. A docstring with a body MUST include `Returns:` for a non-`None` return and `Raises:` for each intentionally raised exception; `Args:` stays optional when the signature is self-explanatory. Ruff `DOC201` and `DOC501` enforce this; `DOC201` accepts a summary that begins `Return ...` as documenting the return.
- When the annotation hides what a return means, write a body with a `Returns:` section: what each element of a tuple is, the expected keys of a mapping, the shape, dtype and units of an array, and the meaning of any sentinel value.

### Style

- Be Pythonic. Prefer standard library solutions when they satisfy requirements.
- Raise specific exceptions and avoid silently swallowing errors in core logic.

## Engineering Discipline

### Quality Gates

All code MUST pass `make check` before being committed. This command runs formatting, linting, type checking, and tests.

- Pre-commit hooks MUST remain active; contributors MUST NOT bypass them with `--no-verify`.
- CI reproduces these checks on every pull request.

### Conventional Commits

All commits MUST follow the Conventional Commits specification: `<type>(<scope>): <subject>`.

- Types: `feat`, `fix`, `docs`, `chore`, `style`, `test`, `build`, `ci`, `refactor`, `perf`, `revert`.
- Subject line MUST be imperative mood, lowercase start, and under 51 characters.
- Body lines MUST wrap at 72 characters.
- Each commit MUST represent one atomic logical change.
- `git-cliff` generates the changelog from these commits; commits are the source of truth. Do not hand-maintain `## [Unreleased]` (regenerate via `git cliff --unreleased` or `scripts/update-unreleased.sh`). Manual edits are limited to released sections for light curation, factual corrections, or formatting cleanup.

### Documentation Hygiene

Documentation decays with code. Any behavior-affecting change MUST update affected docstrings, READMEs, and related documentation in the same commit.

A documentation gap is a bug.

## Governance

This constitution is the authoritative reference for all development practices in this repository. It supersedes ad-hoc conventions, verbal agreements, and conflicting documentation.

- **Amendments**: Any change to this constitution MUST be documented with a version bump and rationale.
- **Versioning**: Follows semantic versioning. MAJOR for principle removals or incompatible redefinitions; MINOR for new principles or material expansions; PATCH for wording clarifications and typo fixes.
- **Compliance**: All pull requests and code reviews MUST verify adherence to these principles. Violations MUST be flagged and resolved before merge.

_When in doubt, choose the approach that is simplest to test._

**Version**: 1.1.0 | **Ratified**: 2026-03-15 | **Last amended**: 2026-10-14
