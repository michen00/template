"""Tests for how CI runs the static analysis hooks.

ty, basedpyright and pylint run in CI's analysis job, by the hook ids in noxfile.py's
`_ANALYSIS_HOOKS`, and the precommit job skips them by the same ids. Each test pins
one link in that chain that a rename or a new hook could break without any job
failing: a hook would then run twice, or nowhere.
"""

from __future__ import annotations

__all__ = ()

import ast
from pathlib import Path
from typing import Any

import pytest
import yaml

_ROOT = Path(__file__).resolve().parents[1]


def _ci() -> dict[str, Any]:
    """Return the parsed CI workflow."""
    workflow: dict[str, Any] = yaml.safe_load(
        (_ROOT / '.github' / 'workflows' / 'CI.yml').read_text(encoding='utf-8')
    )
    return workflow


def _analysis_hooks() -> tuple[str, ...]:
    """Return noxfile.py's `_ANALYSIS_HOOKS`, read without importing nox."""
    tree = ast.parse((_ROOT / 'noxfile.py').read_text(encoding='utf-8'))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == '_ANALYSIS_HOOKS'
            for target in node.targets
        ):
            hooks: tuple[str, ...] = ast.literal_eval(node.value)
            return hooks
    pytest.fail('noxfile.py defines no _ANALYSIS_HOOKS')


def _hook_stages() -> dict[str, list[str]]:
    """Return each hook id in the pre-commit config with the stages it runs at."""
    config = yaml.safe_load(
        (_ROOT / '.pre-commit-config.yaml').read_text(encoding='utf-8')
    )
    default = config.get('default_stages', [])
    return {
        hook['id']: hook.get('stages', default)
        for repo in config['repos']
        for hook in repo['hooks']
    }


def test_the_precommit_job_skips_exactly_the_analysis_hooks() -> None:
    """The precommit job skips the hooks the analysis job runs, and no others.

    pre-commit ignores a SKIP entry that names no hook, so a renamed hook would leave
    the old id skipping nothing and the new one running in both jobs, with no failure.
    """
    steps = {step.get('name'): step for step in _ci()['jobs']['precommit']['steps']}
    skipped = steps['Run pre-commit']['env']['SKIP'].split(',')
    assert sorted(skipped) == sorted(_analysis_hooks())
    assert set(skipped) <= set(_hook_stages())


def test_every_analysis_hook_runs_at_the_manual_stage() -> None:
    """CI runs them at the manual stage, whatever stage each runs at locally."""
    stages = _hook_stages()
    for hook in _analysis_hooks():
        assert 'manual' in stages[hook], hook


def test_the_analysis_legs_run_every_analysis_hook_once() -> None:
    """Split across the matrix legs, each analysis hook still runs exactly once."""
    legs = _ci()['jobs']['analysis']['strategy']['matrix']['hooks']
    hooks = [hook for leg in legs for hook in leg.split()]
    assert sorted(hooks) == sorted(_analysis_hooks())


def test_the_required_context_waits_for_every_job() -> None:
    """run-ci needs every other job, so a job left out of it cannot fail the run."""
    jobs = _ci()['jobs']
    assert set(jobs['run-ci']['needs']) == set(jobs) - {'run-ci'}
