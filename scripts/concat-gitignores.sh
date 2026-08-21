#!/usr/bin/env bash

set -euo pipefail # Exit on errors, unbound vars, and failed pipelines

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [--output <output_file>] [--custom <custom_file>] [<input_file>]

Concatenate multiple .gitignore templates into a single file by fetching URLs from
stdin, a file, or built-in defaults.

Inputs:
  stdin            Read URLs from standard input when piped or redirected.
  <input_file>     Optional file containing one URL per line. Supports section headers
                   with lines starting "## ". A single argument ending with /.gitignore
                   (e.g. my-project/.gitignore) is treated as the output path (relative
                   to repo root) and default URLs are used.

Options:
  --output <file>  Destination file name. Defaults to .gitignore.
  --custom <file>  Repository-specific patterns to append verbatim after the
                   fetched templates. Defaults to custom.gitignore beside this
                   script, and is skipped without error when absent.
  -h, --help       Show this help message and exit.

Examples:
  cat urls.txt | $SCRIPT_NAME
  cat urls.txt | $SCRIPT_NAME --output custom.output.gitignore
  $SCRIPT_NAME
  $SCRIPT_NAME urls.txt
  $SCRIPT_NAME urls.txt --output custom.output.gitignore
  $SCRIPT_NAME my-project/.gitignore
  $SCRIPT_NAME --custom other-patterns.gitignore
EOF
  exit "${1:-0}"
}

# Hardcoded default entries (used if no input is provided). Section headers
# (## Title) appear in the generated .gitignore header; URLs are fetched.
DEFAULT_ENTRIES=(
  "## Language / runtime / ecosystem"
  "https://raw.githubusercontent.com/github/gitignore/main/community/Python/JupyterNotebooks.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Node.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore"

  "## IDEs / editors"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Cloud9.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Cursor.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Eclipse.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Emacs.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/JetBrains.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/SublimeText.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Vim.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/VisualStudioCode.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/VisualStudio.gitignore"

  "## OS / platform"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Linux.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/macOS.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Windows.gitignore"

  "## Tools / documents / misc artifacts"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Archives.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Backup.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Diff.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/MicrosoftOffice.gitignore"
  "https://raw.githubusercontent.com/github/gitignore/main/Global/Patch.gitignore"
)

# Default output file
OUTPUT_FILE=".gitignore"

# Variables
INPUT_FILE=""
# Repository-specific patterns live beside this script rather than inside it, so
# the script itself can be synced between repositories unchanged.
CUSTOM_FILE="$SCRIPT_DIR/custom.gitignore"
ENTRIES=()
URLS=()

add_entry() {
  local line="$1"
  local trimmed="$line"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && return 0
  if [[ "$trimmed" == "## "* ]]; then
    ENTRIES+=("$trimmed")
  elif [[ "$trimmed" == \#* ]]; then
    return 0
  else
    ENTRIES+=("$trimmed")
    URLS+=("$trimmed")
  fi
}

parse_input_stream() {
  local line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    add_entry "$line"
  done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ -z ${2:-} ]]; then
        echo "Error: --output requires a file name." >&2
        usage 1
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --custom)
      if [[ -z ${2:-} ]]; then
        echo "Error: --custom requires a file name." >&2
        usage 1
      fi
      CUSTOM_FILE="$2"
      shift 2
      ;;
    -h | --help)
      usage 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      if [[ -z $INPUT_FILE ]]; then
        INPUT_FILE="$1"
        shift
      else
        echo "Error: Multiple input files specified: '$INPUT_FILE' and '$1'" >&2
        usage 1
      fi
      ;;
  esac
done

# If the only positional argument looks like an output path (e.g. my-project/.gitignore),
# treat it as --output and use default URLs. Resolve relative to repo root (parent of
# script dir) so the same path is used regardless of current working directory.
if [[ -n $INPUT_FILE && $INPUT_FILE == */.gitignore ]]; then
  OUTPUT_FILE="$REPO_ROOT/$INPUT_FILE"
  INPUT_FILE=""
fi

# Determine the source of URLs.
# Priority: explicit input file > stdin (pipe or redirection) > defaults.
if [[ -n $INPUT_FILE ]]; then
  if [[ -f $INPUT_FILE ]]; then
    parse_input_stream < "$INPUT_FILE"
  else
    echo "Input file not found: $INPUT_FILE" >&2
    exit 1
  fi
# A pipe or a redirected file, rather than the broader "stdin is not a
# terminal". A non-interactive parent hands this script a socket or a null
# device, and the broader test was true for both: the read then either blocked
# forever, measured on a socket, or reached end of file at once and exited with
# "No URLs provided", measured on a null device. Neither shape is a pipe or a
# file, so both now fall through to the defaults below. An inherited pipe is
# still read, which is what the usage above promises.
elif [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
  parse_input_stream
else
  for entry in "${DEFAULT_ENTRIES[@]}"; do
    add_entry "$entry"
  done
fi

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "No URLs provided." >&2
  exit 1
fi

# Read the repository-specific patterns up front so the generated header and the
# appended block agree on whether there are any.
CUSTOM_CONTENT=""
CUSTOM_BANNER_LINE=""
if [[ -f "$CUSTOM_FILE" ]]; then
  # Leading blank lines are dropped here and trailing ones by the command
  # substitution, so the block is separated from the patterns above it by exactly
  # one blank line however the file happens to be spaced.
  CUSTOM_CONTENT=$(awk '
    { gsub(/\r$/, ""); gsub(/[ \t]+$/, "") }
    !seen && $0 == "" { next }
    { seen = 1; print }
  ' "$CUSTOM_FILE")
fi

if [[ -n "$CUSTOM_CONTENT" ]]; then
  # Shown relative to the repo root when possible: this line is committed, and an
  # absolute path would bake one checkout's location into every copy.
  CUSTOM_FILE_DISPLAY="$CUSTOM_FILE"
  case "$CUSTOM_FILE_DISPLAY" in
    "$REPO_ROOT"/*) CUSTOM_FILE_DISPLAY="${CUSTOM_FILE_DISPLAY#"$REPO_ROOT"/}" ;;
  esac
  CUSTOM_BANNER_LINE="# Plus local patterns from $CUSTOM_FILE_DISPLAY"
elif [[ -f "$CUSTOM_FILE" ]]; then
  echo "Custom patterns file is empty, skipping: $CUSTOM_FILE"
else
  echo "No custom patterns file, skipping: $CUSTOM_FILE"
fi

# Calculate the length of the longest header line (for ruler)
MAX_HEADER_LINE_LENGTH=0
for entry in "${ENTRIES[@]}"; do
  if [[ "$entry" == "## "* ]]; then
    HEADER_LINE="# ${entry#\#\# }"
  else
    HEADER_LINE="# - $entry"
  fi
  if [[ ${#HEADER_LINE} -gt $MAX_HEADER_LINE_LENGTH ]]; then
    MAX_HEADER_LINE_LENGTH=${#HEADER_LINE}
  fi
done
if [[ ${#CUSTOM_BANNER_LINE} -gt $MAX_HEADER_LINE_LENGTH ]]; then
  MAX_HEADER_LINE_LENGTH=${#CUSTOM_BANNER_LINE}
fi

# Create the comment header
HEADER_LENGTH=$MAX_HEADER_LINE_LENGTH
HEADER=$(printf '#%.0s' $(seq 1 "$HEADER_LENGTH"))

OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [[ ! -d "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR" || {
    echo "Error: cannot create directory '$OUTPUT_DIR' for output file." >&2
    exit 1
  }
fi

{
  echo "$HEADER"
  echo "# This .gitignore is composed of the following templates (retrieved $(date +%Y-%m-%d)):"
  for entry in "${ENTRIES[@]}"; do
    if [[ "$entry" == "## "* ]]; then
      echo "# ${entry#\#\# }"
    else
      echo "# - $entry"
    fi
  done
  [[ -n "$CUSTOM_BANNER_LINE" ]] && echo "$CUSTOM_BANNER_LINE"
  echo "$HEADER"
  echo ""
} > "$OUTPUT_FILE"

echo "Initialized output file with header: $OUTPUT_FILE"

# Convert blob URL to raw URL if needed (user-supplied input may use blob format)
to_raw_url() {
  local u="$1"
  if [[ "$u" == *"/blob/"* ]]; then
    echo "$u" | sed 's|github.com|raw.githubusercontent.com|; s|/blob||'
  else
    echo "$u"
  fi
}

# Loop through URLs
for url in "${URLS[@]}"; do
  echo "Processing URL: $url"

  RAW_URL=$(to_raw_url "$url")
  if [[ "$url" != "$RAW_URL" ]]; then
    echo "Converted to raw URL: $RAW_URL"
  fi

  # Extract the filename (e.g., Python.gitignore)
  FILENAME=$(basename "$url")

  # Calculate dynamic block length
  PREFACE_LENGTH=$((${#FILENAME} + 4)) # Length of " # FILENAME # "
  PREFACE=$(printf '#%.0s' $(seq 1 $PREFACE_LENGTH))

  # Preface block
  {
    echo "$PREFACE"
    echo "# $FILENAME #"
    echo "$PREFACE"
    echo ""
  } >> "$OUTPUT_FILE"

  # Fetch content (curl -f: fail on HTTP 4xx/5xx)
  TMP_CURL=$(mktemp)
  if ! curl -f -s "$RAW_URL" -o "$TMP_CURL"; then
    rm -f "$TMP_CURL"
    echo "Failed to fetch: $RAW_URL" >&2
    exit 1
  fi
  # macOS.gitignore encodes the CR-suffixed "Icon" file as the bracket class
  # `Icon[\r]` (a literal CR inside `[...]`). Stripping CR only at end-of-line
  # leaves the empty class `Icon[]`, which git matches literally, so collapse
  # the class before the end-of-line strip.
  CONTENT=$(awk '{ gsub(/\[\r\]/, ""); gsub(/\r$/, ""); gsub(/[ \t]+$/, ""); print }' "$TMP_CURL")
  rm -f "$TMP_CURL"

  if [[ -z "$CONTENT" ]]; then
    echo "Empty content from: $RAW_URL" >&2
    exit 1
  fi

  # Reject HTML (e.g. GitHub error page)
  content_prefix="${CONTENT:0:256}"
  if [[ "$content_prefix" =~ ^[[:space:]]*\<\![[:space:]]*[Dd][Oo][Cc][Tt][Yy][Pp][Ee] ]] ||
    [[ "$content_prefix" =~ ^[[:space:]]*\<[Hh][Tt][Mm][Ll] ]]; then
    echo "Received HTML instead of gitignore content from: $RAW_URL" >&2
    exit 1
  fi

  echo "Appending content from: $RAW_URL"
  printf '%s\n' "$CONTENT" >> "$OUTPUT_FILE"
  printf '\n# End of %s\n\n' "$url" >> "$OUTPUT_FILE"
done

# Normalize line endings in the final output file
NORMALIZE_TMP=$(mktemp)
tr -d '\r' < "$OUTPUT_FILE" > "$NORMALIZE_TMP" || {
  rm -f "$NORMALIZE_TMP"
  exit 1
}
mv "$NORMALIZE_TMP" "$OUTPUT_FILE"

# Ensure single trailing newline (collapse any trailing blank lines into exactly one newline)
ensure_single_trailing_newline() {
  local file="$1"
  if command -v perl > /dev/null 2>&1; then
    perl -0777 -pi -e 's/\n*\z/\n/' "$file"
  else
    # Command substitution strips trailing newlines; print one newline back.
    local content
    content=$(< "$file")
    printf '%s\n' "$content" > "$file"
  fi
}

ensure_single_trailing_newline "$OUTPUT_FILE"

# Add the ignore patterns that suit any repository. Tool and layout choices that
# vary between repositories belong in the custom file appended below instead.
# Quoted so the block is emitted verbatim: these are gitignore glob patterns, and
# an unquoted heredoc would treat a `$` or a backtick in one as an expansion.
cat >> "$OUTPUT_FILE" << 'EOF'

# Claude user-specific settings
.claude/settings.local.json

# Directory for temporary files marked for deletion
.delete-me/

!.gitkeep
# `bin/` and `**/[Bb]in/*` above (virtualenv and Visual Studio) would otherwise
# ignore a package's own bin/ directory, so re-include it.
!src/*/bin
!src/*/bin/**
# `lib/` above (a build-output convention) would otherwise ignore this
# repository's own shell helper library, silently: the files stay untracked and
# `git add` says nothing about why.
!scripts/lib/
!scripts/lib/**
# ...but the re-include is broad enough to bring back build artifacts with it,
# so ignore those again. Last match wins, so these must follow the negations.
src/*/bin/**/__pycache__/
src/*/bin/**/*.py[cod]
EOF

# Append the repository-specific patterns last so they win wherever they overlap
# with a pattern above. Read before any output was written, so an unreadable or
# empty file has already been reported.
if [[ -n "$CUSTOM_CONTENT" ]]; then
  printf '\n%s\n' "$CUSTOM_CONTENT" >> "$OUTPUT_FILE"
  echo "Appended custom patterns from: $CUSTOM_FILE"
fi

ensure_single_trailing_newline "$OUTPUT_FILE"

echo "Combined .gitignore created as $OUTPUT_FILE"
