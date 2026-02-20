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
- **Git hooks** automatically configured on setup
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
  - `AGENTS.md` - Instructions for AI agents working on the template
  - `CLAUDE.md` - Claude Code-specific instructions
  - `.github/copilot-instructions.md` - GitHub Copilot instructions

## Quick Start

1. **Clone this repository:**

   ```bash
   git clone https://github.com/michen00/template.git
   cd template
   ```

2. **Run the setup script:**

   ```bash
   bash setup.sh
   ```

3. **Follow the prompts:**

   - Choose whether to set up in the current directory or create a new one
   - Enter your project name
   - Enter your GitHub owner (username or organization)
   - Select a profile: **Public** (all community features) or **Private** (excludes contributor greeter, DeepWiki badge)
   - The script will automatically:
     - Copy all template files (filtered by profile)
     - Rename placeholders to your project name
     - Replace owner in repository URLs
     - Set up the project structure
     - Generate a fresh `.gitignore` from GitHub templates

   You can also skip interactive prompts with CLI flags:

   ```bash
   bash setup.sh --profile=private --owner=acme-corp
   ```

4. **Start developing:**

   ```bash
   cd your-project-name
   make develop        # Install dependencies and set up git hooks
   make check          # Run all quality checks
   ```

## What Gets Generated

After running `setup.sh`, you'll have a fully configured Python project with:

- ✅ All dependencies configured in `pyproject.toml`
- ✅ Pre-commit hooks ready to use
- ✅ Custom linter configurations (ruff, pylint, mypy, codespell, etc.)
- ✅ GitHub Actions workflows for CI/CD
- ✅ VS Code settings for consistent development
- ✅ Testing framework with coverage
- ✅ Type checking configured with strict mypy settings
- ✅ AI assistant instructions (AGENTS.md, CLAUDE.md, Copilot instructions)
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
- Git hooks that run automatically
- Clear project structure
- Comprehensive documentation

## Requirements

- Python >= 3.11
- `uv` (will be installed automatically if missing via `make develop`)
- Git

## Common Tasks

```bash
make develop          # Install dependencies and configure git hooks
make check            # Run all quality checks (formatting, linting, tests)
make test             # Run tests with coverage
make lint             # Run linters with auto-fix
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
