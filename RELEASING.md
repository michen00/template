# Releasing

This is the runbook for cutting a release. The flow is three commands with a human
review in the middle, and it produces exactly one artifact: a **GitHub Release** for the
tag.

It does **not** publish to PyPI. `make push-test` (TestPyPI) and `make push-prod` (PyPI)
are deliberately left separate and manual, so a release tag can never push a distribution
to a public index by accident. If a release also needs to go to an index, run those
targets yourself after the tag lands.

## The flow

```text
make release-pr VERSION=X.Y.Z
  -> bump [project].version in pyproject.toml
  -> re-lock uv.lock so it agrees with the new version
  -> refresh CHANGELOG.md, promote [Unreleased] to [X.Y.Z] - YYYY-MM-DD
  -> push release/vX.Y.Z and open a PR

review and merge the PR       <- the only human gate

make release-tag VERSION=X.Y.Z
  -> create and push the tag vX.Y.Z
  -> .github/workflows/release.yml builds the distribution and
     creates the GitHub Release
```

## Before you start

Be on an up-to-date, green `main`, with a working tree that has nothing in it, and with
the GitHub CLI authenticated (both scripts shell out to `gh`).

```bash
git switch main
git pull --ff-only origin main
make check
gh auth status
```

Pick the version with [PEP 440](https://peps.python.org/pep-0440/) / semver in mind. Pass
it as `X.Y.Z` with no leading `v`; the `v` prefix belongs to the tag, not to the version
recorded in `pyproject.toml`.

## Step 1: open the release PR

```bash
make release-pr VERSION=X.Y.Z
```

This bumps the version, re-locks, rewrites the changelog, and opens the PR. Two details
are worth knowing because they are the things that break:

- **The version is static and the lockfile knows it.** `pyproject.toml` carries a literal
  `version = '0.0.0'`; there is no version-from-git plugin here. `uv.lock` also records
  the project's own version, and CI runs `uv run --locked`, which _fails_ rather than
  silently re-resolving when the lockfile disagrees with `pyproject.toml`. So the bump and
  the re-lock are one operation, never two: the script uses `uv version "X.Y.Z"` and then
  `uv lock`. A hand-edited (or `sed`-ed) version that skips the re-lock turns the release
  PR red on the first CI run.
- **The changelog entries are commit subjects.** The `## [Unreleased]` section is
  regenerated from git history by [`scripts/update-unreleased.sh`](scripts/update-unreleased.sh)
  before being promoted, so it reads like the commit log. That is what the review in step
  2 is for.

## Step 2: review and merge

Read the diff the way a consumer would. Reword changelog lines that only make sense to
whoever wrote the commit, confirm the version number matches the size of the change, and
check that `pyproject.toml` and `uv.lock` moved together. Merge once CI is green.

Everything up to this point is reversible by closing the PR. The tag in step 3 is not.

## Step 3: tag the release

```bash
git switch main
git pull --ff-only origin main
make release-tag VERSION=X.Y.Z
```

This verifies you are on a clean `main` whose committed version matches `X.Y.Z`, creates
the annotated tag `vX.Y.Z`, and pushes it with:

```bash
git push origin refs/tags/vX.Y.Z
```

That explicit refspec is not a stylistic choice. `git push --follow-tags` pushes _every_
reachable annotated tag that the remote is missing, not just the one you named — so a
stale local tag from an abandoned attempt would ride along and start a release for a
version nobody asked for. Naming the single ref makes the blast radius exactly one tag.

**Do not run `gh release create` afterwards.** The tag push fires
[`.github/workflows/release.yml`](.github/workflows/release.yml), which builds the
distribution and creates the GitHub Release itself. Doing it by hand as well either
double-creates the release or races the workflow into a failure.

Watch it instead:

```bash
gh run watch
gh release view vX.Y.Z
```

## Troubleshooting

### CI fails with a `--locked` / "lockfile is out of date" error

The version bump landed in `pyproject.toml` without a matching `uv.lock`. Fix it on the
release branch:

```bash
uv lock
git commit -am 'chore(release): re-lock after version bump'
```

Do not "fix" this by dropping `--locked` in CI. The flag is what guarantees the release
is built from the dependency set that was reviewed.

### `make release-pr` says there is nothing under `[Unreleased]` to promote

Either nothing has merged since the last release, or [`cliff.toml`](cliff.toml) is
filtering out every recent commit (it drops some conventional-commit types by design).
Check what git-cliff actually sees:

```bash
git cliff --unreleased
```

### git-cliff fails with an HTTP 404

git-cliff enriches entries by calling the GitHub API, which answers 404 for a private
repository when the caller is anonymous.
[`scripts/update-unreleased.sh`](scripts/update-unreleased.sh) resolves a token from
`gh auth token` when the CLI is authenticated; if it is not, supply one explicitly:

```bash
GITHUB_TOKEN=$(gh auth token) make release-pr VERSION=X.Y.Z
```

### The tag already exists

`make release-tag` refuses to overwrite an existing tag, locally or on the remote, which
is the correct behavior: consumers pin tags, and moving a tag out from under them breaks
reproducibility. If the tag was never pushed, delete the local one and retry. If it _was_
pushed, do not move it — cut the next version instead.

The one narrow exception is a tag whose release run failed because of a bug in the
workflow file itself. Actions runs the workflow as it existed at the tagged commit, so
re-running the failed job cannot pick up a fix that landed later on `main`. If you are
certain nothing consumes the tag yet, delete it on both sides and re-tag the fixed
commit; otherwise, release the next version.

### The tag pushed but no release run started

Confirm the tag reached the remote and that the workflow file exists on the tagged
commit:

```bash
git ls-remote --tags origin 'refs/tags/vX.Y.Z'
git show vX.Y.Z:.github/workflows/release.yml >/dev/null && echo present
gh run list --workflow release.yml
```

A tag created before the release workflow was merged has no workflow to trigger; the fix
is to release a later version, not to re-point the tag.
