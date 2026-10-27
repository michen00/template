"""Contract tests for the script that approves runs held at the bot gate.

pr-catchup.yml sources `.github/scripts/approve-bot-gated-runs.sh` to approve the
pull_request runs its own merge commits cause. The script is a privileged step:
it approves workflow runs with the job's token. These tests hold its predicate to
exactly those runs, and its exit status to whether any of them is still held.
"""

__all__ = ()

import os
import subprocess
from pathlib import Path
from textwrap import dedent

_SCRIPT_PATH = (
    Path(__file__).resolve().parents[1] / '.github/scripts/approve-bot-gated-runs.sh'
)
_SCRIPT = _SCRIPT_PATH.read_text(encoding='utf-8')
_REPO = 'michen00/template'


def _extract_shell_function(name: str) -> str:
    """Return one top-level shell function from the script."""
    start = _SCRIPT.index(f'{name}() {{')
    end = _SCRIPT.index('\n}\n', start) + len('\n}')
    return _SCRIPT[start:end]


def test_the_predicate_admits_only_bot_runs_at_the_caused_sha() -> None:
    """The predicate admits only bot pull_request runs held at the caused SHA."""
    guard = _extract_shell_function('approvable')
    repo = _REPO
    caused = 'a' * 40
    unrelated = 'b' * 40
    bot = 'github-actions[bot]'

    def case(**overrides: str) -> tuple[str, ...]:
        """One argument list for the guard: the approvable baseline, spoiled.

        The defaults are the case that must approve, so each call names only
        the field it breaks and the difference is visible instead of buried in
        seven near-identical arguments.

        Returns:
            The values in insertion order, because the shell function takes them
            positionally.
        """
        fields = {
            'run_sha': caused,
            'caused_sha': caused,
            'run_repo': repo,
            'this_repo': repo,
            'run_event': 'pull_request',
            'run_actor': bot,
            'run_gate': 'action_required',
        }
        fields.update(overrides)
        return tuple(fields.values())

    cases = [
        case(),
        case(run_sha=unrelated),
        case(caused_sha=''),
        case(run_sha='', caused_sha=''),
        case(run_repo='outsider/template'),
        case(this_repo=''),
        case(run_repo='', this_repo=''),
        case(run_event='pull_request_target'),
        case(run_actor='michen00'),
        case(run_gate='completed'),
    ]
    calls = '\n'.join(
        'check ' + ' '.join(f'"{field}"' for field in one) for one in cases
    )
    script = (
        'set -uo pipefail\n'
        f'{guard}\n'
        'check() { if approvable "$@"; then echo approve; else echo skip; fi; }\n'
        f'{calls}\n'
    )

    result = subprocess.run(
        ['bash', '-c', script],
        check=True,
        capture_output=True,
        text=True,
    )

    assert result.stdout.splitlines() == ['approve'] + ['skip'] * 9


def test_the_timing_signature_is_documented_beside_the_gate_reader() -> None:
    """The script says why equal timestamps do not identify a held run."""
    prose = ' '.join(
        ' '.join(
            line.lstrip().lstrip('#').strip()
            for line in _SCRIPT.splitlines()
            if line.lstrip().startswith('#')
        ).split()
    )

    assert 'created_at' in prose
    assert 'run_started_at' in prose
    assert 'only after approval' in prose
    assert 'conclusion' in prose


def _fake_gh(tmp_path: Path) -> Path:
    """A directory holding a fake `gh`, ready to prepend to `PATH`.

    The subject under test is a shell script, so its stand-in has to be a real
    executable rather than an object. It answers from `FAKE_*` environment
    variables, which is what lets each test vary the responses without
    rewriting the stub, and it exits non-zero on a call it was not taught, so an
    unstubbed request fails loudly rather than looking like an empty result.

    Returns:
        The directory holding the stub.
    """
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir(exist_ok=True)
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent("""\
            #!/usr/bin/env python3
            import os
            import sys

            args = sys.argv[1:]
            url = next((arg for arg in args if arg.startswith("repos/")), "")
            jq = args[args.index("--jq") + 1] if "--jq" in args else ""

            if url.endswith("/approve"):
                print("{}")
                raise SystemExit(0)
            if "/actions/runs?" in url:
                if "status=action_required" in url:
                    if jq == ".total_count":
                        print(os.environ["FAKE_GATED_COUNT"])
                    else:
                        sys.stdout.write(os.environ["FAKE_GATED_TSV"])
                elif "event=pull_request" in url:
                    print(os.environ["FAKE_PR_RUNS"])
                else:
                    print(os.environ["FAKE_ALL_RUNS"])
                raise SystemExit(0)
            raise SystemExit(f"fake gh: unexpected call: {args}")
            """),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir


def _run_approve_for_sha(  # noqa: PLR0913 -- one keyword per API answer the stub gives
    tmp_path: Path,
    *,
    pr_runs: str,
    gated_count: str,
    gated_tsv: str,
    all_runs: str = '0',
    pr_number: str = '12',
    main: str = '1',
) -> subprocess.CompletedProcess[str]:
    """Run the approval function under bash, with `gh` and the backoff faked.

    `sleep` is stubbed to a no-op so the script's retry pauses cost the suite
    nothing, and the keyword arguments become the `FAKE_*` responses the stub
    reads back.

    Returns:
        The finished process, not asserted on here, so each caller stays specific
        about the exit status and output it cares about.
    """
    out_file = tmp_path / 'gated.txt'
    sha = 'e' * 40
    script = (
        f'sleep() {{ :; }}\n'
        f"source '{_SCRIPT_PATH}'\n"
        f"APPROVE_BOT_GATED_OUT='{out_file}'\n"
        f"APPROVE_BOT_GATED_MAIN='{main}'\n"
        f'approve_bot_gated_runs_for_sha \'{sha}\' "$PR_NUMBER" || exit $?\n'
    )
    return subprocess.run(
        ['bash', '-c', script],
        env={
            **os.environ,
            'PATH': f'{_fake_gh(tmp_path)}{os.pathsep}{os.environ["PATH"]}',
            'REPO': _REPO,
            'PR_NUMBER': pr_number,
            'FAKE_PR_RUNS': pr_runs,
            'FAKE_ALL_RUNS': all_runs,
            'FAKE_GATED_COUNT': gated_count,
            'FAKE_GATED_TSV': gated_tsv,
        },
        capture_output=True,
        text=True,
        check=False,
    )


def test_a_run_still_held_after_approval_fails_the_script(tmp_path: Path) -> None:
    """A run still held after the approval pass fails the script, which names it."""
    repo = _REPO
    caused = 'e' * 40
    tsv = f'111\t{caused}\t{repo}\tpull_request\tgithub-actions[bot]\taction_required\n'
    held = _run_approve_for_sha(tmp_path, pr_runs='4', gated_count='1', gated_tsv=tsv)
    output = held.stdout + held.stderr

    assert held.returncode != 0
    assert '111' in output
    assert (
        'gh api --method POST '
        'repos/michen00/template/actions/runs/111/approve' in output
    )


def test_a_head_with_no_pull_request_run_fails_the_script(tmp_path: Path) -> None:
    """A head with no pull_request run fails, because its checks never report."""
    empty = _run_approve_for_sha(
        tmp_path, pr_runs='0', all_runs='2', gated_count='0', gated_tsv=''
    )
    output = empty.stdout + empty.stderr

    assert empty.returncode != 0
    assert '12' in output
    assert 'e' * 40 in output


def test_runs_that_are_not_held_leave_the_script_green(
    tmp_path: Path,
) -> None:
    """Runs that exist and are not held need no approval, and the script passes."""
    clear = _run_approve_for_sha(tmp_path, pr_runs='4', gated_count='0', gated_tsv='')

    assert clear.returncode == 0


def _second_run_stub(tmp_path: Path, first_id: str, second_id: str) -> Path:
    """A stub `gh` where a second gated run appears only after the first sweep.

    More than one workflow can answer the `synchronize` event a catch-up
    produces, so a run gated by a second workflow can appear after the first
    one has already been swept and approved. Approving `first_id` here is what
    makes it disappear from every gated listing after; `second_id` appears
    from the very next listing onward, and disappears the same way once it is
    itself approved -- so a sweep that only lists once can approve the first
    run and never see the second.

    Returns:
        The directory holding the stub.
    """
    repo = _REPO
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir(exist_ok=True)
    approved = tmp_path / 'approved-ids.txt'
    approved.write_text('', encoding='utf-8')
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent(f"""\
            #!/usr/bin/env python3
            import os
            import sys
            from pathlib import Path

            args = sys.argv[1:]
            url = next((arg for arg in args if arg.startswith("repos/")), "")
            jq = args[args.index("--jq") + 1] if "--jq" in args else ""
            approved = Path({str(approved)!r})
            state = Path({str(tmp_path)!r}) / "gated-calls"

            if url.endswith("/approve"):
                run_id = url.rsplit("/", 2)[1]
                with approved.open("a") as handle:
                    handle.write(run_id + "\\n")
                print("{{}}")
                raise SystemExit(0)
            if "/actions/runs?" in url and "event=pull_request" in url:
                print(os.environ["FAKE_PR_RUNS"])
                raise SystemExit(0)
            if "/actions/runs?" in url and "status=action_required" in url:
                seen = int(state.read_text()) if state.exists() else 0
                state.write_text(str(seen + 1))
                already = approved.read_text().split()
                gated = ["{first_id}"] if seen == 0 else ["{second_id}"]
                gated = [run for run in gated if run not in already]
                if jq == ".total_count":
                    print(len(gated))
                else:
                    for run in gated:
                        fields = [
                            run, "e" * 40, "{repo}", "pull_request",
                            "github-actions[bot]", "action_required",
                        ]
                        print("\\t".join(fields))
                raise SystemExit(0)
            raise SystemExit(f"fake gh: unexpected call: {{args}}")
            """),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir


def test_a_run_gated_after_the_first_sweep_is_still_approved(tmp_path: Path) -> None:
    """A run that a second workflow holds after the first pass is approved too.

    The count-only poll that follows a single approval pass would see this
    second run and wait for it to clear, but nothing would ever approve it --
    it only becomes visible after the moment the approval loop already ran.
    """
    out_file = tmp_path / 'gated.txt'
    sha = 'e' * 40
    script = (
        'sleep() { :; }\n'
        f"source '{_SCRIPT_PATH}'\n"
        f"APPROVE_BOT_GATED_OUT='{out_file}'\n"
        "APPROVE_BOT_GATED_MAIN='1'\n"
        f"approve_bot_gated_runs_for_sha '{sha}' 12 || exit $?\n"
    )

    result = subprocess.run(
        ['bash', '-c', script],
        env={
            **os.environ,
            'PATH': f'{_second_run_stub(tmp_path, "111", "222")}{os.pathsep}'
            f'{os.environ["PATH"]}',
            'REPO': _REPO,
            'FAKE_PR_RUNS': '2',
        },
        capture_output=True,
        text=True,
        check=False,
    )
    output = result.stdout + result.stderr

    assert 'approved run 111' in output
    assert 'approved run 222' in output
    assert result.returncode == 0


def _lagging_gate_stub(
    tmp_path: Path, run_id: str, lag_polls: int
) -> tuple[Path, Path]:
    """A stub `gh` where an approved run keeps reading `action_required` a while.

    Real approvals do not clear instantly: the Actions API can still report a
    just-approved run as `action_required` for a poll or two after the approve
    call succeeds. `lag_polls` is how many polls (listing and count alike)
    keep reporting `run_id` as gated before it clears for good, independent of
    whether anything approved it in between.

    Returns:
        The directory holding the stub, and the file it records approve calls in.
    """
    repo = _REPO
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir(exist_ok=True)
    approve_calls = tmp_path / 'approve-calls.txt'
    approve_calls.write_text('', encoding='utf-8')
    state = tmp_path / 'poll-count.txt'
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent(f"""\
            #!/usr/bin/env python3
            import os
            import sys
            from pathlib import Path

            args = sys.argv[1:]
            url = next((arg for arg in args if arg.startswith("repos/")), "")
            jq = args[args.index("--jq") + 1] if "--jq" in args else ""
            approve_calls = Path({str(approve_calls)!r})
            state = Path({str(state)!r})

            if url.endswith("/approve"):
                with approve_calls.open("a") as handle:
                    handle.write("1\\n")
                print("{{}}")
                raise SystemExit(0)
            if "/actions/runs?" in url and "event=pull_request" in url:
                print(os.environ["FAKE_PR_RUNS"])
                raise SystemExit(0)
            if "/actions/runs?" in url and "status=action_required" in url:
                polls = int(state.read_text()) if state.exists() else 0
                if jq != ".total_count":
                    polls += 1
                    state.write_text(str(polls))
                lagging = polls <= {lag_polls}
                if jq == ".total_count":
                    print(1 if lagging else 0)
                elif lagging:
                    fields = [
                        "{run_id}", "e" * 40, "{repo}", "pull_request",
                        "github-actions[bot]", "action_required",
                    ]
                    print("\\t".join(fields))
                raise SystemExit(0)
            raise SystemExit(f"fake gh: unexpected call: {{args}}")
            """),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir, approve_calls


def test_a_still_gated_run_after_approval_is_not_reapproved(tmp_path: Path) -> None:
    """A run that still reads as held just after approval is approved once only.

    A held run can keep reporting `action_required` for a moment after it is
    approved, and the sweep polls every three seconds regardless of that lag.
    A run's id must be recorded the moment this pass approves it, not only
    when it is left for a human or fails to approve -- otherwise the next
    poll finds the same run still gated, approves it a second time, and
    prints "approved run ..." a second time for one actual approval.
    """
    run_id = '111'
    stub_dir, approve_calls = _lagging_gate_stub(tmp_path, run_id, lag_polls=2)
    out_file = tmp_path / 'gated.txt'
    sha = 'e' * 40
    script = (
        'sleep() { :; }\n'
        f"source '{_SCRIPT_PATH}'\n"
        f"APPROVE_BOT_GATED_OUT='{out_file}'\n"
        "APPROVE_BOT_GATED_MAIN='1'\n"
        f"approve_bot_gated_runs_for_sha '{sha}' 12 || exit $?\n"
    )

    result = subprocess.run(
        ['bash', '-c', script],
        env={
            **os.environ,
            'PATH': f'{stub_dir}{os.pathsep}{os.environ["PATH"]}',
            'REPO': _REPO,
            'FAKE_PR_RUNS': '2',
        },
        capture_output=True,
        text=True,
        check=False,
    )
    output = result.stdout + result.stderr

    assert output.count(f'approved run {run_id}') == 1
    assert approve_calls.read_text(encoding='utf-8').split() == ['1']
    assert result.returncode == 0


def test_the_sourced_helper_leaves_nothing_behind_in_the_caller(tmp_path: Path) -> None:
    """Calling the helpers adds no variable to the scope that sourced them.

    The workflow sources this file straight into a step body, so an assignment
    made without `local` inside one of its functions is a variable in that
    step. `approvable` takes seven positional operands and the approval helper
    keeps a counter; either landing in the caller is a step-level variable
    nobody declared -- silent until it collides with the caller's own.
    """
    repo = _REPO
    probe = '\n'.join(
        [
            'set +u',
            'before=; after=',
            f"source '{_SCRIPT_PATH}'",
            'set +eu',
            'before="$(compgen -v | sort)"',
            (
                'approvable "$(printf a%.0s {1..40})" "$(printf a%.0s {1..40})" '
                f'"{repo}" "{repo}" pull_request "github-actions[bot]" action_required '
                '|| true'
            ),
            'approve_bot_gated_runs_for_sha "$(printf c%.0s {1..40})" 31 || true',
            'after="$(compgen -v | sort)"',
            'comm -13 <(printf "%s\\n" "$before") <(printf "%s\\n" "$after")',
        ]
    )

    result = subprocess.run(
        ['bash', '-c', 'sleep() { :; }\n' + probe],
        env={
            **os.environ,
            'PATH': f'{_fake_gh(tmp_path)}{os.pathsep}{os.environ["PATH"]}',
            'APPROVE_BOT_GATED_OUT': str(tmp_path / 'gated.txt'),
            'REPO': repo,
            'FAKE_PR_RUNS': '2',
            'FAKE_ALL_RUNS': '2',
            'FAKE_GATED_COUNT': '0',
            'FAKE_GATED_TSV': '',
        },
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.stdout.split() == []
