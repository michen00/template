#!/usr/bin/env -S uv run --script

# /// script
# dependencies = ["nox>=2025.2.9"]
# ///

"""Nox configuration file for CI checks."""

from __future__ import annotations

__all__ = ()

import contextlib
import subprocess
import tempfile
import typing
from pathlib import Path

import nox
from nox.command import CommandFailed

if typing.TYPE_CHECKING:
    from collections.abc import Iterator, Sequence


nox.needs_version = '>=2025.2.9'
nox.options.default_venv_backend = 'uv|venv'

_ANALYSIS_HOOKS = 'ty', 'basedpyright'
"""The hooks that check against the project environment, which `analysis` runs."""


@contextlib.contextmanager
def _export_requirements(groups: Sequence[str] | None = None) -> Iterator[str]:
    """Yield a path to a temporary requirements.txt exported from uv.lock."""
    args = ['uv', 'export', '--format', 'requirements-txt', '--no-hashes']
    if groups:
        for g in groups:
            args += ['--group', g]
    reqs = subprocess.check_output(args, text=True)
    with tempfile.NamedTemporaryFile('w+', delete=False, suffix='.txt') as tmp:
        tmp.write(reqs)
        tmp.flush()
    try:
        yield tmp.name
    finally:
        Path(tmp.name).unlink(missing_ok=True)


@nox.session
def precommit(session: nox.Session) -> None:
    """Run pre-commit hooks."""
    with _export_requirements(groups=('dev',)) as reqs:
        session.install('-r', reqs)
    session.run('pre-commit', 'run', '--all-files')
    session.run(
        'pre-commit', 'run', '--all-files', '--hook-stage', 'pre-push', 'talisman-push'
    )


@nox.session
def analysis(session: nox.Session) -> None:
    """Run the hooks that check against the project environment."""
    # Through pre-commit rather than as bare tool calls, so the hook definitions stay
    # the single source of truth. CI gives them their own job, off the precommit
    # job's critical path, and that job skips them by these ids. Every hook runs even
    # after one fails, as in a full pre-commit run. CI splits the hooks across legs
    # by naming them; with none named, all run. They run at the manual stage, which
    # each hook lists beside the stage it runs at locally.
    hooks = session.posargs or [*_ANALYSIS_HOOKS]
    unknown = sorted({*hooks} - {*_ANALYSIS_HOOKS})
    if unknown:
        session.error(f'not analysis hooks: {", ".join(unknown)}')
    with _export_requirements(groups=('dev',)) as reqs:
        session.install('-r', reqs)
    failed = []
    for hook in hooks:
        try:
            session.run(
                'pre-commit', 'run', '--all-files', '--hook-stage', 'manual', hook
            )
        except CommandFailed:
            failed.append(hook)
    if failed:
        session.error(f'failed: {", ".join(failed)}')


@nox.session
def test(session: nox.Session) -> None:
    """Run pytest with coverage."""
    with _export_requirements(groups=('test',)) as reqs:
        session.install('-r', reqs)
    session.install('.')
    session.run('pytest', '-n', 'auto', '-vv', '--tb=short', '-l', '--durations=10')


if __name__ == '__main__':
    nox.main()
