"""Check a pull request title against the repository conventions.

Deterministic problems (a bad Conventional Commit form, exceeding the 50-character
maximum, a trailing period) are errors and exit non-zero. Everything else is a warning
and does not: mood, a capitalized start, and plan identifiers.

Usage:
    python -m checks.check_pr_title "feat: add config precedence rule"
    PR_TITLE="fix: guard empty body" python -m checks.check_pr_title
"""

from __future__ import annotations

import argparse
import os

from ._common import check_subject


def main(argv: list[str] | None = None) -> int:
    """Validate the title and return a process exit code."""
    parser = argparse.ArgumentParser(description='Check a PR title.')
    parser.add_argument(
        'title',
        nargs='?',
        default=os.environ.get('PR_TITLE'),
        help='the PR title; falls back to the PR_TITLE environment variable',
    )
    args = parser.parse_args(argv)
    if not args.title:
        parser.error('provide a title argument or set PR_TITLE')

    found = check_subject(args.title, label='title')
    return found.emit('title OK')


if __name__ == '__main__':
    raise SystemExit(main())
