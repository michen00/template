"""manifest.txt, held to the template's own root files.

manifest.txt decides what a generated project receives, and setup.sh copies nothing
it does not list, without an error. A tool's config file is the costly omission: the
generated project still runs the shipped hook, but without the settings it reads.

This module is not in manifest.txt, because a generated project has no manifest.
"""

from __future__ import annotations

__all__ = ()

import subprocess
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]

# Root files that build or describe the template and are deliberately not copied. A
# generated project gets its README.md, AGENTS.md and CLAUDE.md from the dotted copies,
# which setup.sh renames.
_TEMPLATE_ONLY = frozenset(
    {
        '.template-profile.sh',
        'AGENTS.md',
        'CLAUDE.md',
        'README.md',
        'manifest.txt',
        'setup.sh',
        'test_setup.sh',
    }
)


def _manifest() -> frozenset[str]:
    """Return every path manifest.txt lists."""
    lines = (_ROOT / 'manifest.txt').read_text(encoding='utf-8').splitlines()
    return frozenset(line.strip() for line in lines if line.strip())


def _tracked_root_files() -> frozenset[str]:
    """Return every tracked file at the repository root."""
    listing = subprocess.run(
        ['git', 'ls-files', '-z'],  # noqa: S607 -- `git` from PATH, as checks/ runs it
        capture_output=True,
        text=True,
        check=True,
        cwd=_ROOT,
    )
    return frozenset(
        path for path in listing.stdout.split('\0') if path and '/' not in path
    )


def test_every_root_file_is_shipped_or_template_only() -> None:
    """A root file nobody listed is a root file no generated project receives."""
    unlisted = sorted(_tracked_root_files() - _manifest() - _TEMPLATE_ONLY)

    assert not unlisted, (
        f'these root files are neither in manifest.txt nor template-only: {unlisted}. '
        'Add each to manifest.txt, or to _TEMPLATE_ONLY with the reason it stays here.'
    )


def test_every_template_only_file_still_exists() -> None:
    """An exemption for a deleted file would silently cover a new file of that name."""
    stale = sorted(_TEMPLATE_ONLY - _tracked_root_files())

    assert not stale, f'_TEMPLATE_ONLY names untracked files: {stale}'
