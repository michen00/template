#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUT="$REPO_ROOT/scripts/concat-gitignores.sh"

TEST_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [-h | --help]

Run tests for concat-gitignores.sh.

Options:
  -h, --help  Show this help message and exit.
EOF
  exit "${1:-0}"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -f "$path" ]] || fail "Expected file to exist: $path"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  grep -Fq -- "$needle" "$path" || fail "Expected '$needle' in $path"
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$path"; then
    fail "Did not expect '$needle' in $path"
  fi
}

assert_line_order() {
  local path="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line="$(grep -nF -- "$first" "$path" | awk -F: 'NR==1 {print $1}')"
  second_line="$(grep -nF -- "$second" "$path" | awk -F: 'NR==1 {print $1}')"
  [[ -n "$first_line" ]] || fail "Could not find first marker: $first"
  [[ -n "$second_line" ]] || fail "Could not find second marker: $second"
  [[ "$first_line" -lt "$second_line" ]] || fail "Expected '$first' before '$second'"
}

new_fixture() {
  local filename="$1"
  local content="$2"
  local path="$TEST_ROOT/$filename"
  printf '%s\n' "$content" > "$path"
  printf '%s\n' "$path"
}

to_file_url() {
  local path="$1"
  printf 'file://%s\n' "$path"
}

test_help_exits_zero() {
  "$SUT" --help > /dev/null
}

test_help_prints_usage() {
  local out
  out="$("$SUT" --help 2>&1)"
  [[ "$out" == *"Usage:"* ]] || fail "Expected help output to include 'Usage:'"
}

test_unknown_option_fails() {
  local out
  if out="$("$SUT" --invalid 2>&1)"; then
    fail "Expected unknown option to fail"
  fi
  [[ "$out" == *"Unknown option"* ]] || fail "Expected unknown option error message"
}

test_output_missing_arg_fails() {
  local out
  if out="$("$SUT" --output 2>&1)"; then
    fail "Expected --output with missing argument to fail"
  fi
  [[ "$out" == *"--output requires a file name"* ]] || fail "Expected missing output argument message"
}

test_fetches_from_file_url() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-one.gitignore" $'# fixture one\n*.tmp\ncache/')"
  url_file="$TEST_ROOT/urls.txt"
  output_file="$TEST_ROOT/out-fetch.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_exists "$output_file"
}

test_output_contains_header() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-header.gitignore" $'# fixture header\n*.header')"
  url_file="$TEST_ROOT/urls-header.txt"
  output_file="$TEST_ROOT/out-header.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "This .gitignore is composed of the following templates"
}

test_output_contains_fetched_content() {
  local fixture url_file output_file marker
  marker="unique-fixture-marker"
  fixture="$(new_fixture "fixture-content.gitignore" $'# fixture content\n'"$marker")"
  url_file="$TEST_ROOT/urls-content.txt"
  output_file="$TEST_ROOT/out-content.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "$marker"
}

test_output_contains_speckit_block() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-speckit.gitignore" $'# fixture speckit\n*.speckit')"
  url_file="$TEST_ROOT/urls-speckit.txt"
  output_file="$TEST_ROOT/out-speckit.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "# Speckit"
  assert_file_contains "$output_file" ".specify/"
}

test_multiple_urls_in_file() {
  local fixture_one fixture_two url_file output_file
  fixture_one="$(new_fixture "fixture-multi-one.gitignore" $'# fixture multi one\nmarker-multi-one')"
  fixture_two="$(new_fixture "fixture-multi-two.gitignore" $'# fixture multi two\nmarker-multi-two')"
  url_file="$TEST_ROOT/urls-multi.txt"
  output_file="$TEST_ROOT/out-multi.gitignore"

  {
    to_file_url "$fixture_one"
    to_file_url "$fixture_two"
  } > "$url_file"

  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "marker-multi-one"
  assert_file_contains "$output_file" "marker-multi-two"
}

test_ignores_single_hash_comments_in_input() {
  local fixture url_file output_file comment_marker
  comment_marker="this-comment-should-be-ignored"
  fixture="$(new_fixture "fixture-comment.gitignore" $'# fixture comment\nmarker-comment')"
  url_file="$TEST_ROOT/urls-comment.txt"
  output_file="$TEST_ROOT/out-comment.gitignore"

  {
    printf '# %s\n' "$comment_marker"
    to_file_url "$fixture"
  } > "$url_file"

  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "marker-comment"
  assert_file_not_contains "$output_file" "# - # $comment_marker"
}

test_preserves_section_labels_and_input_order() {
  local fixture_one fixture_two url_file output_file
  fixture_one="$(new_fixture "fixture-order-one.gitignore" $'# fixture order one\nmarker-order-one')"
  fixture_two="$(new_fixture "fixture-order-two.gitignore" $'# fixture order two\nmarker-order-two')"
  url_file="$TEST_ROOT/urls-order.txt"
  output_file="$TEST_ROOT/out-order.gitignore"

  {
    printf '## Tools / documents / misc artifacts\n'
    to_file_url "$fixture_two"
    printf '## Language / runtime / ecosystem\n'
    to_file_url "$fixture_one"
  } > "$url_file"

  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "# Tools / documents / misc artifacts"
  assert_file_contains "$output_file" "# Language / runtime / ecosystem"
  assert_line_order "$output_file" "# Tools / documents / misc artifacts" "# Language / runtime / ecosystem"
  assert_line_order "$output_file" "# - file://$fixture_two" "# - file://$fixture_one"
}

for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage 0
      ;;
  esac
done

tests=(
  test_help_exits_zero
  test_help_prints_usage
  test_unknown_option_fails
  test_output_missing_arg_fails
  test_fetches_from_file_url
  test_output_contains_header
  test_output_contains_fetched_content
  test_output_contains_speckit_block
  test_multiple_urls_in_file
  test_ignores_single_hash_comments_in_input
  test_preserves_section_labels_and_input_order
)

pass_count=0
fail_count=0

for test_name in "${tests[@]}"; do
  if ("$test_name"); then
    printf '[PASS] %s\n' "$test_name"
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
done

printf '\nResult: %d passed, %d failed\n' "$pass_count" "$fail_count"
[[ "$fail_count" -eq 0 ]]
