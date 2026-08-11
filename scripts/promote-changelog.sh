#!/usr/bin/env bash

# Promote the Unreleased section of CHANGELOG.md into a versioned section.
#
# Renames the existing `## [Unreleased]` heading to
# `## [X.Y.Z](<compare-url>) - YYYY-MM-DD`, keeping everything beneath it, and
# prepends a fresh empty `## [Unreleased]` so the commits that land after this
# release have somewhere to accumulate.
#
# This script edits one file and does nothing else: no staging, no commit, no
# tag, no push. That is what makes it reusable -- the caller (`make release-pr`)
# owns the git side, this can be pointed at a scratch copy of the changelog with
# `--changelog`, and undoing a bad run is `git checkout -- CHANGELOG.md`.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat << EOF
Usage: $SCRIPT_NAME <VERSION> [OPTIONS]

Promote the Unreleased section of CHANGELOG.md to [VERSION] - YYYY-MM-DD.

Arguments:
  VERSION              PEP 440 version string (leading 'v' optional; stripped if present).
                       Examples: 0.0.1, 0.1.0, 1.2.3rc1, 0.5.0a2

Options:
  --no-refresh         Skip running scripts/update-unreleased.sh first.
                       By default, this script refreshes the Unreleased
                       section from git history before promoting it.
  --changelog PATH     Path to changelog file (default: CHANGELOG.md).
  -h, --help           Show this help and exit.

Examples:
  $SCRIPT_NAME 0.0.1
  $SCRIPT_NAME 0.1.0rc1 --no-refresh
EOF
  exit "${1:-0}"
}

die() {
  echo "Error: $1" >&2
  shift
  for line in "$@"; do
    echo "       $line" >&2
  done
  exit 1
}

# Validate PEP 440 version (subset: X.Y.Z[{a,b,rc}N][.postN][.devN]).
# Full PEP 440 also admits epochs, local version labels and several spellings of
# each separator. None of those can be released here -- the tag is vX.Y.Z and the
# version has to round-trip through `uv version` -- so the subset is the check.
is_valid_version() {
  local v="$1"
  [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+((a|b|rc)[0-9]+)?(\.post[0-9]+)?(\.dev[0-9]+)?$ ]]
}

VERSION=""
SKIP_REFRESH=false
CHANGELOG="CHANGELOG.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage 0 ;;
    --no-refresh)
      SKIP_REFRESH=true
      shift
      ;;
    --changelog)
      [[ -n "${2:-}" ]] || {
        echo "Error: --changelog requires a path" >&2
        usage 1
      }
      CHANGELOG="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage 1
      ;;
    *)
      [[ -z "$VERSION" ]] || {
        echo "Error: only one version argument allowed" >&2
        usage 1
      }
      VERSION="$1"
      shift
      ;;
  esac
done

[[ -n "$VERSION" ]] || {
  echo "Error: VERSION argument is required" >&2
  usage 1
}

# Accept either '0.0.1' or 'v0.0.1' -- the leading 'v' belongs to the tag, not to
# the version recorded in pyproject.toml. Strip it silently so this behaves the
# same whether it is invoked by hand or by the release-PR script (which strips
# the prefix too).
if [[ "$VERSION" == v* ]]; then
  VERSION="${VERSION#v}"
fi

if ! is_valid_version "$VERSION"; then
  die "'$VERSION' is not a recognized PEP 440 version (examples: 0.0.1, 0.1.0rc1)"
fi

# Checked explicitly rather than left to the `cd` below: outside a work tree
# `git rev-parse --show-toplevel` writes to stderr and prints nothing, and
# `cd ""` is a successful no-op, so the run would continue in the wrong
# directory and fail later with a confusing "does not exist".
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  die "must be run from inside a git repository."
fi

# Resolve a relative --changelog against the current directory *before* moving to
# the repository root, so `--changelog ../notes/CHANGELOG.md` means what it says
# when this is run from a subdirectory. `pwd -P` resolves symlinks, which keeps
# the path comparable on macOS (/tmp is a link to /private/tmp).
if [[ "$CHANGELOG" != /* ]]; then
  CHANGELOG="$(pwd -P)/$CHANGELOG"
fi

cd "$(git rev-parse --show-toplevel)"
REPO_ROOT="$(pwd -P)"

# Back to a repository-relative path where possible, purely so the messages this
# prints are readable. A changelog outside the repository stays absolute.
case "$CHANGELOG" in
  "$REPO_ROOT"/*) CHANGELOG="${CHANGELOG#"$REPO_ROOT/"}" ;;
esac

[[ -f "$CHANGELOG" ]] || die "$CHANGELOG does not exist"

# Refresh the Unreleased section first so the promoted block reflects current
# HEAD. A missing sibling script is fatal rather than a warning: skipping the
# refresh promotes a stale section into a heading that is about to be tagged and
# published, and a warning in the middle of a release run is not read in time.
# `--no-refresh` is the supported way to opt out.
if [[ "$SKIP_REFRESH" == false ]]; then
  [[ -f "$SCRIPT_DIR/update-unreleased.sh" ]] || die \
    "$SCRIPT_DIR/update-unreleased.sh not found." \
    "Pass --no-refresh to promote the section as it already stands."
  echo "Refreshing Unreleased section from git history..."
  bash "$SCRIPT_DIR/update-unreleased.sh" --changelog "$CHANGELOG"
fi

grep -q '^## \[Unreleased\]' "$CHANGELOG" || die \
  "$CHANGELOG has no '## [Unreleased]' heading to promote." \
  "Generate one with scripts/update-unreleased.sh, or add the heading by hand."

# Bail if the Unreleased section is empty (only the heading, plus maybe blank
# lines). A section worth releasing carries at least one '### <Group>' heading or
# one bullet; promoting an empty one publishes a version that says nothing
# changed, which is worse than refusing.
if ! awk '
  /^## \[Unreleased\]/ { in_unreleased = 1; next }
  in_unreleased && /^## \[/ { exit }
  in_unreleased && /^(### |- )/ { found = 1; exit }
  END { exit !found }
' "$CHANGELOG"; then
  die "$CHANGELOG has no commits under [Unreleased] to promote." \
    "Either land at least one conventional commit since the last release," \
    "or run with --no-refresh if you intentionally seeded the section."
fi

# Local date, not UTC. This date is read as the release date by humans, and the
# tag script re-checks it against its own local `date` before creating the tag.
# A UTC date would disagree with both for part of every day west of Greenwich,
# turning an evening release into a refused tag the next morning.
DATE="$(date +%Y-%m-%d)"

# Build the compare URL for the new heading, when a previous tag exists, so the
# promoted heading is shaped like the ones git-cliff renders from cliff.toml.
#
# `git describe` rather than a version sort over all tags: describe picks the
# most recent tag *reachable from HEAD*, whereas the globally highest tag would
# produce a nonsensical compare range when releasing from a maintenance branch.
PREV_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2> /dev/null || true)"
REMOTE_URL="$(git config --get remote.origin.url || true)"

# A tag for the version being released is already reachable (a re-run, or a tag
# pushed ahead of the changelog). Comparing a tag against itself links to an
# empty diff, so fall back to the plain heading instead.
if [[ "$PREV_TAG" == "v$VERSION" ]]; then
  PREV_TAG=""
fi

format_repo_url() {
  # Convert git@github.com:owner/repo.git -> https://github.com/owner/repo
  local url="$1"
  url="${url%.git}"
  if [[ $url == git@*:* ]]; then
    # Drop the user@ prefix first so the only ':' left is the host/path
    # separator, then turn that single ':' into '/' before prepending the
    # scheme. Replacing ':' while the scheme is already present would clobber
    # the "https:" colon and emit "https///host:owner/repo".
    url="${url#git@}"
    url="https://${url/://}"
  fi
  # Strip any userinfo segment from https/http URLs so a tokenized remote
  # (e.g. https://TOKEN@github.com/...) cannot write a credential into the
  # changelog, which is committed, pushed and published. Anchored at the scheme
  # so this only ever rewrites the authority, never something later in the path.
  if [[ $url =~ ^(https?)://[^/]*@(.*)$ ]]; then
    url="${BASH_REMATCH[1]}://${BASH_REMATCH[2]}"
  fi
  echo "$url"
}

REPO_URL=""
if [[ -n "$REMOTE_URL" ]]; then
  REPO_URL="$(format_repo_url "$REMOTE_URL")"
fi

# Both shapes come from cliff.toml's changelog body: a compare link when there is
# a previous release to compare against, a bare heading for the first one.
if [[ -n "$PREV_TAG" && -n "$REPO_URL" ]]; then
  HEADING="## [$VERSION]($REPO_URL/compare/$PREV_TAG..v$VERSION) - $DATE"
else
  HEADING="## [$VERSION] - $DATE"
fi

# Promote: rename the existing `## [Unreleased]` heading to the versioned
# heading, keeping everything beneath it, and prepend a fresh empty Unreleased
# section above it. One awk pass into a temporary file, so a failure partway
# through leaves the changelog untouched rather than half-rewritten.
TEMP_NEW="$(mktemp)"
trap 'rm -f "$TEMP_NEW"' EXIT

awk -v heading="$HEADING" '
  BEGIN { promoted = 0 }
  /^## \[Unreleased\]/ && !promoted {
    print "## [Unreleased]"
    print ""
    print heading
    promoted = 1
    next
  }
  { print }
  END {
    if (!promoted) {
      print "Error: no `## [Unreleased]` heading found in changelog" > "/dev/stderr"
      exit 1
    }
  }
' "$CHANGELOG" > "$TEMP_NEW"

# Copied over the original rather than moved onto it: mktemp creates the
# temporary file 0600, and both rename and cross-device move would carry that
# mode onto a file everyone else expects to be readable.
cat "$TEMP_NEW" > "$CHANGELOG"
rm -f "$TEMP_NEW"
trap - EXIT

echo "Promoted [Unreleased] -> ${HEADING#'## '}"
echo "Edited:  $CHANGELOG"
