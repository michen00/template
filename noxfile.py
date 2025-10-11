"""Nox configuration file."""

from __future__ import annotations

__all__ = ()


import logging
import platform
import re
from pathlib import Path
from typing import Literal, cast

import nox
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings

try:
    from yapic import json
except ImportError:
    import json

logger = logging.getLogger(__name__)

nox.options.default_venv_backend = "uv|conda|mamba|micromamba|venv"


class Manifest(BaseModel):
    """Schema for the manifest file."""

    icons: list[Path] = Field(frozen=True)
    plugins: list[Path] = Field(alias="plug-ins", frozen=True)
    scripts: list[Path] = Field(frozen=True)

    @classmethod
    def load_from(cls, path: Path) -> Manifest:
        """Load the manifest file from the given path."""
        return cls(**json.loads(path.read_text()))

    @staticmethod
    def load_manifest(path: Path = Path("Contents/MANIFEST.json")) -> Manifest:
        """Load the manifest file from the given path."""
        return Manifest.load_from(Path(__file__).parent / path)


class Settings(BaseSettings):
    """Settings for the project."""

    MAYA_VERSION: Literal["2024", "2025", "2026"] = "2025"
    """The version of Maya to use"""  # TODO: Implement version selection logic


@nox.session(python=[*PYTHON_VERSION_2_MAYA_VERSION.keys()])
def install(session: nox.Session) -> None:  # noqa: PLR0915
    """Install plugin files in Maya for development."""
    session_python = cast("str", session.python)
    logger.debug("nox session for python %s", session_python)
    # Create devkitBase directory structure
    devkit_base = Path.home() / "devkitBase/plug-ins"
    (icons := devkit_base / "icons").mkdir(exist_ok=True)
    (plugins := devkit_base / "plug-ins").mkdir(exist_ok=True)
    (scripts := devkit_base / "scripts").mkdir(exist_ok=True)
    del devkit_base

    # Load the manifest file
    project_root = Path(__file__).parent
    contents = project_root / "Contents"
    manifest = Manifest.load_manifest()

    # Symlink the files
    def symlink_files(source_dir: Path, items: list[Path], dest_dir: Path) -> None:
        """Symlink items from source_dir to dest_dir."""
        for item in items:
            if (target := dest_dir / item).exists():
                target.unlink()
            source = source_dir / item
            target = dest_dir / item
            if target.exists():
                target.unlink()
            if source.exists():
                target.symlink_to(source)
            else:
                logger.warning(
                    "Source file does not exist, skipping symlink: %s", source
                )

    symlink_files(contents / "icons", manifest.icons, icons)
    symlink_files(contents / "plug-ins", manifest.plugins, plugins)
    symlink_files(contents / "scripts", manifest.scripts, scripts)
    del symlink_files

    # Set the Maya environment variables
    env = {
        "MAYA_PLUG_IN_PATH": plugins.as_posix(),
        "MAYA_SCRIPT_PATH": scripts.as_posix(),
        "XBMLANGPATH": icons.as_posix(),
    }
    env_dir = "maya"
    if (os_ := platform.system()) == "Darwin":
        env_dir = f"Library/Preferences/Autodesk/{env_dir}"
    elif os_ == "Windows":
        env_dir = f"Documents/{env_dir}"
    maya_year = PYTHON_VERSION_2_MAYA_VERSION[session_python]
    env_dir = Path.home() / env_dir / maya_year
    (env_dir / "Maya.env").write_text(
        "\n".join(f"{k}={v}" for k, v in env.items()) + "\n"
    )

    # Add the site-packages directory to userSetup.py
    user_setup_file = env_dir / "scripts/userSetup.py"
    user_setup_file.touch(exist_ok=True)
    # Compute site-packages for the per-Maya venv (e.g., .venv-maya2025)
    py_minor = session_python.split(".")[1]
    maya_venv = project_root / f".venv-maya{maya_year}"
    site_packages = maya_venv / f"lib/python3.{py_minor}/site-packages"

    def _ensure_addsitedir(path_to_add: Path) -> None:
        """Deduplicate any existing addsitedir lines and then add ours."""
        sp = path_to_add.as_posix()
        pattern = re.compile(
            r"(?m)^(?:(?:site|__import__\s*\(\s*[\'\"]site[\'\"]\s*\))\s*\.\s*)?addsitedir"
            rf"\s*\(\s*[\'\"]{re.escape(sp)}[\'\"]\s*\)\s*"
            r"[;\s]*(?:#.*)?$"
        )
        content = user_setup_file.read_text()
        content = pattern.sub("", content)
        user_setup_file.write_text(
            f'{content}\n__import__("site").addsitedir("{sp}")\n'
        )

    _ensure_addsitedir(site_packages)
    _ensure_addsitedir(project_root / "src")

    # Ensure maya.cmds import is present for shelf-mode startup convenience
    content = user_setup_file.read_text()
    maya_cmds_pattern = re.compile(
        r"(?m)^(?!\s*#)\s*from\s+maya\s+import\s+cmds\s*(?:#.*)?$"
    )
    if maya_cmds_pattern.search(content) is None:
        user_setup_file.write_text(f"{content}\nfrom maya import cmds\n")
    file_arg = user_setup_file.as_posix()
    session.run("ruff", "format", file_arg, external=True)
    session.run(
        "ruff", "check", file_arg, "--fix", "--exit-zero", "--silent", external=True
    )


@nox.session
def uninstall(session: nox.Session) -> None:
    """Remove plugin files from Maya devkitBase directory."""
    # TODO: clean up other artifacts
    # TODO: clean up userSetup.py
    devkit_base = Path.home() / "devkitBase"

    def unlink_files(
        items: list[Path], dest_dir: Literal["icons", "plug-ins", "scripts"]
    ) -> None:
        """Unlink items from dest_dir."""
        dest = devkit_base / dest_dir
        for item in items:
            (dest / item).unlink(missing_ok=True)

    manifest = Manifest.load_manifest()
    unlink_files(manifest.icons, "icons")
    unlink_files(manifest.plugins, "plug-ins")
    unlink_files(manifest.scripts, "scripts")

    del session


# TODO: FIXME
@nox.session
def docs(session: nox.Session) -> None:
    """Build the docs.

    Pass --non-interactive to avoid serving. The first positional argument is the target
    directory.
    """
    import argparse  # noqa: PLC0415

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-b", dest="builder", default="html", help="Build target (default: html)"
    )
    parser.add_argument("output", nargs="?", help="Output directory")
    args, posargs = parser.parse_known_args(session.posargs)

    session.run("uv", "pip", "install", ".[docs]")
    session.install("sphinx-autobuild")
    session.run(
        *(
            ("sphinx-autobuild", "--open-browser")
            if args.builder == "html" and session.interactive
            else ("sphinx-build", "--keep-going")
        ),
        "-n",  # nitpicky mode
        "-T",  # full tracebacks
        f"-b={args.builder}",
        "docs",
        args.output or f"docs/_build/{args.builder}",
        *posargs,
    )
