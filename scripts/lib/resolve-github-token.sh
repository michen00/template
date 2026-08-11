#!/usr/bin/env bash

# Library: resolve-github-token.sh
#
# Provides `resolve_github_token_via_gh`, a best-effort helper that prints a
# GitHub API token to stdout when (and only when) it is safe to do so on
# behalf of git-cliff (or any consumer that needs a github.com token solely
# for repo enrichment).
#
# This file is meant to be sourced, not executed:
#
#   source "${SCRIPT_DIR}/lib/resolve-github-token.sh"
#   token="$(resolve_github_token_via_gh)"
#
# The function never modifies the caller's environment and never aborts the
# caller on internal failures; callers decide how to react to an empty
# result. See `scripts/update-unreleased.sh` for the canonical use site.

# resolve_github_token_via_gh
# ---------------------------
# Print a github.com token captured from `gh auth token --hostname github.com`
# when ALL of the following hold:
#
#   1. `GITHUB_TOKEN` is unset/empty in the current env.
#   2. `GH_TOKEN` is unset/empty in the current env.
#   3. The `gh` CLI is on `$PATH`.
#   4. `gh auth status --hostname github.com` exits 0 (i.e. the CLI is
#      authenticated for github.com specifically).
#
# Otherwise print nothing and exit 0. The first two conditions mean an
# already-provisioned token always wins: in CI, GITHUB_TOKEN is injected by
# the workflow and this helper stays out of the way entirely.
#
# Both probes are pinned to `--hostname github.com` so that unrelated host
# state on multi-host setups (e.g. GHES alongside github.com) does not break
# changelog generation against a github.com repo. Per the gh CLI manual,
# `gh auth status` without `--hostname` exits non-zero if *any* known host
# has auth issues, and `gh auth token` without `--hostname` returns the
# token for the CLI's default host -- which may not be github.com.
#
# The function does not export anything: callers wanting to scope the
# resulting token to a single child invocation should use a one-shot env
# override on that command, e.g.:
#
#   token="$(resolve_github_token_via_gh)"
#   if [[ -n "$token" ]]; then
#     GITHUB_TOKEN="$token" git cliff --unreleased ...
#   else
#     git cliff --unreleased ...
#   fi
#
# This keeps the credential out of the script's process environment and out
# of any subsequent child processes (notably `git commit` and its hooks).
resolve_github_token_via_gh() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -n "${GH_TOKEN:-}" ]]; then
    return 0
  fi
  if ! command -v gh > /dev/null 2>&1; then
    return 0
  fi
  if ! gh auth status --hostname github.com > /dev/null 2>&1; then
    return 0
  fi
  # `|| true` because an empty result is a supported outcome: the caller
  # falls back to an unauthenticated run rather than failing the changelog.
  gh auth token --hostname github.com 2> /dev/null || true
}
