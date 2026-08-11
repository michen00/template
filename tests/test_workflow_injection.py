"""One invariant, held across every workflow and composite action in the tree.

A value interpolated into a `run:` block becomes part of the script before the shell
ever sees it, so quoting cannot save it. Anything an outside author controls -- a pull
request title, a branch name, a comment body -- has to reach the shell through `env:`
or through a file instead.

This matters more here than in an ordinary repository: the workflows shipped by
`manifest.txt` hold `contents: write` and `pull-requests: write`, and they are copied
into every project created from this one. A hole introduced here propagates.

The tree already satisfies this everywhere, which is the moment worth locking it in:
the test is green on the day it lands, so it can only ever fail on something newly
introduced.
"""

from __future__ import annotations

__all__ = ()

import re
import typing
from pathlib import Path

import pytest
import yaml

if typing.TYPE_CHECKING:
    from collections.abc import Iterator

_ROOT = Path(__file__).resolve().parents[1]
_EXPRESSION = re.compile(r'\$\{\{(.*?)\}\}', re.DOTALL)

# Contexts the runner fills in itself, which no pull request can influence. This is an
# allowlist of expressions rather than of files: a second interpolation in the same
# step still has to be named here, and naming one is a deliberate act with a reason.
_RUNNER_PROVIDED = frozenset({'github.action_path'})


def _definition_files() -> list[Path]:
    """Return every workflow and composite action definition in the tree."""
    # `*.y*ml` rather than `*.yml`: a project derived from this one may reach for the
    # `.yaml` spelling, and a scan that quietly skipped those would still pass.
    workflows = sorted((_ROOT / '.github/workflows').glob('*.y*ml'))
    actions = sorted((_ROOT / '.github/actions').glob('*/action.y*ml'))
    return workflows + actions


def _run_blocks(node: object) -> Iterator[str]:
    """Yield every ``run:`` script anywhere in a parsed definition.

    Walking the parsed document rather than the text covers a workflow's
    ``jobs.*.steps`` and a composite action's ``runs.steps`` without knowing which
    shape it is looking at, and without a regex that a reformat could slip past.
    """
    if isinstance(node, dict):
        for key, value in node.items():
            if key == 'run' and isinstance(value, str):
                yield value
            else:
                yield from _run_blocks(value)
    elif isinstance(node, list):
        for item in node:
            yield from _run_blocks(item)


@pytest.mark.parametrize(
    'path', _definition_files(), ids=lambda path: str(path.relative_to(_ROOT))
)
def test_no_run_block_interpolates_an_outside_value(path: Path) -> None:
    """Untrusted values reach the shell through env or a file, never as script text."""
    document = yaml.safe_load(path.read_text(encoding='utf-8'))
    for script in _run_blocks(document):
        for expression in _EXPRESSION.findall(script):
            assert expression.strip() in _RUNNER_PROVIDED, (
                f'{path.relative_to(_ROOT)} interpolates '
                f'${{{{{expression}}}}} into a run block; pass it through env: instead'
            )


def test_the_scan_covers_every_definition_in_the_tree() -> None:
    """A guard that silently stopped finding files would pass forever."""
    found = {path.relative_to(_ROOT).as_posix() for path in _definition_files()}
    tracked = {
        path
        for path in (_ROOT / '.github').rglob('*.y*ml')
        if path.parent.name == 'workflows' or path.stem == 'action'
    }
    assert found == {path.relative_to(_ROOT).as_posix() for path in tracked}
    # Deliberately not a floor of ten, as the source of this test uses: a project
    # created from this one receives a subset of these definitions, so any specific
    # count would be wrong there. The set equality above is what carries the value;
    # this only catches the scan finding nothing at all.
    assert found


def test_the_allowlist_holds_only_values_a_pull_request_cannot_reach() -> None:
    """github.action_path is the runner's own path to the checked-out action."""
    assert {'github.action_path'} == _RUNNER_PROVIDED
