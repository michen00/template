"""Contract tests for the step that disarms bot auto-merge.

bot-automerge.yml arms auto-merge on an eligible bot pull request, and its last step
turns auto-merge off again whenever a run does not vouch for the head. Each test reads
that step from the workflow, or runs its shell body against a stub `gh`, and pins one
property that a later edit could remove without anything else going red.
"""

__all__ = ()

import os
import subprocess
from pathlib import Path
from textwrap import dedent

import yaml

_WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/bot-automerge.yml'
_DISARM = yaml.safe_load(_WORKFLOW.read_text(encoding='utf-8'))['jobs'][
    'bot-automerge'
]['steps'][-1]


def test_the_last_step_disarms_whenever_this_run_did_not_vouch_for_the_head() -> None:
    """The step runs on `always()`, and its condition names no event or eligibility.

    `always()` makes a run that failed or was canceled before its verdict disarm too.
    With no event named, a run for a label change or a reopen disarms as well, since
    such a run can cancel the run for a push. With no eligibility named, a held update
    that a person armed by hand stays armed. The token is the one arming uses.
    """
    condition = ' '.join(_DISARM['if'].split())

    assert _DISARM['name'] == 'Disarm auto-merge unless this run vouched for the head'
    assert condition == "always() && steps.provenance.outputs.trusted != 'true'"
    assert _DISARM['env']['GH_TOKEN'] == (
        '${{ steps.app-token.outputs.token || github.token }}'  # noqa: S105 -- no secret
    )


def _stub_gh(tmp_path: Path) -> Path:
    """Write a stub `gh` that answers the two calls the step makes.

    The file `armed` holds the pull request's auto-merge state, which a disable that
    succeeds turns off. `read_failures` and `disable_failures` count how many of those
    calls fail first, as a transient fault would. Each answered call is logged to
    `calls`.

    Returns:
        The directory holding the stub.
    """
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir()
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent('''\
            #!/usr/bin/env python3
            """Answer only the calls the disarm step makes; reject the rest."""
            import os
            import sys
            from pathlib import Path

            state = Path(os.environ["FAKE_STATE"])
            args = sys.argv[1:]
            pr = os.environ["PR_NUMBER"]
            view = ["pr", "view", pr, "--json", "autoMergeRequest",
                    "--jq", ".autoMergeRequest != null"]
            disable = ["pr", "merge", "--disable-auto", pr]


            def fails(budget_name):
                budget = state / budget_name
                left = int(budget.read_text(encoding="utf-8"))
                budget.write_text(str(max(left - 1, 0)), encoding="utf-8")
                return left > 0


            if args == view:
                call = "view"
            elif args == disable:
                call = "disable"
            else:
                raise SystemExit(f"fake gh: unexpected call: {args}")
            with (state / "calls").open("a", encoding="utf-8") as log:
                log.write(call + "\\n")
            if call == "view":
                if fails("read_failures"):
                    raise SystemExit("HTTP 502")
                print((state / "armed").read_text(encoding="utf-8"))
            else:
                if fails("disable_failures"):
                    raise SystemExit("HTTP 502")
                (state / "armed").write_text("false", encoding="utf-8")
            '''),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir


def _run_disarm(
    tmp_path: Path, *, armed: bool, read_failures: int = 0, disable_failures: int = 0
) -> tuple[subprocess.CompletedProcess[str], list[str], str]:
    """Run the real step against the stub, with its wait between attempts collapsed.

    Returns:
        The finished step, the calls it made in order, and the auto-merge state left.
    """
    (tmp_path / 'armed').write_text(str(armed).lower(), encoding='utf-8')
    (tmp_path / 'read_failures').write_text(str(read_failures), encoding='utf-8')
    (tmp_path / 'disable_failures').write_text(str(disable_failures), encoding='utf-8')
    (tmp_path / 'calls').write_text('', encoding='utf-8')
    result = subprocess.run(  # noqa: S603 -- the workflow's own step, run as written
        ['bash', '-c', f'sleep() {{ :; }}\n{_DISARM["run"]}'],  # noqa: S607 -- PATH
        env={
            **os.environ,
            'PATH': f'{_stub_gh(tmp_path)}{os.pathsep}{os.environ["PATH"]}',
            'FAKE_STATE': str(tmp_path),
            'GH_REPO': 'michen00/template',
            'PR_NUMBER': '7',
        },
        capture_output=True,
        text=True,
        check=False,
    )
    calls = (tmp_path / 'calls').read_text(encoding='utf-8').split()
    return result, calls, (tmp_path / 'armed').read_text(encoding='utf-8')


def test_a_pull_request_that_is_not_armed_is_only_read(tmp_path: Path) -> None:
    """Nothing is disabled, and nothing is reported, when auto-merge is already off."""
    result, calls, _ = _run_disarm(tmp_path, armed=False)

    assert result.returncode == 0, result.stderr
    assert calls == ['view']
    assert '::warning::' not in result.stdout


def test_an_armed_pull_request_is_disarmed_and_read_back(tmp_path: Path) -> None:
    """The step succeeds only once a read after the disable finds auto-merge off."""
    result, calls, armed = _run_disarm(tmp_path, armed=True)

    assert result.returncode == 0, result.stderr
    assert calls == ['view', 'disable', 'view']
    assert armed == 'false'
    assert '::warning::auto-merge disarmed' in result.stdout


def test_a_read_that_fails_is_treated_as_armed(tmp_path: Path) -> None:
    """A transient fault on the read leads to a disable, not to an armed head.

    Read under `set -e`, a failed query would end the step before the disable, leaving
    the earlier arm on a head no run vouched for.
    """
    result, calls, armed = _run_disarm(tmp_path, armed=True, read_failures=1)

    assert result.returncode == 0, result.stderr
    assert calls == ['view', 'disable', 'view']
    assert armed == 'false'


def test_a_disable_that_fails_is_tried_again(tmp_path: Path) -> None:
    """One refused disable is followed by another, and a read that confirms it."""
    result, calls, armed = _run_disarm(tmp_path, armed=True, disable_failures=1)

    assert result.returncode == 0, result.stderr
    assert calls == ['view', 'disable', 'view', 'disable', 'view']
    assert armed == 'false'


def test_auto_merge_that_stays_armed_fails_the_step(tmp_path: Path) -> None:
    """After three refused disables the step fails rather than leave an arm silently."""
    result, calls, armed = _run_disarm(tmp_path, armed=True, disable_failures=99)

    assert result.returncode == 1
    assert calls.count('disable') == 3
    assert armed == 'true'
    assert '::error::could not confirm auto-merge is off' in result.stdout
