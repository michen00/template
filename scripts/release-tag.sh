#!/usr/bin/env bash

# Create and push the release tag, which is what fires .github/workflows/release.yml.
#
# Exists because the commands it replaces were hand-typed, and one of them carried a
# flag that must not be used. The preflight checks below all guard the same class of
# mistake -- tagging a commit that is not the one about to be released -- each of which
# would otherwise surface as a wrong or failed release run several minutes later.
#
# Pushing is part of this script because a tag that exists only locally does nothing;
# pushing it is what starts the release. That is reversible: the release publishes to no
# package registry, and both the release and the tag can be deleted.

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
CHANGELOG="CHANGELOG.md"

usage() {
  cat << EOF
Usage: $SCRIPT_NAME <version>

Create an annotated tag vX.Y.Z and push it, which triggers the release workflow.
Nothing is published to a package registry.

Arguments:
  <version>   Release version, with or without a leading 'v' (e.g. 0.4.2 or v0.4.2)

Example:
  $SCRIPT_NAME 0.4.2
EOF
  exit "${1:-0}"
}

die() {
  echo "Error: $1" >&2
  shift
  for line in "$@"; do
    echo "  $line" >&2
  done
  exit 1
}

if [ "$#" -ne 1 ]; then
  usage 1
fi

case "$1" in
  -h | --help) usage 0 ;;
esac

BARE="${1#v}"

# Anchored regex rather than a glob. `v[0-9]*.[0-9]*.[0-9]*` reads as if it means digits,
# but glob `*` is any-characters, so it admits v1abc.2.3 -- which would pass here and then
# fail somewhere less obvious, in whichever tool touches it first.
if [[ ! $BARE =~ ^[0-9]+\.[0-9]+\.[0-9]+([ab]|rc|post|dev)?[0-9]*$ ]]; then
  die "version must look like X.Y.Z, got '$1'."
fi
VERSION="v$BARE"

# The declared version is checked here as well as in the release workflow. The workflow's
# check is the one that matters, but reaching it costs a queue wait and a build first.
declared=$(python3 -c "$(
  cat << 'PY'
import pathlib
import tomllib

print(tomllib.loads(pathlib.Path("pyproject.toml").read_text())["project"]["version"])
PY
)")
if [ "$declared" != "$BARE" ]; then
  die "$BARE does not match pyproject.toml ($declared)." \
    "Bump the version first, or tag the version it already declares."
fi

# The changelog's date for this version is written when the release branch is prepared,
# which can be days before the tag, and it is what readers take as the release date.
# Checked here because this is the last moment before the tag exists, and because nothing
# downstream looks at the changelog date at all.
# Both heading shapes cliff.toml can render are accepted: it emits a compare link only
# when a previous tag exists, so the very first release of a project -- the case every
# new project hits -- has the bare `## [X.Y.Z] - <date>` form and would not match a
# pattern that assumed the link. The version is regex-escaped because it contains dots.
escaped_version=$(printf '%s' "$BARE" | sed 's/[.[\*^$]/\\&/g')
changelog_heading=$(grep -m1 -E "^## \[${escaped_version}\](\(| -)" "$CHANGELOG" || true)
if [ -z "$changelog_heading" ]; then
  die "$CHANGELOG has no section for $BARE." \
    "The release commit should have added one, so check that this tag is on the" \
    "commit you meant to release."
fi
today=$(date +%Y-%m-%d)
case "$changelog_heading" in
  *" - $today") ;;
  *)
    die "the $BARE changelog heading is not dated today ($today)." \
      "  $changelog_heading" \
      "That date is the release date as far as readers are concerned. Correct the" \
      "line on the default branch before tagging."
    ;;
esac

# Derived rather than assumed: a fork may use a different default branch name.
default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null || true)
default_branch="${default_branch#origin/}"
default_branch="${default_branch:-main}"

branch=$(git branch --show-current)
if [ "$branch" != "$default_branch" ]; then
  die "on '$branch', not $default_branch." \
    "A release tag names a commit on the default branch. Tagging elsewhere would" \
    "ship whatever that branch contains, and the tag would outlive the branch."
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "the working tree is dirty." \
    "The tag would name HEAD, not what you are looking at."
fi

git fetch origin "$default_branch" --quiet
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$default_branch")" ]; then
  die "$default_branch and origin/$default_branch point at different commits." \
    "The release workflow checks the tag out from the remote, so tagging a commit" \
    "that is not on origin/$default_branch would build something other than what" \
    "you tested."
fi

if git rev-parse --verify "refs/tags/$VERSION" > /dev/null 2>&1; then
  die "tag $VERSION already exists locally." \
    "Delete it first if you meant to re-cut it: git tag -d $VERSION"
fi

if git ls-remote --exit-code --tags origin "refs/tags/$VERSION" > /dev/null 2>&1; then
  die "tag $VERSION already exists on origin." \
    "That version has been cut. Release forward instead."
fi

# Annotated, and signed only where the repository is already set up for it: forcing `-s`
# would fail for anyone without a signing key configured, and this script has to work in
# a project one hour old. `git config tag.gpgsign` is the repository's own statement of
# intent, so it is honored rather than second-guessed.
if [ "$(git config --get tag.gpgsign || echo false)" = "true" ]; then
  git tag -a "$VERSION" -m "$VERSION" -s
  echo "Created signed tag $VERSION."
else
  git tag -a "$VERSION" -m "$VERSION"
  echo "Created tag $VERSION."
fi

# An explicit refspec rather than --follow-tags, which pushes more than it looks like.
# Per git-push(1) it also pushes "annotated tags in refs/tags that are missing from the
# remote but are pointing at commit-ish that are reachable from the refs being pushed" --
# so any stray local annotated tag would ride along having passed none of the checks
# above, and could start a release for a version nobody asked to release. Everything
# above validates exactly one tag; this pushes exactly that one.
#
# The default branch needs no push of its own: the check above already required HEAD and
# origin/$default_branch to be the same commit.
git push origin "refs/tags/$VERSION"
echo
echo "Pushed $VERSION. The release workflow is now building the release."
echo "  gh run watch"
