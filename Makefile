PKG ?= $(shell grep -E '^name[[:space:]]*=' pyproject.toml | sed 's/.*=[[:space:]]*"\(.*\)"/\1/')

CONDA_ENV ?= $(shell grep '^name:' environment.yml | awk '{print $$2}')
CONDA_ACTIVATE = source $$(conda info --base)/etc/profile.d/conda.sh ; conda activate ; conda activate

PIP := python -m pip
PIP_INSTALL := $(PIP) install --upgrade

POETRY_FLAGS = $(if $(DEBUG),-vvv,$(if $(VERBOSE),-vv,))
PYTEST_FLAGS = $(if $(DEBUG),-vv,$(if $(VERBOSE),-v,))
RM_FLAGS = -rf$(if $(or $(DEBUG),$(VERBOSE)),v,)
POETRY = poetry $(POETRY_FLAGS)
PYTEST = pytest $(PYTEST_FLAGS)
RM = rm $(RM_FLAGS)

.DEFAULT_GOAL := help
.ONESHELL:

.PHONY: help
help: ## Show this help message
	@echo "\033[1mAvailable targets:\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "\033[1mEnvironment variables:\033[0m"
	@echo "  PKG=<name>          Name of the package (default: read from pyproject.toml)"
	@echo "  CONDA_ENV=<name>    Name of the Conda environment to use (default: read from environment.yml)"
	@echo "  VERBOSE=true|false  Set to true to enable verbose output (default: false)"
	@echo "  DEBUG=true|false    Set to true to enable debug output (default: false)"
	@echo "  CACHE=true|false    Set to false to disable building from cache (default: true)"

.PHONY: install
install: build/install-deps ## Install project dependencies using Poetry
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && $(POETRY) install --only main

.PHONY: uninstall
uninstall:  ## Uninstall the package from the environment
	@rm -rfv build
	@if conda info --envs | grep -qw $(CONDA_ENV); then \
		echo "Activating Conda environment: $(CONDA_ENV)"; \
		$(CONDA_ACTIVATE) $(CONDA_ENV) && $(PIP) uninstall $(PKG) -y; \
	else \
		echo "Conda environment '$(CONDA_ENV)' does not exist. Skipping activation."; \
	fi

.PHONY: reinstall
reinstall: uninstall install  ## Reinstall the package in the environment

.PHONY: clean
CLEAN_DIRS := __pycache__ .mypy_cache .pytest_cache .ipynb_checkpoints
clean: ## Remove build artifacts, caches, and temporary files
	@rm -rfv build dist .coverage .eggs .ruff_cache htmlcov *.egg-info
	@find . -type d \( $(addprefix -name , $(CLEAN_DIRS)) \) -print0 | xargs -0 -P 4 rm -rfv
	@echo "Cleaned up project directories."

.PHONY: clean-uninstall
clean-uninstall: clean uninstall  ## Clean up project artifacts and uninstall the package
	@$(CONDA_ACTIVATE) base && conda env remove -n $(CONDA_ENV) -y || true

.PHONY: clean-reinstall
clean-reinstall: clean-uninstall install  ## Clean up project artifacts and reinstall the package

.PHONY: develop
develop: build/install-pre-commit  ## Install the package in development mode
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && \
		$(POETRY) install && \
		python -m mypy --install-types --non-interactive --package $(PKG) --follow-imports=silent > /dev/null 2>&1 || true && \
		echo "Installed $(PKG) in development mode"

.PHONY: check
check: build/install-test  ## Run all tests with coverage
	@poetry run $(PYTEST) -n auto -v --cov=src --cov-report=term --cov-report=html

.PHONY: test
test: check ## Alias for running tests

.PHONY: bump-version
bump-version: check-poetry  ## Bump the package version (level={patch|minor|major}, default=patch)
	@if [ -z "$(level)" ]; then \
        LEVEL=patch; \
    else \
        LEVEL=$(level); \
    fi; \
    if [ "$$LEVEL" != "major" ] && [ "$$LEVEL" != "minor" ] && [ "$$LEVEL" != "patch" ]; then \
        echo "\033[1;31mInvalid version bump level: $$LEVEL. Please use one of {major, minor, patch}\033[0m"; \
        exit 1; \
    fi; \
	PREVIOUS_VERSION=$$(poetry version --short); \
    NEW_VERSION=$$(poetry version $$LEVEL --short); \
    git add pyproject.toml && \
	git commit --no-verify -m "Bump $$PREVIOUS_VERSION -> $$NEW_VERSION" && \
	{ git tag -a v$$NEW_VERSION -m "Bump version $$PREVIOUS_VERSION -> $$NEW_VERSION" || { \
        echo "Tagging failed, resetting last commit"; \
        git reset HEAD~1; \
        git checkout -- pyproject.toml; \
        exit 1; \
    }; } && \
	echo "\033[1;32mBumped version from $$PREVIOUS_VERSION to $$NEW_VERSION\033[0m" && \
	read -p "Do you want to push the changes? (y/n) " CONFIRM_PUSH; \
    if [ "$$CONFIRM_PUSH" = "y" ] || [ "$$CONFIRM_PUSH" = "Y" ]; then \
        git push && git push --tags || { \
			echo "Push failed, resetting last commit"; \
			git reset HEAD~1; \
			git checkout -- pyproject.toml; \
			exit 1; \
		}; \
	else \
		echo "\033[1;33mChanges not pushed\033[0m"; \
    fi

.PHONY: reformat
reformat: build/install-pre-commit  ## Reformat the code
	@$(POETRY) run pre-commit run --all-files
	@$(POETRY) run ruff check . --fix

.PHONY: check-poetry
check-poetry:  ## Check the Poetry installation
	@poetry --version >/dev/null || { echo "Error: Poetry is not correctly installed or not in PATH."; exit 1; }

build/install-pre-commit: build/install-dev
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && $(POETRY) run pre-commit install
	@touch $@

build/install-dev: build/install-deps
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && $(POETRY) install --only main,dev
	@touch $@

build/install-test: build/install-deps
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && $(POETRY) install --only main,test
	@touch $@

build/install-deps:
	@command -v conda >/dev/null 2>&1 || { echo "Error: conda is not installed."; exit 1; }
	@echo "Checking for Conda environment: $(CONDA_ENV)..."
	@if conda info --envs | grep -qw $(CONDA_ENV); then \
		echo "Updating existing conda environment: $(CONDA_ENV)..."; \
		conda env update -n $(CONDA_ENV) -f environment.yml --prune; \
	else \
		echo "Creating Conda environment: $(CONDA_ENV)"; \
		if [ -f environment.yml ]; then \
			conda env create -f environment.yml -y; \
		else \
			echo "\033[1;31mError: environment.yml not found! Aborting.\033[0m"; \
			exit 1; \
		fi; \
	fi
	@echo "Activating Conda environment and installing dependencies..."
	@$(CONDA_ACTIVATE) $(CONDA_ENV) && \
		$(PIP_INSTALL) pip && \
		$(PIP_INSTALL) poetry && \
	mkdir -p $@

.PHONY: build
build: check-poetry clean ## Build the package using Poetry
	@$(POETRY) build && echo "Package built successfully!"

.PHONY: push-test
push-test: build ## Publish the package to TestPyPI using Poetry
	@$(POETRY) publish --repository testpypi && echo "Package published to TestPyPI!"

.PHONY: push-prod
push-prod: build ## Publish the package to PyPI using Poetry
	@$(POETRY) publish && echo "Package published to PyPI!"
