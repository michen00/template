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

# Define transformations: hook_id|new_args
declare -a TRANSFORMATIONS=(
  "ruff-check|[--fix, --unsafe-fixes, --show-fixes, --output-format=github, --exit-non-zero-on-fix, --verbose]"
  "ruff-format|[--check, --diff, --verbose]"
)

echo "Modifying ruff args in $CONFIG_FILE for CI..."

# Create a backup and ensure cleanup on exit
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
trap 'rm -f "${CONFIG_FILE}.bak"' EXIT

# Apply each transformation with context-aware matching
for transform in "${TRANSFORMATIONS[@]}"; do
  IFS='|' read -r hook_id new_args <<< "$transform"

  # Capture the old args before replacement
  old_args=$(perl -ne "
    BEGIN { \$in_hook = 0; }
    if (/id: $hook_id/) {
      \$in_hook = 1;
    }
    if (\$in_hook && /^\s+args: (\[.*\])\s*\$/) {
      print \$1;
      last;
    }
    if (/^  - repo:/ || (/id:/ && !/id: $hook_id/)) {
      \$in_hook = 0;
    }
  " "$CONFIG_FILE")

  perl -i -pe "
    BEGIN { \$in_hook = 0; }
    if (/id: $hook_id/) {
      \$in_hook = 1;
    }
    if (\$in_hook && /^\s+args: \[.*\]\s*\$/) {
      s/args: \[.*\]/args: $new_args/;
      \$in_hook = 0;
    }
    if (/^  - repo:/ || (/id:/ && !/id: $hook_id/)) {
      \$in_hook = 0;
    }
  " "$CONFIG_FILE"

  echo "  $hook_id: $old_args → $new_args"
done

echo "✓ Ruff args updated for CI"
