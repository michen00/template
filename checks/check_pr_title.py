"""Check a pull request title against the repository conventions.

Deterministic problems (a bad Conventional Commit form, exceeding the hard length limit
on the title as typed, a trailing period) are errors and exit non-zero. Everything else
is a warning and does not: mood, a capitalized start, the preferred length, plan
identifiers, and the length a squash merge's suffix will push the subject to.

The preferred length is checked here and not in the shared subject helper, because it is
the one rule a title carries that a commit subject does not: a squash merge appends
`" (#123)"` to the title, so a title that fits exactly stops fitting once it lands.

Given a pull request number, that reservation is replaced by the fact. The number is
the pull request's own and cannot change, so the merged length is computed rather than
guessed at. Both are advisory: the hard maximum answers for the title as typed, and the
suffix a squash merge appends is reported so it can be acted on, not enforced. Exactly
one of the two speaks -- the band when there is no number, the projection when there is.

Usage:
    python -m checks.check_pr_title "feat: add config precedence rule"
    PR_TITLE="fix: guard empty body" python -m checks.check_pr_title
    PR_TITLE="fix: guard empty body" PR_NUMBER=64 python -m checks.check_pr_title
"""

from __future__ import annotations

import argparse
import os

from ._common import check_preferred_length, check_squash_subject, check_subject


def _pr_number(explicit: int | None) -> int | None:
    """Return the pull request number, or None when there is not one to use.

    A non-numeric or empty ``PR_NUMBER`` is treated as absent rather than as an error:
    the variable is unset in every local run, and a check that refused to run without
    it would be a check nobody runs before pushing.
    """
    if explicit is not None:
        return explicit
    environment = os.environ.get('PR_NUMBER', '').strip()
    return int(environment) if environment.isdigit() else None


def main(argv: list[str] | None = None) -> int:
    """Validate the title and return a process exit code."""
    parser = argparse.ArgumentParser(description='Check a PR title.')
    parser.add_argument(
        'title',
        nargs='?',
        default=os.environ.get('PR_TITLE'),
        help='the PR title; falls back to the PR_TITLE environment variable',
    )
    parser.add_argument(
        '--pr-number',
        type=int,
        default=None,
        help=(
            'the pull request number, so the squash subject is checked in the form it '
            'will land; falls back to PR_NUMBER. Omit it before the PR exists'
        ),
    )
    args = parser.parse_args(argv)
    if not args.title:
        parser.error('provide a title argument or set PR_TITLE')

    # The title is checked on its own terms first, so a malformed or ill-punctuated one
    # is reported as such rather than being masked by the projection. In particular a
    # trailing period is invisible once the suffix is appended.
    found = check_subject(args.title, label='title')

    # Exactly one length rule speaks. Once the number is known the merged length is a
    # fact, so the reservation would not merely repeat it -- it can contradict it. A
    # 45-character title merging as #6 lands at exactly 50: the projection passes it and
    # the 44-character band calls it over budget. The fact wins, and both advise.
    number = _pr_number(args.pr_number)
    if number is None:
        found.merge(check_preferred_length(args.title, label='title'))
    else:
        found.merge(check_squash_subject(args.title, number))

    return found.emit('title OK')


if __name__ == '__main__':
    raise SystemExit(main())
