#!/usr/bin/env bash

# Lightweight integration test for setup.sh.

set -euo pipefail

if ! command -v rsync > /dev/null 2>&1; then
  echo "rsync is required to run this test." >&2
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

rsync -a --exclude ".git" "$REPO_ROOT"/ "$TEMPLATE_DIR"/

pushd "$TEMPLATE_DIR" > /dev/null

PROJECT_NAME="sample$(date +%s)"

PYTHON_BIN="$(command -v python3 || command -v python)"
if [[ -z $PYTHON_BIN ]]; then
  echo "Python is required to run this test." >&2
  exit 1
fi

export PROJECT_NAME

"$PYTHON_BIN" << 'PY'
import os
import pty
import subprocess
import sys
import time

project_name = os.environ["PROJECT_NAME"]

master_fd, slave_fd = pty.openpty()
process = subprocess.Popen(
    ["./setup.sh"],
    stdin=slave_fd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
os.close(slave_fd)

for line in ("2", project_name):
    os.write(master_fd, (line + "\n").encode())
    time.sleep(0.2)

os.close(master_fd)
stdout, stderr = process.communicate()

sys.stdout.write(stdout)
sys.stderr.write(stderr)

if "Warning:" in stderr:
  sys.exit(1)

if process.returncode != 0:
    sys.exit(process.returncode)
PY

PROJECT_DIR="$WORK_ROOT/$PROJECT_NAME"

if [[ ! -d $PROJECT_DIR ]]; then
  echo "Expected project directory $PROJECT_DIR was not created." >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/README.md" ]]; then
  echo "README.md was not created in $PROJECT_DIR." >&2
  exit 1
fi

if [[ -f "$PROJECT_DIR/README_template.md" ]]; then
  echo "README_template.md should have been renamed in $PROJECT_DIR." >&2
  exit 1
fi

if [[ ! -d "$PROJECT_DIR/src/$PROJECT_NAME" ]]; then
  echo "src/$PROJECT_NAME directory is missing in $PROJECT_DIR." >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/.github/.copilot-instructions.md" ]]; then
  echo "Missing .github/.copilot-instructions.md in generated project." >&2
  exit 1
fi

if ! grep -q "$PROJECT_NAME" "$PROJECT_DIR/pyproject.toml"; then
  echo "pyproject.toml does not contain the project name $PROJECT_NAME." >&2
  exit 1
fi

popd > /dev/null

echo "setup.sh integration test passed."
