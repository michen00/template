VENV = .venv

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

DEBUG    ?= false
VERBOSE  ?= false

UV_FLAGS = -v
RM_FLAGS := -rfv
CHECK_UV_CMD = command -v uv >/dev/null 2>&1 || { \
    echo "$(BOLD)$(RED)uv is required but not installed.$(_COLOR)"; \
    echo "Install uv: https://docs.astral.sh/uv/getting-started/installation/"; \
    exit 1; \
}

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

# Terminal formatting (tput with fallbacks to ANSI codes)
_COLOR  := $(shell tput sgr0 2>/dev/null || printf '\033[0m')
BOLD    := $(shell tput bold 2>/dev/null || printf '\033[1m')
CYAN    := $(shell tput setaf 6 2>/dev/null || printf '\033[0;36m')
GREEN   := $(shell tput setaf 2 2>/dev/null || printf '\033[0;32m')
RED     := $(shell tput setaf 1 2>/dev/null || printf '\033[0;31m')
YELLOW  := $(shell tput setaf 3 2>/dev/null || printf '\033[0;33m')

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
install: check-install-uv build/install-python-versions ## Install the project
	$(UV) sync

.PHONY: develop
WITH_HOOKS ?= true
WITH_SYNC_MAIN ?= false
develop: check-install-uv build/install-dev ## Install the project for development (WITH_HOOKS={true|false}, default=true)
	@echo "Installing missing type stubs..." && \
        $(UV) run mypy --install-types --non-interactive --follow-imports=silent > /dev/null 2>&1 || true
	@if ! git config --local --get-all include.path | grep -q ".gitconfigs/alias"; then \
        git config --local --add include.path "$(CURDIR)/.gitconfigs/alias"; \
    fi
	@git config blame.ignoreRevsFile .git-blame-ignore-revs
	@set -e; \
    if command -v git-lfs >/dev/null 2>&1; then \
        git lfs install --local --skip-repo || true; \
    fi
	@if [ "$(WITH_SYNC_MAIN)" = "true" ]; then \
        $(MAKE) sync-main; \
    fi
	@if [ "$(WITH_HOOKS)" = "true" ]; then \
        $(MAKE) enable-pre-commit; \
    fi

.PHONY: test
PARALLEL ?= false
test: check-install-uv build/install-test ## Run all tests with coverage (PARALLEL={true|false}, default=false)
	@PYTEST_CMD="$(PYTEST)"; [ "$(PARALLEL)" = "true" ] && PYTEST_CMD="$$PYTEST_CMD -n auto"; \
    $(UV) run $$PYTEST_CMD

.PHONY: check
check: tidy ## Run all code quality checks and tests
	$(MAKE) run-pre-commit HOOK_STAGE=pre-commit
	$(MAKE) run-pre-commit HOOK_STAGE=pre-push
	$(MAKE) test

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
    $(VENV) \
    *.egg-info \
    */.venv \
    .coverage \
    .eggs \
    .git/hooks/commit-msg \
    .git/hooks/pre-commit \
    .git/hooks/pre-push \
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
	@echo $(TO_REMOVE) | xargs -n 1 -P 4 $(RM); \
    find . -type d -name "__pycache__" -exec $(RM) {} +
	@echo "Cleaned up project directories."

.PHONY: clean-uninstall
clean-uninstall: clean uninstall ## Clean up project artifacts and uninstall the package

.PHONY: clean-reinstall
clean-reinstall: clean-uninstall ## Clean up project artifacts and reinstall the package
	@$(MAKE) install

.PHONY: clean-reinstall-dev
clean-reinstall-dev: clean-uninstall ## Clean up project artifacts and reinstall the package for development (WITH_HOOKS={true|false}, default=true)
	@$(MAKE) develop

##################
## code quality ##
##################

.PHONY: format-markdown
format-markdown: ## Run Prettier on all markdown files in the project
	npx --yes prettier --write '**/*.md'

.PHONY: format
format: check-install-uv build/install-dev ## Format the code with Ruff
	$(UV) run ruff format
	@echo "$(BOLD)$(GREEN)Code formatting complete!$(_COLOR)"

.PHONY: lint
lint: check-install-uv build/install-dev ## Lint the code with Ruff, fixing issues where possible
	$(UV) run ruff check --fix
	@$(MAKE) .display-lint-complete

.PHONY: tidy
tidy: check-install-uv build/install-dev ## Auto-fix lint issues and format the code
	$(UV) run ruff check --fix --unsafe-fixes --exit-zero
	@$(MAKE) .display-lint-complete
	$(UV) run ruff format
	@echo "$(BOLD)$(GREEN)Code formatting complete!$(_COLOR)"

.PHONY: tidy-all
tidy-all: ## Run pre-commit hooks and auto-fix the code
	-$(MAKE) run-pre-commit
	@$(MAKE) tidy

.PHONY: .display-lint-complete
.display-lint-complete:
	@echo "$(BOLD)$(YELLOW)Linting complete!$(_COLOR)"

.PHONY: sync-main
sync-main: ## Sync local branch with latest main
	@set -e; \
    current_branch=$$(git branch --show-current); \
    stash_was_needed=0; \
    cleanup() { \
        exit_code=$$?; \
        if [ "$$current_branch" != "$$(git branch --show-current)" ]; then \
            echo "$(YELLOW)Warning: Still on $$(git branch --show-current). Attempting to return to $$current_branch...$(_COLOR)"; \
            if git switch "$$current_branch" 2>/dev/null; then \
                echo "Successfully returned to $$current_branch"; \
            else \
                echo "$(YELLOW)Could not return to $$current_branch. You are on $$(git branch --show-current).$(_COLOR)"; \
            fi; \
        fi; \
        if [ $$stash_was_needed -eq 1 ] && git stash list | head -1 | grep -q "Auto stash before switching to main"; then \
            echo "$(YELLOW)Note: Your stashed changes are still available. Run 'git stash pop' to restore them.$(_COLOR)"; \
        fi; \
        exit $$exit_code; \
    }; \
    trap cleanup EXIT; \
    if ! git diff --quiet || ! git diff --cached --quiet; then \
        git stash push -m "Auto stash before switching to main"; \
        stash_was_needed=1; \
    fi; \
    git switch main && git pull; \
    if command -v git-lfs >/dev/null 2>&1; then \
        git lfs pull || true; \
    fi; \
    git switch "$$current_branch"; \
    if [ $$stash_was_needed -eq 1 ]; then \
        if git stash apply; then \
            git stash drop; \
        else \
            echo "$(RED)Error: Stash apply had conflicts. Resolve them, then run: git stash drop$(_COLOR)"; \
        fi; \
    fi; \
    trap - EXIT

.PHONY: enable-pre-commit
enable-pre-commit: check-install-uv ## Enable pre-commit hooks
	@if $(UV) run pre-commit --version >/dev/null 2>&1; then \
        $(UV) run pre-commit install; \
    else \
        echo "$(YELLOW)Warning: pre-commit is not installed. Skipping hook installation.$(_COLOR)"; \
        echo "Install it with: uv sync (or make develop)"; \
    fi

.PHONY: disable-pre-commit
disable-pre-commit: check-install-uv ## Disable pre-commit hooks
	@if $(UV) run pre-commit --version >/dev/null 2>&1; then \
        $(UV) run pre-commit uninstall; \
        echo "$(BOLD)$(GREEN)Pre-commit hooks disabled.$(_COLOR)"; \
    else \
        echo "$(YELLOW)Warning: pre-commit is not installed. Nothing to disable.$(_COLOR)"; \
        echo "Install it with: uv sync (or make develop)"; \
    fi

.PHONY: run-pre-commit
HOOK_STAGE ?= pre-commit
run-pre-commit: check-install-uv build/install-dev ## Run the pre-commit checks (HOOK_STAGE=pre-commit|pre-push|commit-msg|... to run only that stage)
	$(UV) run $(PRECOMMIT) run --all-files $(if $(HOOK_STAGE),--hook-stage $(HOOK_STAGE),)

###########################
## development shortcuts ##
###########################

.PHONY: check-install-uv
check-install-uv: ## Check if uv is installed
	@set -e; $(CHECK_UV_CMD)

.PHONY: bust-ci-cache
bust-ci-cache: ## Bust the CI cache
	@CACHE_BUSTER=.github/workflows/.cache-buster && \
    date > $$CACHE_BUSTER && \
    git add $$CACHE_BUSTER && \
    git commit -m "ci: bust cache on $$(date +'%Y-%m-%d %H:%M')"

.PHONY: push-test
push-test: build ## Publish the package to TestPyPI using uv
	@$(UV) publish --index testpypi && echo "Package published to TestPyPI!"

.PHONY: push-prod
push-prod: build ## Publish the package to PyPI using uv
	@$(UV) publish && echo "Package published to PyPI!"

##############
## building ##
##############

.PHONY: build
CACHE ?= true
build: check-install-uv ## Build the package using uv (CACHE={true|false}, default=true)
	$(UV) build $(if $(filter false,$(CACHE)),--no-cache,) && echo "Package built successfully!"

.PHONY: rebuild
rebuild: clean ## Clean up artifacts and build the package from scratch
	@$(MAKE) build

SYNC_INPUTS = pyproject.toml .python-version $(wildcard uv.lock)
VENV_MARKER = $(VENV)/pyvenv.cfg

$(VENV_MARKER): .python-version
	@set -e; $(CHECK_UV_CMD); $(UV) venv --python $(shell cat .python-version) $(VENV)

build/install-dev: build/install-deps
	$(UV) sync --inexact --only-dev
	mkdir -p $(dir $@) && touch $@

build/install-test: build/install-deps
	$(UV) sync --inexact --only-group test
	mkdir -p $(dir $@) && touch $@

build/install-deps: build/install-python-versions $(VENV_MARKER) $(SYNC_INPUTS)
	@set -e; $(CHECK_UV_CMD); $(UV) sync --no-editable --no-install-project
	mkdir -p $(dir $@) && touch $@

build/install-python-versions: .python-version
	@set -e; $(CHECK_UV_CMD); $(UV) python install $(shell cat .python-version)
	mkdir -p $(dir $@) && touch $@
