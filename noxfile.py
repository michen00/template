"""Nox configuration file for CI checks."""

from __future__ import annotations

__all__ = ()

import contextlib
import subprocess
import tempfile
import typing
from pathlib import Path

import nox

if typing.TYPE_CHECKING:
    from collections.abc import Iterator, Sequence


nox.options.default_venv_backend = 'uv|venv'


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
        Path(tmp.name).unlink()


@nox.session
def precommit(session: nox.Session) -> None:
    """Run pre-commit hooks."""
    with _export_requirements(groups=('dev',)) as reqs:
        session.install('-r', reqs)
    session.run('pre-commit', 'run', '--all-files')
    session.run('pre-commit', 'run', '--all-files', '--hook-stage', 'pre-push', 'mypy')
    session.run(
        'pre-commit', 'run', '--all-files', '--hook-stage', 'pre-push', 'talisman-push'
    )


@nox.session
def test(session: nox.Session) -> None:
    """Run pytest with coverage."""
    with _export_requirements(groups=('test',)) as reqs:
        session.install('-r', reqs)
    session.install('.')
    session.run('pytest', '-n', 'auto', '-vv', '--tb=short', '-l', '--durations=10')
