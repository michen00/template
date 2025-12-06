#!/usr/bin/env bash

# Purpose: Replace ruff-check and ruff-format args in .pre-commit-config.yaml
#          with CI-optimized versions for stricter checking and better GitHub output formatting.
#

# TODO: be less hacky; dynamically modifying at CI time is unsatisfying

set -euo pipefail

CONFIG_FILE=".pre-commit-config.yaml"

if [[ ! -f $CONFIG_FILE ]]; then
  echo "Error: $CONFIG_FILE not found in current directory" >&2
  exit 1
fi

# Define transformations: hook_id|arg1|arg2|arg3|...
declare -a TRANSFORMATIONS=(
  "ruff-check|--fix|--unsafe-fixes|--show-fixes|--output-format=github|--exit-non-zero-on-fix|--verbose"
  "ruff-format|--check|--diff|--verbose"
)

echo "Modifying ruff args in $CONFIG_FILE for CI..."

# Create a backup and ensure cleanup on exit
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
trap 'rm -f "${CONFIG_FILE}.bak"' EXIT

# Apply each transformation with context-aware matching
for transform in "${TRANSFORMATIONS[@]}"; do
  IFS='|' read -ra parts <<< "$transform"
  hook_id="${parts[0]}"

  # Build multiline YAML array format from pipe-delimited args
  # Indentation: 8 spaces for args: [, 10 spaces for items, 8 spaces for closing ]
  multiline_args="        args:\n          ["
  for ((i = 1; i < ${#parts[@]}; i++)); do
    multiline_args+=$(printf "\n            %s," "${parts[i]}")
  done
  multiline_args+=$(printf "\n          ]")

  # Build single-line format for echo message
  new_args_single_line="["
  for ((i = 1; i < ${#parts[@]}; i++)); do
    if [[ $i -gt 1 ]]; then
      new_args_single_line+=", "
    fi
    new_args_single_line+="${parts[i]}"
  done
  new_args_single_line+="]"

  # Capture the old args before replacement
  old_args=$(perl -ne "
    BEGIN { \$in_hook = 0; }
    if (/id:\s+$hook_id\s*\$/) {
      \$in_hook = 1;
    }
    if (\$in_hook && /^\s+args: (\[.*\])\s*\$/) {
      print \$1;
      last;
    }
    if (/^  - repo:/ || (/id:\s+\S+\s*\$/ && !/id:\s+$hook_id\s*\$/)) {
      \$in_hook = 0;
    }
  " "$CONFIG_FILE")

  # Replace args with multiline format
  # The multiline string already has correct absolute indentation
  perl -i -0pe "
    BEGIN { \$in_hook = 0; \$multiline = qq($multiline_args); }
    if (/id:\s+$hook_id\s*\$/m) {
      \$in_hook = 1;
    }
    if (\$in_hook && /^(\s+)args: \[.*?\]\s*\$/m) {
      s/^(\s+)args: \[.*?\]\s*\$/\$multiline/m;
      \$in_hook = 0;
    }
    if (/^  - repo:/m || (/id:\s+\S+\s*\$/m && !/id:\s+$hook_id\s*\$/m)) {
      \$in_hook = 0;
    }
  " "$CONFIG_FILE"

  echo "  $hook_id: $old_args → $new_args_single_line"
done

# Remove stages: ["pre-push"] from mypy hook to run it in CI
echo "Removing mypy pre-push stage restriction..."
perl -i -pe '
  BEGIN { $in_mypy = 0; }
  if (/id:\s+mypy\s*$/) {
    $in_mypy = 1;
  }
  if ($in_mypy && /^\s+stages:\s*\[.*\]\s*$/) {
    $_ = "";
    $in_mypy = 0;
  }
  if (/^  - repo:/ || (/id:\s+\S+\s*$/ && !/id:\s+mypy\s*$/)) {
    $in_mypy = 0;
  }
' "$CONFIG_FILE"

echo "✓ Pre-commit config updated for CI"
