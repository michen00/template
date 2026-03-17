#!/usr/bin/env bash

set -euo pipefail

read -r -d '' USAGE << 'EOF' || true
setup.sh integration smoke test

Description:
  Duplicate the template repo into isolated workspaces, exercise `setup.sh`
  in both supported modes (in-place and "new directory"), and assert the
  generated project layout plus token replacement are correct.

Usage:
  ./test_setup.sh [options]

Options:
  -h, --help     Show this message and exit.
  -v, --verbose  Print the captured setup.sh output and a run summary.

Requirements:
  - rsync
  - python3 (or python)
  - git
EOF

RESET=$'\033[0m'
GREEN=$'\033[32m'
RED=$'\033[31m'
CYAN=$'\033[36m'

VERBOSE=false

while (($#)); do
  case "$1" in
    -h | --help)
      printf '%s\n' "$USAGE"
      exit 0
      ;;
    -v | --verbose)
      VERBOSE=true
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf '%s[ERROR]%s Unknown option: %s\n' "$RED" "$RESET" "$1" >&2
      printf '%s\n' "$USAGE"
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

printf '%s==>%s setup.sh integration smoke test\n' "$CYAN" "$RESET"

if ! command -v rsync > /dev/null 2>&1; then
  printf '%s[ERROR]%s rsync is required to run this test.\n' "$RED" "$RESET" >&2
  exit 1
fi

PYTHON_BIN="$(command -v python3 || command -v python)"
if [[ -z $PYTHON_BIN ]]; then
  printf '%s[ERROR]%s python3 (or python) is required to run this test.\n' "$RED" "$RESET" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORK_ROOT="$(mktemp -d -t template-setup-test-XXXXXX)"
cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

copy_template() {
  local dest="$1"
  mkdir -p "$dest"
  printf -- '-- copying template -> %s\n' "$dest"
  rsync -a --exclude ".git" "$REPO_ROOT"/ "$dest"/
}

copy_template_with_git() {
  local dest="$1"
  copy_template "$dest"
  (
    cd "$dest"
    git init -q
    git remote add origin "git@github.com:example/template.git"
  )
}

copy_template_with_git_worktree() {
  local repo_dir="$1"
  local worktree_dest="$2"
  local branch_name

  branch_name="fixture-worktree-$(date +%s)-$RANDOM"

  copy_template "$repo_dir"
  (
    cd "$repo_dir"
    git init -q
    git -c user.name="Setup Test" -c user.email="setup@example.com" add -A
    git -c user.name="Setup Test" -c user.email="setup@example.com" -c commit.gpgsign=false commit -q -m "Initial commit"
    git remote add origin "git@github.com:example/template.git"
    git worktree add -q "$worktree_dest" -b "$branch_name"
  )
}

run_setup_with_inputs() {
  local workdir="$1"
  local description="$2"
  local inputs="$3"
  local expected_exit="${4:-0}"

  pushd "$workdir" > /dev/null

  if $VERBOSE; then
    export TEST_SETUP_VERBOSE=1
  else
    export TEST_SETUP_VERBOSE=0
  fi
  export SETUP_SH_QUIET=1
  export SETUP_TEST_INPUTS="$inputs"
  export SETUP_TEST_EXPECTED_EXIT="$expected_exit"

  printf -- '-- running setup.sh (%s)\n' "$description"
  "$PYTHON_BIN" << 'PY'
import os
import pty
import subprocess
import sys
import time

inputs_raw = os.environ.get("SETUP_TEST_INPUTS", "").splitlines()
if not inputs_raw:
    sys.stderr.write("Missing SETUP_TEST_INPUTS for setup.sh invocation\n")
    sys.exit(1)

verbose = os.environ.get("TEST_SETUP_VERBOSE") == "1"
expected_exit = int(os.environ.get("SETUP_TEST_EXPECTED_EXIT", "0"))
os.environ["SETUP_SH_QUIET"] = os.environ.get("SETUP_SH_QUIET", "1")

env = os.environ.copy()
controller_fd, client_fd = pty.openpty()
process = subprocess.Popen(
    ["./setup.sh"],
    stdin=client_fd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)
os.close(client_fd)

for line in inputs_raw:
    os.write(controller_fd, (line + "\n").encode())
    time.sleep(0.2)

os.close(controller_fd)
stdout, stderr = process.communicate()

should_display = verbose or process.returncode != expected_exit or (
    expected_exit == 0 and "Warning:" in stderr
)

if should_display:
    if stdout:
        sys.stdout.write(stdout)
    if stderr:
        sys.stderr.write(stderr)

if expected_exit == 0 and "Warning:" in stderr:
    sys.exit(1)

if process.returncode != expected_exit:
    sys.exit(process.returncode or 1)
PY

  popd > /dev/null
}

assert_path_missing() {
  local path="$1"

  if [[ -e $path ]]; then
    printf '%s[ERROR]%s expected path %s to be removed.\n' "$RED" "$RESET" "$path" >&2
    exit 1
  fi
}

assert_git_remote_url_equals() {
  local project_root="$1"
  local expected="$2"
  local actual

  actual="$(git -C "$project_root" config --get remote.origin.url || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s[ERROR]%s expected git remote %s but found %s.\n' \
      "$RED" "$RESET" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_git_remote_url_absent() {
  local project_root="$1"
  local actual

  actual="$(git -C "$project_root" config --get remote.origin.url || true)"
  if [[ -n "$actual" ]]; then
    printf '%s[ERROR]%s expected git remote to be absent, but found %s.\n' \
      "$RED" "$RESET" "$actual" >&2
    exit 1
  fi
}

assert_git_repository_exists() {
  local project_root="$1"

  if ! git -C "$project_root" rev-parse --git-dir > /dev/null 2>&1; then
    printf '%s[ERROR]%s expected git repository at %s.\n' \
      "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi
}

assert_git_has_no_commits() {
  local project_root="$1"

  if git -C "$project_root" rev-parse --verify HEAD > /dev/null 2>&1; then
    printf '%s[ERROR]%s expected git repository at %s to have no commits.\n' \
      "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi
}

assert_no_text_match_in_dir() {
  local path="$1"
  local needle="$2"

  if grep -R -I -q -- "$needle" "$path"; then
    printf '%s[ERROR]%s did not expect to find %s anywhere under %s.\n' \
      "$RED" "$RESET" "$needle" "$path" >&2
    exit 1
  fi
}

assert_template_only_files_removed() {
  local project_root="$1"

  assert_path_missing "$project_root/.github/workflows/template-CI.yml"
  assert_path_missing "$project_root/.github/workflows/test-concat-gitignores.yml"
  assert_path_missing "$project_root/.github/workflows/test-update-unreleased.yml"
  assert_path_missing "$project_root/scripts/tests/test-concat-gitignores.sh"
  assert_path_missing "$project_root/scripts/tests/test-update-unreleased.sh"
}

assert_templates_preserved() {
  local project_root="$1"
  local cliff_path="$project_root/cliff.toml"

  if [[ ! -f $cliff_path ]]; then
    printf '%s[ERROR]%s missing %s.\n' "$RED" "$RESET" "$cliff_path" >&2
    exit 1
  fi

  if ! grep -q "templates" "$cliff_path"; then
    printf '%s[ERROR]%s expected %s to retain the word "templates" (do not replace plural tokens).\n' "$RED" "$RESET" "$cliff_path" >&2
    exit 1
  fi
}

verify_new_directory_project() {
  local project_dir="$1"
  local project_name="$2"

  printf -- '-- validating generated project (new directory mode): %s\n' "$project_dir"

  if [[ ! -d $project_dir ]]; then
    printf '%s[ERROR]%s expected project directory %s was not created.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/README.md" ]]; then
    printf '%s[ERROR]%s README.md missing in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ -f "$project_dir/.README.md" ]]; then
    printf '%s[ERROR]%s .README.md should have been renamed in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -d "$project_dir/src/$project_name" ]]; then
    printf '%s[ERROR]%s src/%s directory missing in %s.\n' "$RED" "$RESET" "$project_name" "$project_dir" >&2
    exit 1
  fi

  if [[ -d "$project_dir/src/template" ]]; then
    printf '%s[ERROR]%s src/template should have been renamed in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/.github/copilot-instructions.md" ]]; then
    printf '%s[ERROR]%s missing .github/copilot-instructions.md in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ -f "$project_dir/.github/.copilot-instructions.md" ]]; then
    printf '%s[ERROR]%s found hidden .github/.copilot-instructions.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/AGENTS.md" ]]; then
    printf '%s[ERROR]%s missing AGENTS.md in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ -f "$project_dir/.AGENTS.md" ]]; then
    printf '%s[ERROR]%s found hidden .AGENTS.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/CLAUDE.md" ]]; then
    printf '%s[ERROR]%s missing CLAUDE.md in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ -f "$project_dir/.CLAUDE.md" ]]; then
    printf '%s[ERROR]%s found hidden .CLAUDE.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/.specify/memory/constitution.md" ]]; then
    printf '%s[ERROR]%s missing .specify/memory/constitution.md in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if [[ -f "$project_dir/.specify/memory/.constitution.md" ]]; then
    printf '%s[ERROR]%s found hidden .specify/memory/.constitution.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if ! grep -q "$project_name" "$project_dir/pyproject.toml"; then
    printf '%s[ERROR]%s pyproject.toml does not contain the project name %s.\n' "$RED" "$RESET" "$project_name" >&2
    exit 1
  fi

  if ! grep -q "# \[project.scripts\]" "$project_dir/pyproject.toml"; then
    printf '%s[ERROR]%s [project.scripts] section header in pyproject.toml should be commented out.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if ! grep -q "# example-script = " "$project_dir/pyproject.toml"; then
    printf '%s[ERROR]%s example-script entry in pyproject.toml should be commented out.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if [[ ! -f "$project_dir/.gitignore" ]]; then
    printf '%s[ERROR]%s .gitignore missing in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  if ! grep -q "This .gitignore is composed of the following templates" "$project_dir/.gitignore"; then
    printf '%s[ERROR]%s .gitignore appears to be missing the expected header.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if find "$project_dir" \( -path "$project_dir/.git" -o -path "$project_dir/.git/*" \) -prune -o -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  assert_git_repository_exists "$project_dir"
  assert_templates_preserved "$project_dir"
  assert_template_only_files_removed "$project_dir"
}

verify_inplace_project() {
  local project_root="$1"
  local project_name="$2"
  local sentinel="$3"

  printf -- '-- validating generated project (current directory mode): %s\n' "$project_root"

  if [[ ! -f "$project_root/README.md" ]]; then
    printf '%s[ERROR]%s README.md missing in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/.README.md" ]]; then
    printf '%s[ERROR]%s .README.md should have been renamed in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/setup.sh" ]] || [[ -f "$project_root/manifest.txt" ]]; then
    printf '%s[ERROR]%s setup scaffolding files should have been removed from %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ ! -d "$project_root/src/$project_name" ]]; then
    printf '%s[ERROR]%s src/%s directory missing in %s.\n' "$RED" "$RESET" "$project_name" "$project_root" >&2
    exit 1
  fi

  if [[ -d "$project_root/src/template" ]]; then
    printf '%s[ERROR]%s src/template should have been renamed in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ ! -f "$project_root/.github/copilot-instructions.md" ]]; then
    printf '%s[ERROR]%s missing .github/copilot-instructions.md in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/.github/.copilot-instructions.md" ]]; then
    printf '%s[ERROR]%s found hidden .github/.copilot-instructions.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ ! -f "$project_root/AGENTS.md" ]]; then
    printf '%s[ERROR]%s missing AGENTS.md in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/.AGENTS.md" ]]; then
    printf '%s[ERROR]%s found hidden .AGENTS.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ ! -f "$project_root/CLAUDE.md" ]]; then
    printf '%s[ERROR]%s missing CLAUDE.md in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/.CLAUDE.md" ]]; then
    printf '%s[ERROR]%s found hidden .CLAUDE.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ ! -f "$project_root/.specify/memory/constitution.md" ]]; then
    printf '%s[ERROR]%s missing .specify/memory/constitution.md in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if [[ -f "$project_root/.specify/memory/.constitution.md" ]]; then
    printf '%s[ERROR]%s found hidden .specify/memory/.constitution.md in %s (should have been renamed).\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if ! grep -q "$project_name" "$project_root/pyproject.toml"; then
    printf '%s[ERROR]%s pyproject.toml does not contain the project name %s.\n' "$RED" "$RESET" "$project_name" >&2
    exit 1
  fi

  if ! grep -q "# \[project.scripts\]" "$project_root/pyproject.toml"; then
    printf '%s[ERROR]%s [project.scripts] section header in pyproject.toml should be commented out.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if ! grep -q "# example-script = " "$project_root/pyproject.toml"; then
    printf '%s[ERROR]%s example-script entry in pyproject.toml should be commented out.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if [[ ! -f "$project_root/.gitignore" ]]; then
    printf '%s[ERROR]%s .gitignore missing in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  if ! grep -q "This .gitignore is composed of the following templates" "$project_root/.gitignore"; then
    printf '%s[ERROR]%s .gitignore appears to be missing the expected header.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  if [[ -e $sentinel ]]; then
    printf '%s[ERROR]%s sentinel file %s should have been removed by cleanup.\n' "$RED" "$RESET" "$sentinel" >&2
    exit 1
  fi

  if find "$project_root" \( -path "$project_root/.git" -o -path "$project_root/.git/*" \) -prune -o -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  assert_git_repository_exists "$project_root"
  assert_templates_preserved "$project_root"
  assert_template_only_files_removed "$project_root"
}

verify_inplace_project_keeps_git() {
  local project_root="$1"
  local project_name="$2"
  local sentinel="$3"
  local expected_remote="$4"
  local backup_file="$5"

  verify_inplace_project "$project_root" "$project_name" "$sentinel"
  assert_git_remote_url_equals "$project_root" "$expected_remote"
  assert_no_text_match_in_dir "$project_root/.git" "$project_name"
  if [[ ! -f "$backup_file" ]]; then
    printf '%s[ERROR]%s expected preserved git backup file at %s.\n' \
      "$RED" "$RESET" "$backup_file" >&2
    exit 1
  fi
}

verify_inplace_project_recreates_git() {
  local project_root="$1"
  local project_name="$2"
  local sentinel="$3"

  verify_inplace_project "$project_root" "$project_name" "$sentinel"
  assert_git_has_no_commits "$project_root"
  assert_git_remote_url_absent "$project_root"
}

verify_inplace_project_keeps_git_worktree() {
  local project_root="$1"
  local project_name="$2"
  local sentinel="$3"
  local expected_remote="$4"

  verify_inplace_project "$project_root" "$project_name" "$sentinel"
  assert_git_remote_url_equals "$project_root" "$expected_remote"
  if [[ ! -f "$project_root/.git" ]]; then
    printf '%s[ERROR]%s expected worktree git metadata file at %s/.git.\n' \
      "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi
}

PROJECT_NAME_NEW="sample$(date +%s)"
TEMPLATE_DIR_NEW="$WORK_ROOT/new-directory-template"
PROJECT_DIR_NEW="$WORK_ROOT/$PROJECT_NAME_NEW"

copy_template "$TEMPLATE_DIR_NEW"
run_setup_with_inputs "$TEMPLATE_DIR_NEW" "new directory mode" $'2\n'"$PROJECT_NAME_NEW"
verify_new_directory_project "$PROJECT_DIR_NEW" "$PROJECT_NAME_NEW"

PROJECT_NAME_INPLACE="local$(date +%s)"
TEMPLATE_DIR_INPLACE="$WORK_ROOT/in-place-template"
SENTINEL_FILE="$TEMPLATE_DIR_INPLACE/out_of_manifest.tmp"

copy_template "$TEMPLATE_DIR_INPLACE"
touch "$SENTINEL_FILE"
run_setup_with_inputs "$TEMPLATE_DIR_INPLACE" "current directory mode" $'1\n'"$PROJECT_NAME_INPLACE"$'\ny'
verify_inplace_project "$TEMPLATE_DIR_INPLACE" "$PROJECT_NAME_INPLACE" "$SENTINEL_FILE"

PROJECT_NAME_KEEP_GIT="keep$(date +%s)"
TEMPLATE_DIR_KEEP_GIT="$WORK_ROOT/in-place-keep-git-template"
SENTINEL_KEEP_GIT="$TEMPLATE_DIR_KEEP_GIT/out_of_manifest_keep.tmp"
EXPECTED_REMOTE="git@github.com:example/template.git"
GIT_BACKUP_FILE="$TEMPLATE_DIR_KEEP_GIT/.git/config.bak"

copy_template_with_git "$TEMPLATE_DIR_KEEP_GIT"
touch "$SENTINEL_KEEP_GIT"
printf 'seed backup\n' > "$GIT_BACKUP_FILE"
run_setup_with_inputs "$TEMPLATE_DIR_KEEP_GIT" "current directory mode (keep git)" $'1\n'"$PROJECT_NAME_KEEP_GIT"$'\ny\ny'
verify_inplace_project_keeps_git \
  "$TEMPLATE_DIR_KEEP_GIT" \
  "$PROJECT_NAME_KEEP_GIT" \
  "$SENTINEL_KEEP_GIT" \
  "$EXPECTED_REMOTE" \
  "$GIT_BACKUP_FILE"

PROJECT_NAME_WIPE_GIT="wipe$(date +%s)"
TEMPLATE_DIR_WIPE_GIT="$WORK_ROOT/in-place-wipe-git-template"
SENTINEL_WIPE_GIT="$TEMPLATE_DIR_WIPE_GIT/out_of_manifest_wipe.tmp"

copy_template_with_git "$TEMPLATE_DIR_WIPE_GIT"
touch "$SENTINEL_WIPE_GIT"
run_setup_with_inputs "$TEMPLATE_DIR_WIPE_GIT" "current directory mode (wipe git)" $'1\n'"$PROJECT_NAME_WIPE_GIT"$'\ny\nn'
verify_inplace_project_recreates_git \
  "$TEMPLATE_DIR_WIPE_GIT" \
  "$PROJECT_NAME_WIPE_GIT" \
  "$SENTINEL_WIPE_GIT"

PROJECT_NAME_KEEP_WORKTREE_GIT="keepwt$(date +%s)"
TEMPLATE_DIR_KEEP_WORKTREE_BASE="$WORK_ROOT/in-place-keep-worktree-base"
TEMPLATE_DIR_KEEP_WORKTREE_GIT="$WORK_ROOT/in-place-keep-worktree-template"
SENTINEL_KEEP_WORKTREE_GIT="$TEMPLATE_DIR_KEEP_WORKTREE_GIT/out_of_manifest_keep_worktree.tmp"

copy_template_with_git_worktree "$TEMPLATE_DIR_KEEP_WORKTREE_BASE" "$TEMPLATE_DIR_KEEP_WORKTREE_GIT"
touch "$SENTINEL_KEEP_WORKTREE_GIT"
run_setup_with_inputs "$TEMPLATE_DIR_KEEP_WORKTREE_GIT" "current directory mode (keep git worktree)" $'1\n'"$PROJECT_NAME_KEEP_WORKTREE_GIT"$'\ny\ny'
verify_inplace_project_keeps_git_worktree \
  "$TEMPLATE_DIR_KEEP_WORKTREE_GIT" \
  "$PROJECT_NAME_KEEP_WORKTREE_GIT" \
  "$SENTINEL_KEEP_WORKTREE_GIT" \
  "$EXPECTED_REMOTE"

PROJECT_NAME_FAILURE="broken$(date +%s)"
TEMPLATE_DIR_FAILURE="$WORK_ROOT/in-place-failure-template"

copy_template "$TEMPLATE_DIR_FAILURE"
rm -f "$TEMPLATE_DIR_FAILURE/.AGENTS.md"
run_setup_with_inputs "$TEMPLATE_DIR_FAILURE" "current directory mode (finalize failure)" $'1\n'"$PROJECT_NAME_FAILURE"$'\ny' 1

printf '%s==>%s setup.sh integration smoke test: %sPASSED%s\n' "$CYAN" "$RESET" "$GREEN" "$RESET"

if $VERBOSE; then
  printf '\n%s[INFO]%s Verbose summary\n' "$CYAN" "$RESET"
  printf '  workspace root:        %s\n' "$WORK_ROOT"
  printf '  new-dir template:      %s\n' "$TEMPLATE_DIR_NEW"
  printf '  new-dir project name:  %s\n' "$PROJECT_NAME_NEW"
  printf '  new-dir project dir:   %s\n' "$PROJECT_DIR_NEW"
  printf '  in-place template:     %s\n' "$TEMPLATE_DIR_INPLACE"
  printf '  in-place project name: %s\n' "$PROJECT_NAME_INPLACE"
fi
