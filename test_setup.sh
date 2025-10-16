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

run_setup_with_inputs() {
  local workdir="$1"
  local description="$2"
  local inputs="$3"

  pushd "$workdir" > /dev/null

  if $VERBOSE; then
    export TEST_SETUP_VERBOSE=1
  else
    export TEST_SETUP_VERBOSE=0
  fi
  export SETUP_SH_QUIET=1
  export SETUP_TEST_INPUTS="$inputs"

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

should_display = verbose or process.returncode != 0 or "Warning:" in stderr

if should_display:
    if stdout:
        sys.stdout.write(stdout)
    if stderr:
        sys.stderr.write(stderr)

if "Warning:" in stderr:
    sys.exit(1)

if process.returncode != 0:
    sys.exit(process.returncode)
PY

  popd > /dev/null
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

  if [[ -f "$project_dir/README_template.md" ]]; then
    printf '%s[ERROR]%s README_template.md should have been renamed in %s.\n' "$RED" "$RESET" "$project_dir" >&2
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

  if ! grep -q "$project_name" "$project_dir/pyproject.toml"; then
    printf '%s[ERROR]%s pyproject.toml does not contain the project name %s.\n' "$RED" "$RESET" "$project_name" >&2
    exit 1
  fi

  if find "$project_dir" -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi
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

  if [[ -f "$project_root/README_template.md" ]]; then
    printf '%s[ERROR]%s README_template.md should have been renamed in %s.\n' "$RED" "$RESET" "$project_root" >&2
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

  if ! grep -q "$project_name" "$project_root/pyproject.toml"; then
    printf '%s[ERROR]%s pyproject.toml does not contain the project name %s.\n' "$RED" "$RESET" "$project_name" >&2
    exit 1
  fi

  if [[ -e $sentinel ]]; then
    printf '%s[ERROR]%s sentinel file %s should have been removed by cleanup.\n' "$RED" "$RESET" "$sentinel" >&2
    exit 1
  fi

  if find "$project_root" -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_root" >&2
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
