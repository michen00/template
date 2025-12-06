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

# Define transformations: hook_id|space-separated args
# Will be converted to multi-line YAML array format to respect 88 character limit
declare -a TRANSFORMATIONS=(
  "ruff-check|--fix --unsafe-fixes --show-fixes --output-format=github --exit-non-zero-on-fix --verbose"
  "ruff-format|--check --diff --verbose"
)

echo "Modifying ruff args in $CONFIG_FILE for CI..."

# Create a backup and ensure cleanup on exit
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
trap 'rm -f "${CONFIG_FILE}.bak"' EXIT

# Apply each transformation with context-aware matching
for transform in "${TRANSFORMATIONS[@]}"; do
  IFS='|' read -r hook_id args_string <<< "$transform"

  # Capture the old args before replacement (for logging)
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

  # Replace inline args array with multi-line format using perl
  perl -i -pe "
    BEGIN {
      \$in_hook = 0;
      \$hook_id_pattern = q($hook_id);
      @args = qw($args_string);
    }
    if (/id:\s+\$hook_id_pattern\s*\$/) {
      \$in_hook = 1;
      print;
      next;
    }
    if (\$in_hook && /^\s+args:\s*\[.*\]\s*\$/) {
      # Replace with multi-line format
      print \"        args:\n\";
      for my \$arg (@args) {
        print \"          - \$arg\n\";
      }
      \$in_hook = 0;
      next;
    }
    if (/^  - repo:/ || (/id:\s+\S+\s*\$/ && !/id:\s+\$hook_id_pattern\s*\$/)) {
      \$in_hook = 0;
    }
    print;
  " "$CONFIG_FILE"

  echo "  $hook_id: $old_args → multi-line format"
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

# Format the modified file with yamlfmt to ensure it passes yamllint
# This prevents yamlfmt from modifying it during pre-commit and causing yamllint failures
echo "Formatting $CONFIG_FILE with yamlfmt..."
# Try multiple methods to run yamlfmt (it may not be available yet in CI)
if command -v yamlfmt &> /dev/null; then
  yamlfmt "$CONFIG_FILE" 2> /dev/null || echo "Note: yamlfmt formatting attempted" >&2
elif uv run --no-project yamlfmt "$CONFIG_FILE" 2> /dev/null; then
  : # yamlfmt ran successfully via uv
else
  # yamlfmt not available yet - it will format during pre-commit run
  # The file should still be valid YAML, just may need formatting
  echo "Note: yamlfmt not available yet, will be formatted during pre-commit run" >&2
fi

echo "✓ Pre-commit config updated for CI"
