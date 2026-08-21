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

assert_single_trailing_newline() {
  local path="$1"
  local last_two
  [[ "$(tail -c 1 "$path")" == "" ]] || fail "Expected file to end with a newline: $path"
  last_two="$(tail -c 2 "$path" | od -An -tx1 | tr -d ' \n')"
  [[ "$last_two" != "0a0a" ]] || fail "Expected exactly one trailing newline: $path"
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

test_custom_missing_arg_fails() {
  local out
  if out="$("$SUT" --custom 2>&1)"; then
    fail "Expected --custom with missing argument to fail"
  fi
  [[ "$out" == *"--custom requires a file name"* ]] || fail "Expected missing custom argument message"
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

# The built-in tail carries only the patterns that suit any repository: the
# user-local settings file, and the re-includes that repair what this script's
# own default template list over-ignores. Tool choices live in the custom file.
test_output_contains_builtin_tail() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-tail.gitignore" $'# fixture tail\n*.tail')"
  url_file="$TEST_ROOT/urls-tail.txt"
  output_file="$TEST_ROOT/out-tail.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" --custom "$TEST_ROOT/absent.gitignore" > /dev/null

  assert_file_contains "$output_file" ".claude/settings.local.json"
  assert_file_contains "$output_file" "!scripts/lib/"
  assert_file_contains "$output_file" "!src/*/bin"
  assert_file_not_contains "$output_file" "# spec-kit scaffolding"
}

test_custom_file_is_appended() {
  local fixture url_file output_file custom_file
  fixture="$(new_fixture "fixture-custom.gitignore" $'# fixture custom\nmarker-custom-fetched')"
  url_file="$TEST_ROOT/urls-custom.txt"
  output_file="$TEST_ROOT/out-custom.gitignore"
  custom_file="$(new_fixture "custom-patterns.gitignore" $'# repo tooling\nmarker-custom-pattern/')"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" --custom "$custom_file" > /dev/null

  assert_file_contains "$output_file" "marker-custom-pattern/"
  assert_file_contains "$output_file" "# Plus local patterns from $custom_file"
  # Last match wins in gitignore, so the custom block has to follow the built-in
  # tail rather than precede it.
  assert_line_order "$output_file" "!scripts/lib/" "marker-custom-pattern/"
  assert_single_trailing_newline "$output_file"
}

# The whole point of the split: a copy of this script dropped into a repository
# that has no customization at all still has to work.
test_missing_custom_file_is_skipped() {
  local fixture url_file output_file out
  fixture="$(new_fixture "fixture-nocustom.gitignore" $'# fixture nocustom\nmarker-nocustom')"
  url_file="$TEST_ROOT/urls-nocustom.txt"
  output_file="$TEST_ROOT/out-nocustom.gitignore"

  to_file_url "$fixture" > "$url_file"
  out="$("$SUT" "$url_file" --output "$output_file" --custom "$TEST_ROOT/does-not-exist.gitignore" 2>&1)"

  [[ "$out" == *"No custom patterns file, skipping:"* ]] || fail "Expected the missing custom file to be reported"
  assert_file_contains "$output_file" "marker-nocustom"
  assert_file_not_contains "$output_file" "# Plus local patterns from"
  assert_single_trailing_newline "$output_file"
}

# A file of nothing but blank lines contributes no block, so the header must not
# announce one either.
test_empty_custom_file_adds_nothing() {
  local fixture url_file output_file custom_file
  fixture="$(new_fixture "fixture-emptycustom.gitignore" $'# fixture emptycustom\nmarker-emptycustom')"
  url_file="$TEST_ROOT/urls-emptycustom.txt"
  output_file="$TEST_ROOT/out-emptycustom.gitignore"
  custom_file="$(new_fixture "custom-empty.gitignore" $'\n')"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" --custom "$custom_file" > /dev/null

  assert_file_contains "$output_file" "marker-emptycustom"
  assert_file_not_contains "$output_file" "# Plus local patterns from"
  assert_single_trailing_newline "$output_file"
}

# The custom file is hand-edited, so it can arrive with CRLF endings and padding
# blank lines at either end. None of that should reach the generated file.
test_custom_file_endings_are_normalized() {
  local fixture url_file output_file custom_file
  fixture="$(new_fixture "fixture-crlf.gitignore" $'# fixture crlf\nmarker-crlf-fetched')"
  url_file="$TEST_ROOT/urls-crlf.txt"
  output_file="$TEST_ROOT/out-crlf.gitignore"
  custom_file="$TEST_ROOT/custom-crlf.gitignore"
  printf '\r\n# crlf block\r\nmarker-crlf-pattern/\r\n\r\n\r\n' > "$custom_file"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" --custom "$custom_file" > /dev/null

  assert_file_contains "$output_file" "marker-crlf-pattern/"
  if grep -q $'\r' "$output_file"; then
    fail "Expected no carriage returns in $output_file"
  fi
  assert_single_trailing_newline "$output_file"
}

# Without --custom the default resolves beside the script, not against the
# working directory, so the same run works from anywhere.
test_default_custom_file_is_used() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-defaultcustom.gitignore" $'# fixture defaultcustom\nmarker-defaultcustom')"
  url_file="$TEST_ROOT/urls-defaultcustom.txt"
  output_file="$TEST_ROOT/out-defaultcustom.gitignore"

  to_file_url "$fixture" > "$url_file"
  (cd "$TEST_ROOT" && "$SUT" "$url_file" --output "$output_file" > /dev/null)

  assert_file_contains "$output_file" "# Plus local patterns from scripts/custom.gitignore"
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

test_handles_no_trailing_newline() {
  local fixture_one fixture_two url_file output_file
  fixture_one="$(new_fixture "fixture-noeol-one.gitignore" $'# fixture noeol one\nmarker-noeol-one')"
  fixture_two="$(new_fixture "fixture-noeol-two.gitignore" $'# fixture noeol two\nmarker-noeol-two')"
  url_file="$TEST_ROOT/urls-noeol.txt"
  output_file="$TEST_ROOT/out-noeol.gitignore"

  # Write two URLs; use printf without trailing \n on the last line
  local url_one url_two
  url_one="$(to_file_url "$fixture_one")"
  url_two="$(to_file_url "$fixture_two")"
  printf '%s\n%s' "$url_one" "$url_two" > "$url_file"

  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "marker-noeol-one"
  assert_file_contains "$output_file" "marker-noeol-two"
}

test_preserves_literal_backslashes_and_escape_sequences() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-literal.gitignore" $'# fixture literal\nliteral-backslash-n: \\n\n-n should stay literal\npath\\with\\slashes')"
  url_file="$TEST_ROOT/urls-literal.txt"
  output_file="$TEST_ROOT/out-literal.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" "$url_file" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" 'literal-backslash-n: \n'
  assert_file_contains "$output_file" "-n should stay literal"
  assert_file_contains "$output_file" 'path\with\slashes'
  assert_file_contains "$output_file" "# End of file://$fixture"
}

# The generator is the only thing here that reaches the network, and the rest of
# this suite stays offline by serving fixtures over file:// URLs. The built-in
# default list cannot be expressed that way, so curl is stubbed instead. The stub
# honors -o and ignores everything else, which is all the generator asks of it.
stub_curl_dir() {
  local dir="$TEST_ROOT/stub-bin"
  mkdir -p "$dir"
  cat > "$dir/curl" << 'STUB'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '# stubbed template\nstub-marker\n' > "${out:-/dev/stdout}"
STUB
  chmod +x "$dir/curl"
  printf '%s\n' "$dir"
}

# The regression test. A non-interactive caller supplies a stdin that is not a
# terminal and carries nothing to read, and the defaults have to be used. Before
# the input dispatch distinguished a pipe from any non-terminal, this run read an
# empty stdin, collected no URLs, and exited 1 complaining it had none.
test_defaults_are_used_when_stdin_carries_nothing() {
  local stub_dir output_file out
  stub_dir="$(stub_curl_dir)"
  output_file="$TEST_ROOT/out-defaults.gitignore"

  out="$(PATH="$stub_dir:$PATH" "$SUT" --output "$output_file" < /dev/null 2>&1)"

  [[ "$out" != *"No URLs provided."* ]] || fail "Expected the defaults when stdin carries nothing"
  assert_file_contains "$output_file" "# - https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore"
  assert_file_contains "$output_file" "stub-marker"
}

# The other half of the dispatch, and the reason the test above cannot simply
# treat every non-terminal stdin as empty: both of these forms are documented,
# and an earlier revision of this script honored only the pipe.
test_piped_urls_are_read() {
  local fixture output_file
  fixture="$(new_fixture "fixture-piped.gitignore" $'# fixture piped\nmarker-piped')"
  output_file="$TEST_ROOT/out-piped.gitignore"

  to_file_url "$fixture" | "$SUT" --output "$output_file" > /dev/null

  assert_file_contains "$output_file" "marker-piped"
}

test_redirected_urls_are_read() {
  local fixture url_file output_file
  fixture="$(new_fixture "fixture-redirected.gitignore" $'# fixture redirected\nmarker-redirected')"
  url_file="$TEST_ROOT/urls-redirected.txt"
  output_file="$TEST_ROOT/out-redirected.gitignore"

  to_file_url "$fixture" > "$url_file"
  "$SUT" --output "$output_file" < "$url_file" > /dev/null

  assert_file_contains "$output_file" "marker-redirected"
}

tests=(
  test_help_exits_zero
  test_help_prints_usage
  test_unknown_option_fails
  test_output_missing_arg_fails
  test_custom_missing_arg_fails
  test_fetches_from_file_url
  test_output_contains_header
  test_output_contains_fetched_content
  test_output_contains_builtin_tail
  test_custom_file_is_appended
  test_missing_custom_file_is_skipped
  test_empty_custom_file_adds_nothing
  test_custom_file_endings_are_normalized
  test_default_custom_file_is_used
  test_multiple_urls_in_file
  test_ignores_single_hash_comments_in_input
  test_preserves_section_labels_and_input_order
  test_handles_no_trailing_newline
  test_preserves_literal_backslashes_and_escape_sequences
  test_defaults_are_used_when_stdin_carries_nothing
  test_piped_urls_are_read
  test_redirected_urls_are_read
)

for test_name in "${tests[@]}"; do
  if ! ("$test_name"); then
    printf '[FAIL] %s (test runner halted)\n' "$test_name" >&2
    exit 1
  fi
  printf '[PASS] %s\n' "$test_name"
done

printf '\nAll %d tests passed.\n' "${#tests[@]}"
