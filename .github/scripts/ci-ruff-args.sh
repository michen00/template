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

  # Build single-line format
  single_line_args="        args: ["
  for ((i = 1; i < ${#parts[@]}; i++)); do
    if [[ $i -gt 1 ]]; then
      single_line_args+=", "
    fi
    single_line_args+="${parts[i]}"
  done
  single_line_args+="]"

  # Build multiline YAML array format (for hooks with many args)
  # Indentation: 8 spaces for 'args:', 10 spaces for '[', 12 spaces for items, 10 spaces for ']'
  # Use literal \n escapes throughout so perl's qq() can properly interpolate them
  multiline_args="        args:\n          ["
  for ((i = 1; i < ${#parts[@]}; i++)); do
    multiline_args+="\n            ${parts[i]},"
  done
  multiline_args+="\n          ]"

  # Choose format based on arg count: single-line for <=3 args, multiline otherwise
  arg_count=$((${#parts[@]} - 1))
  if [[ $arg_count -le 3 ]]; then
    replacement_args="$single_line_args"
  else
    replacement_args="$multiline_args"
  fi

  # For echo message
  new_args_single_line="[${single_line_args#*: \[}"

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

  # Replace or insert args using line-by-line processing (NOT slurp mode)
  # This ensures we only modify args within the correct hook context
  perl -i -pe "
    BEGIN { \$in_hook = 0; \$done = 0; \$new_args = qq($replacement_args); }
    # Enter hook context when we find the target hook id
    if (/^\\s+-\\s+id:\\s+$hook_id\\s*\$/) {
      \$in_hook = 1;
      \$done = 0;
    }
    # Replace existing args line if in correct hook context
    elsif (\$in_hook && !\$done && /^\\s+args:\\s*\\[.*\\]\\s*\$/) {
      \$_ = \"\$new_args\\n\";
      \$done = 1;
    }
    # Exit hook context and insert args if we hit next hook/repo without finding args
    elsif (\$in_hook && !\$done && (/^\\s+-\\s+id:/ || /^\\s+-\\s+repo:/)) {
      \$_ = \"\$new_args\\n\" . \$_;
      \$done = 1;
      \$in_hook = 0;
    }
    # Exit hook context when entering a new repo
    elsif (/^\\s+-\\s+repo:/) {
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
