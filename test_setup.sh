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
  shift 3
  local extra_args=("$@")

  pushd "$workdir" > /dev/null

  if $VERBOSE; then
    export TEST_SETUP_VERBOSE=1
  else
    export TEST_SETUP_VERBOSE=0
  fi
  export SETUP_SH_QUIET=1
  export SETUP_TEST_INPUTS="$inputs"
  export SETUP_TEST_EXTRA_ARGS="${extra_args[*]}"

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

extra_args = os.environ.get("SETUP_TEST_EXTRA_ARGS", "").split()
cmd = ["./setup.sh"] + extra_args

env = os.environ.copy()
controller_fd, client_fd = pty.openpty()
process = subprocess.Popen(
    cmd,
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

verify_common_assertions() {
  local project_root="$1"
  local project_name="$2"
  local owner="$3"

  # cliff.toml contains owner/project_name in repository URLs
  if ! grep -q "$owner/$project_name" "$project_root/cliff.toml"; then
    printf '%s[ERROR]%s cliff.toml does not contain %s/%s in repository URLs.\n' "$RED" "$RESET" "$owner" "$project_name" >&2
    exit 1
  fi

  # cliff.toml does NOT contain personal email postprocessor
  if grep -q 'michael\.chen@aicadium\.ai' "$project_root/cliff.toml"; then
    printf '%s[ERROR]%s cliff.toml still contains personal email postprocessor line.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  # .pre-commit-config.yaml still contains michen00/custom-commit-hooks
  if ! grep -q 'michen00/custom-commit-hooks' "$project_root/.pre-commit-config.yaml"; then
    printf '%s[ERROR]%s .pre-commit-config.yaml does not contain michen00/custom-commit-hooks (should be preserved).\n' "$RED" "$RESET" >&2
    exit 1
  fi

  # pyproject.toml contains correct authors with no email
  if ! grep -q "authors = \[{ name = \"$owner\" }\]" "$project_root/pyproject.toml"; then
    printf '%s[ERROR]%s pyproject.toml does not contain authors = [{ name = "%s" }].\n' "$RED" "$RESET" "$owner" >&2
    exit 1
  fi

  # CODE_OF_CONDUCT.md contains placeholder email
  if ! grep -q '\[INSERT CONTACT EMAIL\]' "$project_root/CODE_OF_CONDUCT.md"; then
    printf '%s[ERROR]%s CODE_OF_CONDUCT.md does not contain [INSERT CONTACT EMAIL] placeholder.\n' "$RED" "$RESET" >&2
    exit 1
  fi
}

verify_private_assertions() {
  local project_root="$1"

  # greet-new-contributors.yml must NOT exist
  if [[ -f "$project_root/.github/workflows/greet-new-contributors.yml" ]]; then
    printf '%s[ERROR]%s greet-new-contributors.yml should not exist in private profile.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  # README.md must NOT contain DeepWiki badge
  if grep -q 'Ask DeepWiki' "$project_root/README.md"; then
    printf '%s[ERROR]%s README.md should not contain DeepWiki badge in private profile.\n' "$RED" "$RESET" >&2
    exit 1
  fi
}

verify_public_assertions() {
  local project_root="$1"
  local project_name="$2"
  local owner="$3"

  # greet-new-contributors.yml must exist
  if [[ ! -f "$project_root/.github/workflows/greet-new-contributors.yml" ]]; then
    printf '%s[ERROR]%s greet-new-contributors.yml should exist in public profile.\n' "$RED" "$RESET" >&2
    exit 1
  fi

  # README.md must contain DeepWiki badge with correct owner/project
  if ! grep -q "$owner/$project_name" "$project_root/README.md"; then
    printf '%s[ERROR]%s README.md does not contain DeepWiki badge with %s/%s.\n' "$RED" "$RESET" "$owner" "$project_name" >&2
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

  if find "$project_dir" -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_dir" >&2
    exit 1
  fi

  assert_templates_preserved "$project_dir"
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

  if find "$project_root" -name '*.bak' -print -quit | grep -q .; then
    printf '%s[ERROR]%s found leftover .bak files in %s.\n' "$RED" "$RESET" "$project_root" >&2
    exit 1
  fi

  assert_templates_preserved "$project_root"
}

OWNER="testowner"
PASS_COUNT=0
FAIL_COUNT=0

run_scenario() {
  local scenario_num="$1"
  local description="$2"
  shift 2

  printf '\n%s--- Scenario %s: %s ---%s\n' "$CYAN" "$scenario_num" "$description" "$RESET"
  if "$@"; then
    printf '%s[PASS]%s Scenario %s: %s\n' "$GREEN" "$RESET" "$scenario_num" "$description"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '%s[FAIL]%s Scenario %s: %s\n' "$RED" "$RESET" "$scenario_num" "$description"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- Scenario 1: new-dir, public, via flags ---
scenario_1() {
  local project_name
  project_name="pub-new-$(date +%s)"
  local template_dir="$WORK_ROOT/s1-template"
  local project_dir="$WORK_ROOT/$project_name"

  copy_template "$template_dir"
  run_setup_with_inputs "$template_dir" "S1: new-dir public flags" \
    $'2\n'"$project_name" \
    "--profile=public" "--owner=$OWNER"
  verify_new_directory_project "$project_dir" "$project_name"
  verify_common_assertions "$project_dir" "$project_name" "$OWNER"
  verify_public_assertions "$project_dir" "$project_name" "$OWNER"
}

# --- Scenario 2: new-dir, private, via flags ---
scenario_2() {
  local project_name
  project_name="prv-new-$(date +%s)"
  local template_dir="$WORK_ROOT/s2-template"
  local project_dir="$WORK_ROOT/$project_name"

  copy_template "$template_dir"
  run_setup_with_inputs "$template_dir" "S2: new-dir private flags" \
    $'2\n'"$project_name" \
    "--profile=private" "--owner=$OWNER"
  verify_new_directory_project "$project_dir" "$project_name"
  verify_common_assertions "$project_dir" "$project_name" "$OWNER"
  verify_private_assertions "$project_dir"
}

# --- Scenario 3: in-place, public, via interactive prompts ---
scenario_3() {
  local project_name
  project_name="pub-inp-$(date +%s)"
  local template_dir="$WORK_ROOT/s3-template"
  local sentinel="$template_dir/out_of_manifest.tmp"

  copy_template "$template_dir"
  touch "$sentinel"
  # Inputs: location=1, name, owner, profile=1 (public), confirm=y
  run_setup_with_inputs "$template_dir" "S3: in-place public interactive" \
    $'1\n'"$project_name"$'\n'"$OWNER"$'\n1\ny'
  verify_inplace_project "$template_dir" "$project_name" "$sentinel"
  verify_common_assertions "$template_dir" "$project_name" "$OWNER"
  verify_public_assertions "$template_dir" "$project_name" "$OWNER"
}

# --- Scenario 4: in-place, private, via interactive prompts ---
scenario_4() {
  local project_name
  project_name="prv-inp-$(date +%s)"
  local template_dir="$WORK_ROOT/s4-template"
  local sentinel="$template_dir/out_of_manifest.tmp"

  copy_template "$template_dir"
  touch "$sentinel"
  # Inputs: location=1, name, owner, profile=2 (private), confirm=y
  run_setup_with_inputs "$template_dir" "S4: in-place private interactive" \
    $'1\n'"$project_name"$'\n'"$OWNER"$'\n2\ny'
  verify_inplace_project "$template_dir" "$project_name" "$sentinel"
  verify_common_assertions "$template_dir" "$project_name" "$OWNER"
  verify_private_assertions "$template_dir"
}

# --- Scenario 5: new-dir, private, partial flag (--owner only) ---
scenario_5() {
  local project_name
  project_name="mix-new-$(date +%s)"
  local template_dir="$WORK_ROOT/s5-template"
  local project_dir="$WORK_ROOT/$project_name"

  copy_template "$template_dir"
  # Inputs: location=2, name, profile=2 (private) — owner from flag
  run_setup_with_inputs "$template_dir" "S5: new-dir private partial-flag" \
    $'2\n'"$project_name"$'\n2' \
    "--owner=$OWNER"
  verify_new_directory_project "$project_dir" "$project_name"
  verify_common_assertions "$project_dir" "$project_name" "$OWNER"
  verify_private_assertions "$project_dir"
}

# --- Scenario 6: --help prints usage and exits 0 ---
scenario_6() {
  local template_dir="$WORK_ROOT/s6-template"
  copy_template "$template_dir"
  pushd "$template_dir" > /dev/null

  local output
  output=$(./setup.sh --help 2>&1)
  local rc=$?

  popd > /dev/null

  if [[ $rc -ne 0 ]]; then
    printf '%s[ERROR]%s --help exited with code %s (expected 0).\n' "$RED" "$RESET" "$rc" >&2
    return 1
  fi

  if [[ $output != *"Usage:"* ]]; then
    printf '%s[ERROR]%s --help output does not contain "Usage:".\n' "$RED" "$RESET" >&2
    return 1
  fi
}

run_scenario 1 "new-dir, public, flags" scenario_1
run_scenario 2 "new-dir, private, flags" scenario_2
run_scenario 3 "in-place, public, interactive" scenario_3
run_scenario 4 "in-place, private, interactive" scenario_4
run_scenario 5 "new-dir, private, partial-flag" scenario_5
run_scenario 6 "--help prints usage" scenario_6

printf '\n%s==>%s setup.sh integration smoke test: ' "$CYAN" "$RESET"
if [[ $FAIL_COUNT -eq 0 ]]; then
  printf '%sPASSED%s (%s/%s scenarios)\n' "$GREEN" "$RESET" "$PASS_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
else
  printf '%sFAILED%s (%s/%s scenarios passed)\n' "$RED" "$RESET" "$PASS_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  exit 1
fi

if $VERBOSE; then
  printf '\n%s[INFO]%s Verbose summary\n' "$CYAN" "$RESET"
  printf '  workspace root: %s\n' "$WORK_ROOT"
  printf '  scenarios run:  %s\n' "$((PASS_COUNT + FAIL_COUNT))"
  printf '  passed:         %s\n' "$PASS_COUNT"
  printf '  failed:         %s\n' "$FAIL_COUNT"
fi
