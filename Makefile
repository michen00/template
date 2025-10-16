VERSION ?= $(shell grep -E '^version[[:space:]]*=' pyproject.toml | sed 's/.*=[[:space:]]*"\(.*\)"/\1/')
VENV = .venv

.ONESHELL:

DEBUG    ?= false
VERBOSE  ?= false

UV_FLAGS = -v
RM_FLAGS := -rfv

ifeq ($(DEBUG),true)
    MAKEFLAGS += --debug=v
    PYTEST_FLAGS := -vv
else ifeq ($(VERBOSE),true)
    PYTEST_FLAGS := -v
else
    MAKEFLAGS += --silent
    PYTEST_FLAGS :=
    UV_FLAGS = -q
    RM_FLAGS := -rf
endif

PYTEST := pytest $(PYTEST_FLAGS)
RM := rm $(RM_FLAGS)
UV := uv $(UV_FLAGS)

PRECOMMIT ?= pre-commit
ifneq ($(shell command -v prek >/dev/null 2>&1 && echo y),)
    PRECOMMIT := prek
    ifneq ($(filter true,$(DEBUG) $(VERBOSE)),)
        $(info Using prek for pre-commit checks)
        ifeq ($(DEBUG),true)
            PRECOMMIT := $(PRECOMMIT) -v
        endif
    endif
endif

# Terminal formatting (tput with fallbacks)
_COLOR  := $(shell tput sgr0 2>/dev/null || echo "\033[0m")
BOLD    := $(shell tput bold 2>/dev/null || echo "\033[1m")
CYAN    := $(shell tput setaf 6 2>/dev/null || echo "\033[36m")
GREEN   := $(shell tput setaf 2 2>/dev/null || echo "\033[32m")
RED     := $(shell tput setaf 1 2>/dev/null || echo "\033[31m")
YELLOW  := $(shell tput setaf 3 2>/dev/null || echo "\033[33m")

.DEFAULT_GOAL := help
.PHONY: help
help: ## Show this help message
	@echo "$(BOLD)Available targets:$(_COLOR)"
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
        awk 'BEGIN {FS = ":.*?## "; max = 0} \
            {if (length($$1) > max) max = length($$1)} \
            {targets[NR] = $$0} \
            END {for (i = 1; i <= NR; i++) { \
                split(targets[i], arr, FS); \
                printf "$(CYAN)%-*s$(_COLOR) %s\n", max + 2, arr[1], arr[2]}}'
	@echo
	@echo "$(BOLD)Environment variables:$(_COLOR)"
	@echo "  $(YELLOW)DEBUG$(_COLOR) = true|false    Set to true to enable debug output (default: false)"
	@echo "  $(YELLOW)VERBOSE$(_COLOR) = true|false  Set to true to enable verbose output (default: false)"

.PHONY: install
install: build/install-python-versions ## Install the project
	$(UV) sync

.PHONY: develop
WITH_HOOKS ?= true
develop: build/install-dev ## Install the project for development (WITH_HOOKS={true|false}, default=true)
	@echo "Installing missing type stubs..." && \
        $(UV) run mypy --install-types --non-interactive --follow-imports=silent > /dev/null 2>&1 || true
	@if [ "$(WITH_HOOKS)" = "true" ]; then \
        $(MAKE) enable-git-hooks; \
    fi
	@git config --local --add include.path "$(CURDIR)/.gitconfigs/alias"
	@git config blame.ignoreRevsFile .git-blame-ignore-revs
	@git lfs install --local; \
       current_branch=$$(git branch --show-current) && \
       if ! git diff --quiet || ! git diff --cached --quiet; then \
           git stash push -m "Auto stash before switching to main"; \
           stash_was_needed=1; \
       else \
           stash_was_needed=0; \
       fi; \
       git checkout main && git pull && \
       git lfs pull && git checkout $$current_branch; \
       if [ $$stash_was_needed -eq 1 ]; then \
           git stash pop; \
       fi

.PHONY: check
PARALLEL ?= false
check: build/install-test ## Run all tests with coverage (PARALLEL={true|false}, default=false)
	@PYTEST_CMD="$(PYTEST)"; [ "$(PARALLEL)" = "true" ] && PYTEST_CMD="$$PYTEST_CMD -n auto"; \
    $(UV) run $$PYTEST_CMD --cov=src --cov-report=term-missing

.PHONY: test
test: check ## Alias for running tests

###############
## Git hooks ##
###############

.PHONY: enable-git-hooks
enable-git-hooks: configure-git-hooks ## Enable Git hooks
	@set -e; \
    mv .gitconfigs/hooks .gitconfigs/hooks.bak && \
    trap 'mv .gitconfigs/hooks.bak .gitconfigs/hooks' EXIT; \
    $(UV) run pre-commit install && \
    mv .git/hooks/pre-commit .githooks/pre-commit && \
    echo "pre-commit hooks moved to .githooks/pre-commit"

.PHONY: enable-pre-commit-only
enable-pre-commit-only: ## Enable pre-commit hooks without enabling commit hooks
	@git config --local --unset-all include.path > /dev/null 2>&1 || true
	@rm -f .githooks/pre-commit && $(UV) run pre-commit install

.PHONY: enable-commit-hooks-only
enable-commit-hooks-only: configure-git-hooks ## Enable commit hooks without enabling pre-commit hooks
	@rm -f .githooks/pre-commit
	@echo "Enabled commit hooks only"

.PHONY: configure-git-hooks
configure-git-hooks: ## Configure Git to use the hooksPath defined in .gitconfig
	@git config --local --add include.path "$(CURDIR)/.gitconfigs/hooks" && \
        echo "Configured Git to use hooksPath defined in .gitconfigs/hooks"

.PHONY: disable-commit-hooks-only
disable-commit-hooks-only: disable-git-hooks enable-commit-hooks-only ## Disable commit hooks and enable pre-commit hooks
	@echo "Disabled commit hooks and enabled pre-commit hooks"

.PHONY: disable-pre-commit-only
disable-pre-commit-only: disable-git-hooks enable-pre-commit-only ## Disable pre-commit hooks and enable commit hooks
	@echo "Disabled pre-commit hooks and enabled commit hooks"

.PHONY: disable-git-hooks
disable-git-hooks: ## Disable the use of Git hooks locally
	@git config --local --unset-all include.path > /dev/null 2>&1 || true
	@git config --local --unset-all core.hooksPath > /dev/null 2>&1 || true
	@rm -f .git/hooks/pre-commit
	@echo "Disabled Git hooks"

################################
## (post-|un|re)?installation ##
################################

.PHONY: uninstall
uninstall: check-install-uv ## Uninstall the project
	@echo "Uninstalling project..."
	$(UV) pip uninstall .

.PHONY: reinstall
reinstall: uninstall install ## Reinstall the project

.PHONY: reinstall-dev
reinstall-dev: uninstall develop ## Reinstall the project for development (WITH_HOOKS={true|false}, default=true)

.PHONY: clean
TO_REMOVE := \
    *.egg-info \
    */.venv \
    .coverage \
    .eggs \
    .git/hooks/pre-commit \
    .githooks/pre-commit \
    .ipynb_checkpoints \
    .mypy_cache \
    .pytest_cache \
    .ruff_cache \
    __pycache__ \
    build \
    dist \
    htmlcov \
    node_modules
clean: ## Remove build artifacts, caches, and temporary files
	@echo "Cleaning up project directories..."
	@if [ -n "$$VIRTUAL_ENV" ]; then deactivate; fi; \
    echo $(TO_REMOVE) | xargs -n 1 -P 4 $(RM); \
    find . -type d -name "__pycache__" -exec $(RM) {} +
	@echo "Cleaned up project directories."
	@$(RM) $(VENV)

.PHONY: clean-uninstall
clean-uninstall: clean uninstall ## Clean up project artifacts and uninstall the package

.PHONY: clean-reinstall
clean-reinstall: clean-uninstall install ## Clean up project artifacts and reinstall the package

.PHONY: clean-reinstall-dev
clean-reinstall-dev: clean-uninstall develop ## Clean up project artifacts and reinstall the package for development (WITH_HOOKS={true|false}, default=true)

##################
## code quality ##
##################

.PHONY: format-all
format-all: ## Run code-quality checks and format the code
	-$(MAKE) run-pre-commit
	@$(MAKE) format-unsafe

.PHONY: ruff-format
ruff-format: build/install-dev ## Format the code with Ruff
	$(UV) run ruff format
	@echo "$(BOLD)$(GREEN)Code formatting complete!$(_COLOR)"

.PHONY: lint
lint: build/install-dev ## Lint the code with Ruff, fixing issues where possible
	$(UV) run ruff check --fix
	@$(MAKE) .display-lint-complete

.PHONY: lint-unsafe
lint-unsafe: build/install-dev ## Lint the code with Ruff, fixing issues where possible with --unsafe-fixes
	$(UV) run ruff check --fix --unsafe-fixes --exit-zero
	@$(MAKE) .display-lint-complete

.PHONY: format
format: lint ruff-format ## Format the code with Ruff

.PHONY: format-unsafe
format-unsafe: lint-unsafe ruff-format ## Format the code with Ruff using --unsafe-fixes

.PHONY: run-pre-commit
run-pre-commit: build/install-dev ## Run the pre-commit checks
	@if [ -s .githooks/pre-commit ] || [ -s .git/hooks/pre-commit ]; then \
        :; \
    else \
        echo "Pre-commit hooks missing. Installing pre-commit hooks..."; \
        $(MAKE) enable-pre-commit-only; \
    fi
	$(UV) run $(PRECOMMIT) run --all-files

.PHONY: .display-lint-complete
.display-lint-complete: ## Display a message when linting is complete
	@echo "$(BOLD)$(YELLOW)Linting complete!$(_COLOR)"

###########################
## development shortcuts ##
###########################

.PHONY: check-install-uv
check-install-uv: ## Check if uv is installed
	@set -e; \
    command -v uv >/dev/null 2>&1 || { \
        echo "$(BOLD)$(RED)installing uv$(RESET)"; \
        curl -LsSf https://astral.sh/uv/install.sh | sh; \
    }

.PHONY: bust-ci-cache
bust-ci-cache: ## Bust the CI cache
	@CACHE_BUSTER=.github/workflows/.cache-buster && \
    date > $$CACHE_BUSTER && \
    git add $$CACHE_BUSTER && \
    git commit -m "ci: bust cache on $$(date +'%Y-%m-%d %H:%M')"

.PHONY: push-test
push-test: build ## Publish the package to TestPyPI using Poetry
	@$(UV) publish --index testpypi && echo "Package published to TestPyPI!"

.PHONY: push-prod
push-prod: build ## Publish the package to PyPI using Poetry
	@$(UV) publish && echo "Package published to PyPI!"

##############
## building ##
##############

.PHONY: build
CACHE ?= true
build: check-install-uv clean ## Build the package using uv (CACHE={true|false}, default=true)
	$(UV) build $(if $(filter false,$(CACHE)),--no-cache,) && echo "Package built successfully!"

MARKER_FILE = build/$(VERSION).marker

$(MARKER_FILE):
	@echo "$(BOLD)$(YELLOW)You are on new prerequisites $(VERSION)! Removing build markers before rebuilding$(_COLOR)"
	@$(RM) build
	@$(MAKE) MARKER_FILE= > /dev/null
	@mkdir -p $(@D)
	@touch $@

include $(MARKER_FILE)

build/install-dev: build/install-deps
	$(UV) sync --only-dev
	touch $@

build/install-test: build/install-deps
	$(UV) sync --only-group test
	touch $@

build/install-deps: build/install-python-versions
	$(UV) sync --no-editable --no-install-project
	mkdir -p $(dir $@) && touch $@

.PHONY: check-install-uv build/install-python-versions
build/install-python-versions:
	$(UV) python install $(shell cat .python-version)
