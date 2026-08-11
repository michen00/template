#!/usr/bin/env bash

# Open a release PR for VERSION.
#
# Workflow:
#   1. Validate VERSION (PEP 440) and the working tree state
#   2. Promote CHANGELOG.md Unreleased -> [VERSION] - YYYY-MM-DD
#   3. Bump the project version in pyproject.toml and re-lock uv.lock
#   4. Create a release branch (release/vX.Y.Z) from the current branch
#   5. Commit and push the branch
#   6. Open a draft PR via gh
#
# This script does not tag, build, or publish anything. After the PR merges,
# push the annotated tag vX.Y.Z to start the release.
#
# Every mutation is gated behind the preconditions below, which exist because
# the failure modes they catch are silent: a stale checkout promotes a changelog
# that is missing recently merged commits, a duplicate tag produces a release
# nobody can reproduce, and a colliding release branch races another
# maintainer's in-flight PR.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat << EOF
Usage: $SCRIPT_NAME <VERSION> [OPTIONS]

Open a release PR for VERSION.

Arguments:
  VERSION              PEP 440 version string (leading 'v' optional; stripped if present).

Options:
  --base BRANCH        Base branch for the PR (default: repository default branch).
  --no-push            Skip pushing the branch and opening a PR (local-only).
  --ready              Open the PR ready-for-review instead of draft.
  -h, --help           Show this help and exit.

Examples:
  $SCRIPT_NAME 0.0.1
  $SCRIPT_NAME 0.1.0rc1 --no-push
EOF
  exit "${1:-0}"
}

# Anchored on purpose. An unanchored pattern (or a shell glob such as
# 'v[0-9]*.[0-9]*.[0-9]*') happily accepts 'v1abc.2.3', which would produce a
# tag that sorts nowhere sensible and a version the build backend rejects.
is_valid_version() {
  local v="$1"
  [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+((a|b|rc)[0-9]+)?(\.post[0-9]+)?(\.dev[0-9]+)?$ ]]
}

VERSION=""
BASE_BRANCH=""
DO_PUSH=true
DRAFT_FLAG=(--draft)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage 0 ;;
    --no-push)
      DO_PUSH=false
      shift
      ;;
    --ready)
      DRAFT_FLAG=()
      shift
      ;;
    --base)
      [[ -n "${2:-}" ]] || {
        echo "Error: --base requires a branch name" >&2
        usage 1
      }
      BASE_BRANCH="$2"
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

# Accept either '0.0.1' or 'v0.0.1' — the tag is always v$VERSION downstream,
# so a leading 'v' is redundant. Strip it with a stderr note so callers see
# what we landed on.
if [[ "$VERSION" == v* ]]; then
  echo "Note: stripping leading 'v' from VERSION; using '${VERSION#v}' (tag will be v${VERSION#v})." >&2
  VERSION="${VERSION#v}"
fi

if ! is_valid_version "$VERSION"; then
  echo "Error: '$VERSION' is not a recognized PEP 440 version" >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

# Preconditions
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree has uncommitted changes. Commit, stash, or discard first." >&2
  exit 1
fi

# Resolve base branch
if [[ -z "$BASE_BRANCH" ]]; then
  if command -v gh > /dev/null 2>&1; then
    BASE_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2> /dev/null || true)"
  fi
  BASE_BRANCH="${BASE_BRANCH:-main}"
fi

# Refuse to release a version whose tag already exists
TAG="v$VERSION"
if git rev-parse --verify --quiet "refs/tags/$TAG" > /dev/null; then
  echo "Error: tag $TAG already exists locally." >&2
  exit 1
fi
# Check origin for an existing tag without mutating local state. A
# `git fetch && exit 1 || true` form would swallow every fetch failure (auth,
# DNS, transient origin errors) as "tag not found", which could let a duplicate
# release proceed. `git ls-remote` is read-only and lets us distinguish
# "no matching ref" (empty stdout, exit 0) from "query failed" (non-zero exit).
# Skip in --no-push mode so a local rehearsal can run without network access;
# the eventual push path re-checks origin before any release ref is created.
if [[ "$DO_PUSH" == true ]]; then
  # The `|| ls_remote_status=$?` is load-bearing: under `set -e` a plain
  # `var="$(cmd)"` assignment aborts the script the instant the substitution
  # fails, so a bare `$?` on the next line can never observe a failure and the
  # "query failed" branch below would be unreachable.
  ls_remote_status=0
  remote_tag_refs="$(git ls-remote --tags origin "refs/tags/$TAG" 2>&1)" ||
    ls_remote_status=$?
  if [[ $ls_remote_status -ne 0 ]]; then
    echo "Error: failed to query origin for tag $TAG (exit $ls_remote_status):" >&2
    printf '%s\n' "$remote_tag_refs" >&2
    exit 1
  fi
  if [[ -n "$remote_tag_refs" ]]; then
    echo "Error: tag $TAG already exists on origin." >&2
    exit 1
  fi
fi

RELEASE_BRANCH="release/$TAG"
if git rev-parse --verify --quiet "refs/heads/$RELEASE_BRANCH" > /dev/null; then
  echo "Error: branch $RELEASE_BRANCH already exists locally." >&2
  exit 1
fi

# Refuse to push to a release branch that already exists on origin.
# The local branch is created below, so `git push` would either fail with a
# confusing non-fast-forward error or, worse, race another maintainer's
# in-flight release PR. Detect the collision up front with a clear message.
if [[ "$DO_PUSH" == true ]] &&
  [[ -n "$(git ls-remote --heads origin "refs/heads/$RELEASE_BRANCH" 2> /dev/null)" ]]; then
  echo "Error: branch $RELEASE_BRANCH already exists on origin." >&2
  echo "       Another maintainer may have an in-flight release PR for $VERSION." >&2
  exit 1
fi

# Defensive: refuse to fork the release branch from anything other than the
# resolved base branch. The runbook says to be on the base branch, but a stray
# feature branch checkout would silently produce a release PR with missing or
# extra commits.
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2> /dev/null || true)"
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  echo "Error: must be on '$BASE_BRANCH' to open a release PR (currently on '${CURRENT_BRANCH:-detached HEAD}')." >&2
  echo "       Run 'git switch $BASE_BRANCH && git pull --ff-only' first, or pass --base to override." >&2
  exit 1
fi

# Defensive: verify local HEAD matches origin/$BASE_BRANCH so the changelog gets
# promoted from the same history the maintainer thinks they are on. A stale
# local checkout would silently miss recently merged commits.
# Skip in --no-push mode so a local rehearsal can run without network access.
if [[ "$DO_PUSH" == true ]]; then
  if ! git fetch origin "$BASE_BRANCH" --quiet; then
    echo "Error: failed to fetch origin/$BASE_BRANCH" >&2
    exit 1
  fi
  LOCAL_SHA="$(git rev-parse HEAD)"
  REMOTE_SHA="$(git rev-parse "origin/$BASE_BRANCH")" || {
    echo "Error: cannot resolve origin/$BASE_BRANCH; run 'git fetch origin $BASE_BRANCH' first." >&2
    exit 1
  }
  if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
    echo "Error: local '$BASE_BRANCH' is out of sync with 'origin/$BASE_BRANCH'." >&2
    echo "       local HEAD          : $LOCAL_SHA" >&2
    echo "       origin/$BASE_BRANCH : $REMOTE_SHA" >&2
    echo "       Run 'git pull --ff-only origin $BASE_BRANCH' (or push your local commits) first." >&2
    exit 1
  fi
fi

# uv owns the version bump below, so fail here rather than half-way through the
# mutations with a promoted changelog already on disk.
if ! command -v uv > /dev/null 2>&1; then
  echo "Error: uv not found; it is required to bump the project version." >&2
  echo "       Install uv: https://docs.astral.sh/uv/getting-started/installation/" >&2
  exit 1
fi

# Everything past this point writes to the working tree. The clean-tree
# assertion above means anything modified from here on belongs to this run, so a
# failure can safely tell the maintainer exactly what to discard. Cleared once
# the commit lands, after which the recovery advice would be wrong.
RELEASE_FILES=(CHANGELOG.md pyproject.toml uv.lock)
report_dirty_worktree() {
  # `$?` is the status the script is exiting with; capture it before anything
  # else clobbers it. Written as an `if` rather than `[[ ... ]] && return`
  # because under `set -u`/`set -e` a failing AND-list aborts the handler and
  # swallows the advice below.
  local status=$?
  if [[ $status -eq 0 ]]; then
    return 0
  fi
  echo >&2
  echo "Error: aborted with release edits still in the working tree." >&2
  echo "       Discard them with: git restore ${RELEASE_FILES[*]}" >&2
}
trap report_dirty_worktree EXIT

# Promote CHANGELOG before creating the branch so promotion failures leave no
# orphaned release branch behind.
"$SCRIPT_DIR/promote-changelog.sh" "$VERSION"

if git diff --quiet CHANGELOG.md; then
  echo "Error: CHANGELOG.md was not modified by promotion. Aborting." >&2
  exit 1
fi

# Bump the version. This repository pins a static `version` in pyproject.toml
# and uv.lock records that same version for the project itself, while CI runs
# `uv run --locked` — so a bump that updates only pyproject.toml turns the
# release PR red on the very first job. `uv version <VALUE>` re-resolves and
# rewrites uv.lock as part of the bump; `--no-sync` keeps it from reinstalling
# .venv, which this script has no reason to touch. Never sed pyproject.toml: it
# would leave uv.lock stale.
uv version --no-sync "$VERSION"

# Belt and braces. `uv version` honors environment overrides (UV_FROZEN and
# friends) that can skip the re-lock, and a stale uv.lock is exactly the failure
# this step exists to prevent — so assert the outcome instead of trusting it.
ACTUAL_VERSION="$(uv version --short)"
if [[ "$ACTUAL_VERSION" != "$VERSION" ]]; then
  echo "Error: expected project version '$VERSION' after the bump, found '$ACTUAL_VERSION'." >&2
  exit 1
fi
if ! uv lock --check > /dev/null 2>&1; then
  echo "Note: uv.lock is out of date after the version bump; re-locking." >&2
  uv lock
fi

# Apply auto-fixers (markdownlint, trailing-whitespace, ...) to the freshly
# generated files before staging, so the subsequent `git commit` does not get
# blocked by a hook that auto-modifies them. git-cliff's default output emits
# content that markdownlint will line-wrap, and that mid-commit mutation cleanly
# aborts the script otherwise.
#
# `make develop` installs pre-commit into uv's project venv (not system PATH),
# so prefer `uv run pre-commit` and only fall back to a bare PATH `pre-commit`
# for environments that ship it directly (CI, pipx-installed personal setups).
# When neither is available, skip the pre-flight and let the subsequent
# `git commit` step surface any genuine hook failure.
#
# Distinguishing auto-fix from a hard failure matters: pre-commit returns
# non-zero in both cases. We hash the release files before and after; if exit is
# non-zero AND nothing changed, that is a hard fail (configuration error, hook
# crash, etc.) and we abort with a clear message rather than letting the
# maintainer hit the same error a few lines later in `git commit` with no
# context.
PRECOMMIT_CMD=()
if uv run pre-commit --version > /dev/null 2>&1; then
  PRECOMMIT_CMD=(uv run pre-commit)
elif command -v pre-commit > /dev/null 2>&1; then
  PRECOMMIT_CMD=(pre-commit)
fi
if [[ ${#PRECOMMIT_CMD[@]} -gt 0 ]]; then
  hashes_before="$(git hash-object "${RELEASE_FILES[@]}")"
  pre_commit_status=0
  "${PRECOMMIT_CMD[@]}" run --files "${RELEASE_FILES[@]}" || pre_commit_status=$?
  hashes_after="$(git hash-object "${RELEASE_FILES[@]}")"
  if [[ $pre_commit_status -ne 0 ]] &&
    [[ $hashes_before == "$hashes_after" ]]; then
    echo "Error: pre-commit hard-failed on the release files without modifying them (exit $pre_commit_status)." >&2
    echo "       Resolve the underlying issue and re-run $SCRIPT_NAME." >&2
    exit 1
  fi
fi

# `git switch -c` carries the uncommitted release edits onto the new branch, so
# the base branch is left exactly as it was found.
git switch -c "$RELEASE_BRANCH"

git add "${RELEASE_FILES[@]}"
git commit -m "chore(release): prepare $VERSION"

trap - EXIT

if [[ "$DO_PUSH" == false ]]; then
  echo
  echo "Local release branch ready: $RELEASE_BRANCH"
  echo "Skipped push and PR creation (--no-push)."
  exit 0
fi

if ! command -v gh > /dev/null 2>&1; then
  echo "Error: gh CLI not found. Install it or use --no-push." >&2
  echo "       The release branch '$RELEASE_BRANCH' is committed locally and can be pushed by hand." >&2
  exit 1
fi

git push -u origin "$RELEASE_BRANCH"

# The PR body is inlined rather than read from a form on disk: this repository
# ships no PR forms, and a release PR always says the same three things.
PR_TITLE="chore(release): $VERSION"
PR_BODY=$(
  cat << EOF
## Summary

Prepare the \`$TAG\` release off \`$BASE_BRANCH\`:

- promote the \`## [Unreleased]\` section of [CHANGELOG.md](CHANGELOG.md) to \`## [$VERSION]\`
- bump the project version to \`$VERSION\` in [pyproject.toml](pyproject.toml) and re-lock [uv.lock](uv.lock)

No functional changes. Review the entries under the \`[$VERSION]\` heading and edit them directly in this PR if any commit subjects need polishing for human readers.

## Test plan

- [ ] CHANGELOG entries under \`[$VERSION]\` accurately describe the changes since the previous release
- [ ] CI green (the re-locked \`uv.lock\` is what keeps \`uv run --locked\` happy)

## After merge

Tag the merge commit as \`$TAG\` and push the tag.
EOF
)

gh pr create \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --base "$BASE_BRANCH" \
  --head "$RELEASE_BRANCH" \
  "${DRAFT_FLAG[@]}"

echo
echo "Release PR opened. After it merges, tag $TAG on $BASE_BRANCH and push the tag."
