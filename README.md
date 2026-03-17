# Python Project Template

A production-ready Python project template that gets you up and running in minutes with modern tooling, best practices, and CI/CD already configured.

> **Note:** This template reflects my personal preferences and opinions about Python project setup. The tooling choices, configurations, and conventions are tailored to my workflow. Feel free to customize it to match your own preferences!

## Why Use This Template?

This template helps you set up:

- Dependency management and virtual environments
- Linting, formatting, and type checking
- Testing framework and coverage
- Pre-commit hooks and CI/CD pipelines
- Project structure and documentation
- Git configuration and workflows

**This template gives you all of that, configured and ready to go.**

## What's Included

### 🚀 Modern Python Tooling

- **[`uv`](https://github.com/astral-sh/uv)** - Lightning-fast Python package manager (replaces pip, pip-tools, poetry)
- **[`ruff`](https://github.com/astral-sh/ruff)** - Fast Python linter and formatter (replaces black, isort, flake8, autoflake, and more)
- **[`mypy`](https://mypy.readthedocs.io/)** - Static type checker with strict mode enabled
- **[`pytest`](https://pytest.org/)** - Testing framework with coverage reporting
- **[`nox`](https://nox.thea.codes/)** - Reproducible CI environments

### ✅ Quality Assurance Out of the Box

- **Pre-commit hooks** for:
  - Security scanning (gitleaks, talisman)
  - Code formatting (ruff, prettier, shfmt, markdownlint)
  - Linting (ruff, pylint, shellcheck, actionlint, yamllint)
  - Spell checking (codespell, typos)
  - Type checking (mypy)
  - Git commit message validation (conventional commits)
- **Custom linter configurations** included:
  - `.ruff.toml` - Ruff linting and formatting rules
  - `.pylintrc` - Pylint configuration
  - `.codespellrc` - Spell checking configuration
  - `.markdownlint.yml` - Markdown linting rules
  - `.yamllint` - YAML linting configuration
  - `.gitlint` - Git commit message linting
  - `.editorconfig` - Editor configuration for consistent formatting
  - `pyproject.toml` - Mypy strict type checking configuration
- **GitHub Actions workflows** for:
  - Automated testing and linting on every PR
  - Dependabot for dependency updates
  - Contributor greeting automation

### 🛠️ Developer Experience

- **Makefile** with common tasks (`make develop`, `make check`, `make test`, etc.)
- **VS Code configuration** with recommended extensions and settings
- **Git hooks** configured via `make develop`
- **Git LFS** support for large files
- **Blame ignore** for formatting commits

### 📦 Project Structure

- Modern `src/` layout (PEP 420 compliant)
- Type stubs (`py.typed`) for package distribution
- Example CLI script with [Typer](https://typer.tiangolo.com/)
- Organized test structure with pytest
- Pre-configured for PyPI publishing

### 📚 Documentation & Standards

- [Conventional Commits](https://www.conventionalcommits.org/) for version control
- [git-cliff](https://git-cliff.org/) for automated changelog generation
- Contributing guidelines and code of conduct
- **AI assistant instructions** to help AI tools understand your project:
  - `AGENTS.md` - Instructions for AI agents
  - `CLAUDE.md` - Claude Code-specific instructions
  - `.github/copilot-instructions.md` - GitHub Copilot instructions
  - `.github/instructions/CI.instructions.md` - CI workflow instructions for AI agents

## Quick Start

### Option A: Use this template (GitHub)

1. Click **"Use this template"** on GitHub to create a new repository.
2. Clone your new repo:

   ```bash
   git clone https://github.com/<you>/<your-repo>.git
   cd <your-repo>
   ```

3. Edit `.template-profile.sh` — set `GITHUB_OWNER`, `AUTHOR_NAME`, and `AUTHOR_EMAIL` to your values.
4. Run the setup script:

   ```bash
   bash setup.sh
   ```

5. Follow the prompts (setup mode and project name).
6. Start developing:

   ```bash
   make develop        # Install dependencies and set up git hooks
   make check          # Run all quality checks
   ```

### Option B: Clone and run

1. Clone and enter the template:

   ```bash
   git clone https://github.com/michen00/template.git
   cd template
   ```

2. Edit `.template-profile.sh` — set `GITHUB_OWNER`, `AUTHOR_NAME`, and `AUTHOR_EMAIL` to your values.
3. Run the setup script:

   ```bash
   bash setup.sh
   ```

4. Follow the prompts (setup mode and project name).
5. Start developing:

   ```bash
   cd your-project-name
   make develop        # Install dependencies and set up git hooks
   make check          # Run all quality checks
   ```

> **For template maintainers:** Named profiles can be defined in `.template-profile.sh` and activated with `setup.sh --profile <name>` to skip editing the defaults.

## What Gets Generated

After running `setup.sh`, you'll have a fully configured Python project with:

- ✅ All dependencies configured in `pyproject.toml`
- ✅ Pre-commit hook configuration (run `make develop` to install)
- ✅ Custom linter configurations (ruff, pylint, mypy, codespell, etc.)
- ✅ GitHub Actions workflows for CI/CD
- ✅ VS Code settings for consistent development
- ✅ Testing framework with coverage
- ✅ Type checking configured with strict mypy settings
- ✅ AI assistant instructions (AGENTS.md, CLAUDE.md, Copilot instructions)
- ✅ Project constitution (`.specify/memory/constitution.md`) with design principles and coding standards
- ✅ Documentation templates
- ✅ Example CLI script to get you started

## Key Features

### Fast Dependency Management

`uv` is 10-100x faster than pip and provides:

- Automatic virtual environment management
- Lock file support (`uv.lock`)
- Fast dependency resolution
- Works seamlessly with existing Python workflows

### Comprehensive Code Quality

The template includes multiple layers of quality checks with carefully tuned configurations:

- **Formatting**: Automatic code formatting with ruff (custom `.ruff.toml` config)
- **Linting**: Multiple linters (ruff, pylint, shellcheck, yamllint) with pre-configured rules
- **Type Safety**: Strict mypy configuration in `pyproject.toml` catches type errors early
- **Security**: Automated secret scanning in commits (gitleaks, talisman)
- **Documentation**: Spell checking (codespell) and markdown linting with custom configs
- **Git Hygiene**: Git commit message validation (gitlint) and editor consistency (editorconfig)

### CI/CD Ready

GitHub Actions workflows are pre-configured to:

- Run tests on every pull request
- Check code quality automatically
- Cache dependencies for faster runs
- Support parallel test execution

### Developer-Friendly

- Simple `make` commands for common tasks
- Pre-configured editor settings
- Git hooks managed via pre-commit
- Clear project structure
- Comprehensive documentation

## Requirements

- Python 3.13+
- [`uv`](https://docs.astral.sh/uv/getting-started/installation/)
- Git

## Common Tasks

```bash
make develop          # Install dependencies and configure git hooks
make check            # Run all quality checks (formatting, linting, type checking, tests)
make test             # Run tests with coverage
make lint             # Run linters with auto-fix
make tidy             # Auto-fix lint issues and format code
make format           # Format code
make clean            # Remove build artifacts and caches
```

## Documentation

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/michen00/template)

For detailed information about:

- Project structure and conventions
- Development workflow
- Contributing guidelines
- CI/CD configuration

See the generated project's documentation files after setup.
