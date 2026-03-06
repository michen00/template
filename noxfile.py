"""Nox configuration file for CI checks."""

from __future__ import annotations

__all__ = ()

import subprocess
import tempfile
import typing

import nox

if typing.TYPE_CHECKING:
    from collections.abc import Sequence


nox.options.default_venv_backend = 'uv|venv'


def _export_requirements(groups: Sequence[str] | None = None) -> str:
    """Return a path to a temporary requirements.txt exported from uv.lock."""
    args = ['uv', 'export', '--format', 'requirements-txt', '--no-hashes']
    if groups:
        for g in groups:
            args += ['--group', g]
    reqs = subprocess.check_output(args, text=True)
    with tempfile.NamedTemporaryFile('w+', delete=False, suffix='.txt') as tmp:
        tmp.write(reqs)
        tmp.flush()
    return tmp.name


@nox.session
def precommit(session: nox.Session) -> None:
    """Run pre-commit hooks."""
    session.install('-r', _export_requirements(groups=('dev',)))
    session.run('pre-commit', 'run', '--all-files')


@nox.session
def test(session: nox.Session) -> None:
    """Run pytest."""
    session.install('-r', _export_requirements(groups=('test',)))
    session.run('pytest', '-n', 'auto')
