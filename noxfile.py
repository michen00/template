"""Nox configuration file for CI checks."""

from __future__ import annotations

__all__ = ()


import subprocess
import tempfile

import nox

nox.options.default_venv_backend = "uv|venv"


def _export_requirements(groups: list[str] | None = None) -> str:
    """Return a path to a temporary requirements.txt exported from uv.lock."""
    args = ["uv", "export", "--format", "requirements-txt", "--no-hashes"]
    if groups:
        for g in groups:
            args += ["--group", g]
    reqs = subprocess.check_output(args, text=True)
    with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".txt") as tmp:
        tmp.write(reqs)
        tmp.flush()
    return tmp.name


@nox.session
def precommit(session: nox.Session) -> None:
    """Run pre-commit hooks."""
    req = _export_requirements(groups=["dev"])
    session.install("-r", req)
    session.run("pre-commit", "run", "--all-files")


@nox.session
def test(session: nox.Session) -> None:
    """Run pytest."""
    req = _export_requirements(groups=["test"])
    session.install("-r", req)
    session.run("pytest", "-n", "auto")
