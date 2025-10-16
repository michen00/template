#!/usr/bin/env bash

set -euo pipefail

read -r -d '' USAGE << 'EOF' || true
setup.sh integration smoke test

Description:
  Duplicate the template repo into a temporary workspace, run `setup.sh` in
  "new directory" mode, and assert the generated project structure and token
  replacement are correct.

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

TEMPLATE_DIR="$WORK_ROOT/template"
mkdir -p "$TEMPLATE_DIR"

printf -- '-- copying template -> %s\n' "$TEMPLATE_DIR"
rsync -a --exclude ".git" "$REPO_ROOT"/ "$TEMPLATE_DIR"/

pushd "$TEMPLATE_DIR" > /dev/null

PROJECT_NAME="sample$(date +%s)"
export PROJECT_NAME

if $VERBOSE; then
  export TEST_SETUP_VERBOSE=1
else
  export TEST_SETUP_VERBOSE=0
fi
export SETUP_SH_QUIET=1

printf -- '-- running setup.sh (new directory mode)\n'
"$PYTHON_BIN" << 'PY'
import os
import pty
import subprocess
import sys
import time

project_name = os.environ["PROJECT_NAME"]
verbose = os.environ.get("TEST_SETUP_VERBOSE") == "1"
os.environ["SETUP_SH_QUIET"] = os.environ.get("SETUP_SH_QUIET", "1")

controller_fd, client_fd = pty.openpty()
env = os.environ.copy()
process = subprocess.Popen(
  ["./setup.sh"],
  stdin=client_fd,
  stdout=subprocess.PIPE,
  stderr=subprocess.PIPE,
  text=True,
  env=env,
)
os.close(client_fd)

for line in ("2", project_name):
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

PROJECT_DIR="$WORK_ROOT/$PROJECT_NAME"

printf -- '-- validating generated project: %s\n' "$PROJECT_DIR"

if [[ ! -d $PROJECT_DIR ]]; then
  printf '%s[ERROR]%s expected project directory %s was not created.\n' "$RED" "$RESET" "$PROJECT_DIR" >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/README.md" ]]; then
  printf '%s[ERROR]%s README.md missing in %s.\n' "$RED" "$RESET" "$PROJECT_DIR" >&2
  exit 1
fi

if [[ -f "$PROJECT_DIR/README_template.md" ]]; then
  printf '%s[ERROR]%s README_template.md should have been renamed in %s.\n' "$RED" "$RESET" "$PROJECT_DIR" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_DIR/src/$PROJECT_NAME" ]]; then
  printf '%s[ERROR]%s src/%s directory missing in %s.\n' "$RED" "$RESET" "$PROJECT_NAME" "$PROJECT_DIR" >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/.github/copilot-instructions.md" ]]; then
  printf '%s[ERROR]%s missing .github/copilot-instructions.md in %s.\n' "$RED" "$RESET" "$PROJECT_DIR" >&2
  exit 1
fi

if [[ -f "$PROJECT_DIR/.github/.copilot-instructions.md" ]]; then
  printf '%s[ERROR]%s found hidden .github/.copilot-instructions.md in %s (should have been renamed).\n' "$RED" "$RESET" "$PROJECT_DIR" >&2
  exit 1
fi

if ! grep -q "$PROJECT_NAME" "$PROJECT_DIR/pyproject.toml"; then
  printf '%s[ERROR]%s pyproject.toml does not contain the project name %s.\n' "$RED" "$RESET" "$PROJECT_NAME" >&2
  exit 1
fi

popd > /dev/null

printf '%s==>%s setup.sh integration smoke test: %sPASSED%s\n' "$CYAN" "$RESET" "$GREEN" "$RESET"

if $VERBOSE; then
  printf '\n%s[INFO]%s Verbose summary\n' "$CYAN" "$RESET"
  printf '  workspace root: %s\n' "$WORK_ROOT"
  printf '  template copy:  %s\n' "$TEMPLATE_DIR"
  printf '  project name:   %s\n' "$PROJECT_NAME"
  printf '  project dir:    %s\n' "$PROJECT_DIR"
fi
