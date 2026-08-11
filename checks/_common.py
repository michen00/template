"""Shared validation helpers for the deterministic PR checks.

These helpers embody the repository's governing rule: a tool's action may never be
stronger than its detection is certain. Heuristic or ambiguous problems are therefore
always warnings, which advise but never block. An exact detection is permitted to block
but is not obliged to: `check_squash_subject` measures a length exactly and still only
advises, because the characters that carry the subject over are the platform's rather
than the author's.
"""

from __future__ import annotations

__all__ = (
    'CONVENTIONAL_TYPES',
    'Findings',
    'check_preferred_length',
    'check_squash_subject',
    'check_subject',
    'squash_subject',
)

import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

CONVENTIONAL_TYPES = (
    'feat',
    'fix',
    'docs',
    'style',
    'refactor',
    'perf',
    'test',
    'build',
    'ci',
    'chore',
    'revert',
)

_CONVENTIONAL = re.compile(
    r'^(?:' + '|'.join(CONVENTIONAL_TYPES) + r')'
    r'(?:\([a-z0-9._/-]+\))?!?: (?P<subject>.+)$'
)

_HARD_MAX = 50

# The hard maximum governs every subject. This tighter one governs titles alone, because
# a squash merge appends `" (#123)"` to a title and nothing at all to a commit subject:
# 50 minus that suffix is what a title really has to spend, and 44 leaves a two-digit
# number room. See check_preferred_length for why it is not part of check_subject.
_TITLE_SOFT_MAX = 44

# Common non-imperative first words: third-person and past forms we see most often.
_NON_IMPERATIVE = frozenset(
    {
        'added',
        'adds',
        'fixed',
        'fixes',
        'updated',
        'updates',
        'removed',
        'removes',
        'changed',
        'changes',
        'refactored',
        'renamed',
        'moved',
        'deleted',
        'created',
        'implemented',
        'introduced',
        'bumped',
        'merged',
    }
)

_PLAN_ID = re.compile(r'\b(?:F\d+|S\d+|Phase\s*\d+|Slice\s*\w+)\b')


@dataclass(slots=True)
class Findings:
    """Result of a check: errors block, warnings advise (the action-strength rule)."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def merge(self, other: Findings) -> None:
        """Fold another result into this one."""
        self.errors.extend(other.errors)
        self.warnings.extend(other.warnings)

    @property
    def ok(self) -> bool:
        """Whether nothing blocks, i.e. there are no errors."""
        return not self.errors

    def _publish(self, severity: str, message: str) -> None:
        """Print one finding, as a workflow annotation when running under Actions.

        An annotation reaches the Checks tab and the run summary; a plain stderr
        line reaches only a job log, which nobody opens when the job is green.
        Workflow commands are read from stdout, so the annotation form goes there
        while a local run keeps the stream and the wording it always had.
        """
        if os.environ.get('GITHUB_ACTIONS'):
            print(f'::{severity}::{message}')
        else:
            print(f'{severity}: {message}', file=sys.stderr)

    def _record(self) -> None:
        """Append the warnings to the file named by ``PR_WARNINGS_FILE``, if any.

        Each check step names its own file, so the stem identifies whichever check
        raised what the file holds and the upsert step can group by it without
        Findings ever learning about labels. Absent the variable -- every local
        run -- this does nothing, and a clean check writes no file at all, so the
        comment step never renders a heading with nothing under it.

        Recording is a convenience; the raw job log `_publish` writes to is the
        durable record -- GitHub renders at most ten annotations per level per
        step, so a high-warning check truncates on the Checks tab and the run
        summary while the log keeps every line. So a filesystem problem here --
        a bad permission, a full disk, a path component that already exists as
        a file -- is reported as a warning rather than raised, and never turns
        an otherwise-clean, warnings-only check into a hard failure.
        """
        target = os.environ.get('PR_WARNINGS_FILE', '').strip()
        if not target or not self.warnings:
            return
        path = Path(target)
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('a', encoding='utf-8') as handle:
                handle.writelines(f'{warning}\n' for warning in self.warnings)
        except OSError as error:
            self._publish('warning', f'could not record warnings to {path}: {error}')

    def emit(self, ok_message: str) -> int:
        """Print findings, record warnings via `_record`, and return an exit code.

        The filesystem write is a real side effect a caller reading only this
        docstring should know about, not just the printed and annotated forms.
        """
        publish = self._publish
        for warning in self.warnings:
            publish('warning', warning)
        for error in self.errors:
            publish('error', error)
        self._record()
        if self.ok:
            suffix = ' (with warnings)' if self.warnings else ''
            print(f'{ok_message}{suffix}')
            return 0
        return 1


def _looks_non_imperative(first_word: str) -> bool:
    """Whether the first word reads as non-imperative (past tense or third person)."""
    low = first_word.lower()
    return low in _NON_IMPERATIVE or low.endswith('ing')


def check_subject(subject_line: str, *, label: str = 'subject') -> Findings:
    """Validate one Conventional Commit subject line against the conventions.

    These are the rules that govern every subject, a commit's as much as a title's. The
    tighter preferred length is not among them: it is a title rule, applied separately
    by check_preferred_length.
    """
    found = Findings()
    match = _CONVENTIONAL.match(subject_line)
    if match is None:
        found.errors.append(
            f"{label}: not Conventional Commit form 'type(scope): subject' "
            f'(types: {", ".join(CONVENTIONAL_TYPES)})'
        )
        return found

    subject = match.group('subject')

    # Deterministic and unambiguous -> errors (block).
    if len(subject_line) > _HARD_MAX:
        found.errors.append(
            f'{label}: {len(subject_line)} chars exceeds hard max {_HARD_MAX}'
        )
    if subject_line.endswith('.'):
        found.errors.append(f'{label}: must not end with a period')

    # Heuristic or ambiguous -> warnings (advise).
    first_word = subject.split(' ', 1)[0]
    if first_word[:1].isupper():
        found.warnings.append(
            f"{label}: subject should start lowercase ('{first_word}')"
        )
    if _looks_non_imperative(first_word):
        found.warnings.append(
            f"{label}: subject may not be imperative ('{first_word}')"
        )
    if _PLAN_ID.search(subject):
        found.warnings.append(
            f'{label}: contains a plan identifier; keep it out of the subject'
        )
    return found


def squash_subject(title: str, pr_number: int) -> str:
    """Return the commit subject a squash merge will produce from this title.

    GitHub appends the pull request's *own* number, which is known and immutable from
    the moment the pull request exists -- so this is a projection rather than a guess.
    """
    return f'{title} (#{pr_number})'


def check_squash_subject(
    title: str, pr_number: int, *, label: str = 'title'
) -> Findings:
    """Advise when the subject a squash merge will produce exceeds the hard maximum.

    The hard maximum governs the string an author wrote. The suffix is the
    platform's addition, appended after the title check has already run, so a
    title that fits can still land over -- which is how this repository's own
    default branch came to carry subjects that exceeded a maximum enforced on
    every one of them. Reporting the projection is what closes that gap; blocking
    on it would charge an author for characters they did not type, and make a
    title that passes locally fail in CI for a reason the local run cannot show
    them.

    Advising rather than blocking is consistent with the rule above, which caps
    action strength at detection certainty without compelling a certain finding
    to take the strongest action available. The number is exact, so the
    projection is exact; the choice of what to do about it is separate.
    """
    found = Findings()
    projected = squash_subject(title, pr_number)
    if len(projected) > _HARD_MAX:
        excess = len(projected) - _HARD_MAX
        found.warnings.append(
            f'{label}: {len(title)} chars becomes {len(projected)} as the squash '
            f'subject, over the hard max {_HARD_MAX}; trim {excess}'
        )
    return found


def check_preferred_length(subject_line: str, *, label: str = 'title') -> Findings:
    """Advise when a title leaves no room for the suffix a squash merge will append.

    This is a title rule rather than a subject rule, which is why it sits outside
    check_subject rather than inside it. Every subject answers to the hard maximum; only
    a title is also charged for `" (#123)"`, because only a title becomes the squashed
    commit subject. A commit on the branch never grows a suffix, so holding its subject
    to the reserve would charge it for room it will never need -- which is what happened
    while this band lived in the shared helper, and is the reason it no longer does.

    The band stops at the hard maximum so that an over-long subject is reported once, as
    the error it already is, rather than twice.
    """
    found = Findings()
    if _TITLE_SOFT_MAX < len(subject_line) <= _HARD_MAX:
        found.warnings.append(
            f'{label}: {len(subject_line)} chars over preferred max {_TITLE_SOFT_MAX}'
        )
    return found
