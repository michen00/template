"""Contract tests for the write-capable PR catch-up workflow.

pr-catchup.yml merges main into every open, same-repository, conflict-free pull
request that has fallen behind, then approves the pull_request runs its own merge
commits cause and fails if any of them stays held. Each test runs one step's shell
body against a stub `gh`, or reads one property of the workflow definition that a
later edit could remove without anything else going red. The approval script it
sources has its own tests in test_approve_bot_gated_runs.py.
"""

__all__ = ()

import os
import re
import subprocess
from pathlib import Path
from textwrap import dedent

from checks._common import check_subject

_REPO = 'michen00/template'
_WORKFLOW = (
    Path(__file__).resolve().parents[1] / '.github/workflows/pr-catchup.yml'
).read_text(encoding='utf-8')


def _strip_comments(text: str) -> str:
    """Return only the YAML directives, dropping whole-line comments.

    The header comment names the approval gate it works around, so an absence
    assertion over the directives has to read them without the prose.
    """
    return '\n'.join(
        line for line in text.splitlines() if not line.lstrip().startswith('#')
    )


_DIRECTIVES = _strip_comments(_WORKFLOW)


def _extract_step_run(name: str) -> str:
    """Return the dedented shell body for a named workflow step."""
    step_start = _WORKFLOW.index(f'      - name: {name}\n')
    body_start = _WORKFLOW.index('        run: |\n', step_start) + len(
        '        run: |\n'
    )
    body_end = _WORKFLOW.find('\n      - name:', body_start)
    if body_end == -1:
        body_end = len(_WORKFLOW)
    return dedent(_WORKFLOW[body_start:body_end])


def _extract_step(name: str) -> str:
    """Return the directives of one named workflow step, whole-line comments dropped."""
    start = _WORKFLOW.index(f'      - name: {name}\n')
    end = _WORKFLOW.find('\n      - name:', start + 1)
    block = _WORKFLOW[start:] if end == -1 else _WORKFLOW[start:end]
    return _strip_comments(block)


def _header_prose() -> str:
    """Return the header comment as one whitespace-normalized line.

    Asserting on the raw text would let a claim slip back in simply by rewrapping
    it across two comment lines, so flatten the prose before reading it.
    """
    comments = [
        line.lstrip().lstrip('#').strip()
        for line in _WORKFLOW.splitlines()
        if line.lstrip().startswith('#')
    ]
    return ' '.join(' '.join(comments).split())


def _granted_permissions() -> dict[str, str]:
    """Return the workflow's single top-level permissions map."""
    lines = _DIRECTIVES.splitlines()
    scopes: dict[str, str] = {}
    for line in lines[lines.index('permissions:') + 1 :]:
        if not line.startswith('  '):
            break
        scope, _, access = line.strip().partition(':')
        scopes[scope] = access.strip()
    return scopes


def test_permissions_cover_approval_and_stay_least_privilege() -> None:
    """Approving a gated run needs actions: write, and nothing wider is granted."""
    assert _DIRECTIVES.count('permissions:') == 1
    assert _granted_permissions() == {
        'actions': 'write',
        'contents': 'write',
        'pull-requests': 'write',
    }


def test_the_approval_script_is_checked_out_before_it_is_sourced() -> None:
    """The approval script is on disk before the step that sources it runs."""
    approve = _WORKFLOW.index('      - name: Approve the runs this catch-up caused\n')
    checkout = _WORKFLOW.rindex(
        '      - name: Check out the approval script\n', 0, approve
    )
    assert checkout < approve
    block = _WORKFLOW[checkout:approve]
    assert 'actions/checkout@v7' in block
    assert '.github/scripts/approve-bot-gated-runs.sh' in block
    assert '.github/scripts/approve-bot-gated-runs.sh' in _extract_step_run(
        'Approve the runs this catch-up caused'
    )


def test_only_same_repository_conflict_free_prs_are_updated() -> None:
    """A fork-backed or conflicting PR never reaches the merge call."""
    update = _extract_step_run('Update behind PR branches')
    assert '.isCrossRepository == false' in update
    assert '.mergeable != "CONFLICTING"' in update


def test_the_listing_reaches_every_open_pr() -> None:
    """The listing is not capped at a page, so no candidate is silently skipped.

    `gh pr list` truncates to `--limit` rather than paging past it, and says
    nothing when it does. A cap at or near the open-PR count would leave the
    tail of the list behind indefinitely while the run reports success -- the
    same silent staleness as a refused update, reached by never considering
    the PR at all. The bound is what this asserts; the exact number is not
    load-bearing.
    """
    update = _extract_step_run('Update behind PR branches')
    limit = re.search(r'gh pr list .*--limit (\d+)', update)

    assert limit is not None
    assert int(limit.group(1)) >= 1000


def _fake_gh(tmp_path: Path) -> Path:
    """Write a stub `gh` that answers the run-listing calls the step makes.

    The counts are separated the way the real API separates them: an unfiltered
    listing includes the code-scanning runs created at the same commit, while the
    `event=pull_request` listing counts only the runs that carry the required
    checks. A step that forgot the event filter would therefore read a head with no
    required-check runs as healthy, which is the mistake worth failing on.

    Returns:
        The directory holding the stub.
    """
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir(exist_ok=True)
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent('''\
            #!/usr/bin/env python3
            """Answer only the API shapes the workflow asks for; reject the rest."""
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
            '''),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir


def _run_approve_step(  # noqa: PLR0913 -- one keyword per API answer the stub gives
    tmp_path: Path,
    updated_lines: str,
    *,
    pr_runs: str = '0',
    all_runs: str = '0',
    gated_count: str = '0',
    gated_tsv: str = '',
) -> subprocess.CompletedProcess[str]:
    """Run the real approve step against the stub, with its bounded waits collapsed."""
    (tmp_path / 'pr-catchup-updated.txt').write_text(updated_lines, encoding='utf-8')
    step = _extract_step_run('Approve the runs this catch-up caused')
    script = f'set -e\nsleep() {{ :; }}\n{step}'
    return subprocess.run(
        ['bash', '-c', script],
        env={
            **os.environ,
            'PATH': f'{_fake_gh(tmp_path)}{os.pathsep}{os.environ["PATH"]}',
            'GITHUB_WORKSPACE': str(Path(__file__).resolve().parents[1]),
            'PR_CATCHUP_DIR': str(tmp_path),
            'REPO': _REPO,
            'FAKE_PR_RUNS': pr_runs,
            'FAKE_ALL_RUNS': all_runs,
            'FAKE_GATED_COUNT': gated_count,
            'FAKE_GATED_TSV': gated_tsv,
        },
        capture_output=True,
        text=True,
        check=False,
    )


def _update_stub(tmp_path: Path) -> Path:
    """Write a stub `gh` for the update loop, answering the merge call per PR.

    None of the outcomes the loop branches on can be read from an exit status
    alone, so each is reproduced the way gh presents it: a merge prints the new
    SHA; a branch that already carries main prints nothing, because the endpoint
    answers 204 with an empty body; and a conflict or a fault prints only a
    trailing "(HTTP nnn)" on stderr. Every merge call is recorded, so a test can
    read back the refs and the subject the loop asked for.

    Returns:
        The directory holding the stub.
    """
    stub_dir = tmp_path / 'bin'
    stub_dir.mkdir(exist_ok=True)
    stub = stub_dir / 'gh'
    stub.write_text(
        dedent('''\
            #!/usr/bin/env python3
            """Answer the three calls the update loop makes; reject anything else."""
            import os
            import sys
            from pathlib import Path

            args = sys.argv[1:]
            state = Path(os.environ["FAKE_STATE"])

            if args[:2] == ["pr", "list"]:
                if os.environ["FAKE_LIST_FAILS"] == "yes":
                    print("gh: API rate limit exceeded (HTTP 403)", file=sys.stderr)
                    raise SystemExit(1)
                for number in os.environ["FAKE_PRS"].split():
                    print(number, f"feat/pr-{number}")
            elif args[:2] == ["pr", "view"]:
                conflicting = args[2] in os.environ["FAKE_CONFLICTING"].split()
                print("CONFLICTING" if conflicting else "MERGEABLE")
            elif args[0] == "api" and any(arg.endswith("/merges") for arg in args):
                fields = {}
                for flag, value in zip(args, args[1:]):
                    if flag == "-f":
                        key, _, field = value.partition("=")
                        fields[key] = field
                record = [fields["base"], fields["head"], fields["commit_message"]]
                with (state / "merges.tsv").open("a") as calls:
                    calls.write("\\t".join(record) + "\\n")
                number = fields["base"].rsplit("-", 1)[-1]
                refusal = ""
                if (os.environ.get("GH_TOKEN") == "app-token"
                    and os.environ.get("FAKE_APP_REFUSED") == "yes"):
                    print("gh: App denied (HTTP 403)", file=sys.stderr)
                    raise SystemExit(1)
                if number in (os.environ["FAKE_CONFLICTING"].split()
                              + os.environ["FAKE_WITHHELD"].split()):
                    refusal = "gh: Merge conflict (HTTP 409)"
                elif number in os.environ["FAKE_REFUSED"].split():
                    refusal = "gh: Resource not accessible by integration (HTTP 403)"
                if refusal:
                    print(refusal, file=sys.stderr)
                    raise SystemExit(1)
                if number not in os.environ["FAKE_CURRENT"].split():
                    print("b" * 40)
            else:
                raise SystemExit(f"fake gh: unexpected call: {args}")
            '''),
        encoding='utf-8',
    )
    stub.chmod(0o755)
    return stub_dir


def _run_update_step(  # noqa: PLR0913 -- one keyword per way the merge call answers
    tmp_path: Path,
    *,
    prs: str = '31',
    current: str = '',
    conflicting: str = '',
    withheld: str = '',
    refused: str = '',
    list_fails: bool = False,
    app_token: str = '',
    app_refused: bool = False,
) -> subprocess.CompletedProcess[str]:
    """Run the update loop against the stub, naming how the merge answers each PR.

    A PR named in none of `current`, `conflicting`, `withheld` or `refused` is
    merged and moves to a new head. A `withheld` PR gets the same 409 as a
    `conflicting` one, but GitHub reports it as mergeable.

    Returns:
        The finished step.
    """
    state = tmp_path / 'state'
    state.mkdir(exist_ok=True)
    return subprocess.run(
        ['bash', '-c', _extract_step_run('Update behind PR branches')],
        env={
            **os.environ,
            'PATH': f'{_update_stub(tmp_path)}{os.pathsep}{os.environ["PATH"]}',
            'PR_CATCHUP_DIR': str(tmp_path),
            'REPO': _REPO,
            'FAKE_STATE': str(state),
            'FAKE_PRS': prs,
            'FAKE_CURRENT': current,
            'FAKE_CONFLICTING': conflicting,
            'FAKE_WITHHELD': withheld,
            'FAKE_REFUSED': refused,
            'FAKE_LIST_FAILS': 'yes' if list_fails else 'no',
            'APP_TOKEN': app_token,
            'FALLBACK_TOKEN': 'default-token',
            'GH_TOKEN': 'default-token',
            'FAKE_APP_REFUSED': 'yes' if app_refused else 'no',
        },
        capture_output=True,
        text=True,
        check=False,
    )


def _run_verification_step(
    tmp_path: Path,
    gated_lines: str = '',
    silent_lines: str = '',
    refused_lines: str = '',
    blind_lines: str = '',
) -> subprocess.CompletedProcess[str]:
    """Run the verification step against each synthetic class of stuck PR."""
    step = _extract_step_run('Fail if any caused run is still awaiting approval')
    (tmp_path / 'pr-catchup-gated.txt').write_text(gated_lines, encoding='utf-8')
    (tmp_path / 'pr-catchup-silent.txt').write_text(silent_lines, encoding='utf-8')
    (tmp_path / 'pr-catchup-refused.txt').write_text(refused_lines, encoding='utf-8')
    (tmp_path / 'pr-catchup-blind.txt').write_text(blind_lines, encoding='utf-8')
    return subprocess.run(
        ['bash', '-c', step],
        env={
            **os.environ,
            'PR_CATCHUP_DIR': str(tmp_path),
            'REPO': _REPO,
        },
        capture_output=True,
        text=True,
        check=False,
    )


def test_the_catchup_merge_commit_carries_a_conventional_subject(
    tmp_path: Path,
) -> None:
    """The merge commit this workflow makes has a typed subject, not a bare `Merge`.

    The update-branch endpoint takes `expected_head_sha` and nothing else, so its
    merge commit always reads `Merge branch 'main' into ...`. The merge call takes a
    `commit_message`, and the subject it is given here passes the same
    Conventional Commit check that every human commit on a branch must pass. The
    PR number stands in for the branch name, whose length would otherwise decide
    whether the subject fits the hard maximum.
    """
    update = _run_update_step(tmp_path, prs='31')
    call = (tmp_path / 'state/merges.tsv').read_text(encoding='utf-8').strip()
    base, head, subject = call.split('\t')
    findings = check_subject(subject)

    assert update.returncode == 0
    # main is merged into the PR branch, never the other way around.
    assert (base, head) == ('feat/pr-31', 'main')
    assert subject == 'chore: merge main into #31'
    assert findings.errors == []
    assert findings.warnings == []


def test_a_failed_pr_listing_turns_the_run_red(tmp_path: Path) -> None:
    """A PR listing that fails turns the run red rather than updating nothing.

    The loop reads `gh pr list` through a pipe, so without pipefail the pipeline
    reports the `while` loop's own status, and a listing that died of a rate
    limit or an outage is indistinguishable from a repository with no PR
    behind main: the step updates nothing and stays green, which is the state
    this whole workflow exists to make impossible.
    """
    update = _run_update_step(tmp_path, list_fails=True)

    assert update.returncode != 0
    assert (tmp_path / 'pr-catchup-updated.txt').read_text(encoding='utf-8') == ''


def test_one_refused_pr_does_not_abandon_the_others(tmp_path: Path) -> None:
    """A refused PR is recorded, and the loop goes on to update the next one."""
    _run_update_step(tmp_path, prs='31 32', refused='31')

    refused = (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8')
    updated = (tmp_path / 'pr-catchup-updated.txt').read_text(encoding='utf-8')

    assert refused.split()[0] == '31'
    assert updated.split() == ['32', 'b' * 40]


def test_a_branch_already_carrying_main_is_not_treated_as_a_failure(
    tmp_path: Path,
) -> None:
    """A PR the merge call answers with an empty 204 is current, and is not reported.

    Every catch-up leaves far more PRs alone than it updates, so reading an empty
    body as anything but "nothing to do" would make the failure fire on ordinary
    runs.
    """
    update = _run_update_step(tmp_path, prs='31', current='31')

    assert update.returncode == 0
    assert (tmp_path / 'pr-catchup-updated.txt').read_text(encoding='utf-8') == ''
    assert (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8') == ''


def test_a_conflict_the_listing_could_not_hold_out_is_not_a_failure(
    tmp_path: Path,
) -> None:
    """A 409 on a conflicting PR leaves it behind without failing the run.

    `mergeable` reads UNKNOWN until GitHub has computed it, and the listing holds
    out only CONFLICTING, so a conflicting PR can still reach the merge call.
    Failing there would keep every catch-up red until somebody else rebased their
    branch, over a PR the listing excludes on its own once GitHub finishes the
    computation.
    """
    update = _run_update_step(tmp_path, prs='31', conflicting='31')

    assert update.returncode == 0
    assert (tmp_path / 'pr-catchup-updated.txt').read_text(encoding='utf-8') == ''
    assert (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8') == ''
    # A CONFLICTING entry is skipped in silence; this one at least says so.
    assert '#31 conflicts with main' in update.stdout


def test_a_409_on_a_pr_github_reports_as_mergeable_fails_the_run(
    tmp_path: Path,
) -> None:
    """A 409 is a conflict only when GitHub also reports the PR as conflicting.

    A clean merge that would change a workflow file the token cannot write is
    refused with a 409 too. Reading that as a conflict leaves the PR behind
    under a green run with a notice that misnames the cause.
    """
    update = _run_update_step(tmp_path, prs='31', withheld='31')
    recorded = (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8')
    verify = _run_verification_step(tmp_path, refused_lines=recorded)

    assert update.returncode == 0
    assert 'conflicts with main' not in update.stdout
    assert recorded.split()[:2] == ['31', 'feat/pr-31']
    assert '409' in recorded
    assert 'MERGEABLE' in recorded
    assert verify.returncode != 0


def test_a_refusal_that_is_neither_204_nor_409_is_reported_rather_than_read_as_current(
    tmp_path: Path,
) -> None:
    """A 403, a 404 or a rate limit leaves the branch behind, and the run says so.

    Only an empty body means the branch is already current, and only a 409 on a
    conflicting PR means the merge was never this workflow's to make. Folding any
    other refusal into either leaves a catch-up that was refused permission
    reporting success -- the PR looks current, and the runs that would have
    tested it were never created.
    """
    update = _run_update_step(tmp_path, prs='31', refused='31')
    recorded = (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8')
    verify = _run_verification_step(tmp_path, refused_lines=recorded)
    output = verify.stdout + verify.stderr

    # The loop stays green so the PRs after this one are still updated; the
    # verification step is where every class of stall is turned red.
    assert update.returncode == 0
    assert recorded.split()[:2] == ['31', 'feat/pr-31']
    assert '403' in recorded
    assert verify.returncode != 0
    assert '31' in output
    # The operator needs the status to tell a fault from an up-to-date branch, and
    # the branch name to re-run the merge by hand without looking it up first.
    assert '403' in output
    assert 'base=feat/pr-31' in output


def test_verification_fails_when_a_caused_run_stays_gated(tmp_path: Path) -> None:
    """A caused run still held at the gate turns the catch-up run red."""
    blocked = _run_verification_step(tmp_path, gated_lines='30138052205 27\n')
    cleared = _run_verification_step(tmp_path)

    assert blocked.returncode != 0
    assert '27' in blocked.stdout + blocked.stderr
    assert cleared.returncode == 0


def test_verification_fails_when_an_approval_pass_stayed_blind(tmp_path: Path) -> None:
    """An approval pass that could not confirm the gate turns the run red."""
    sha = 'd' * 40
    blocked = _run_verification_step(tmp_path, blind_lines=f'31 {sha}\n')
    cleared = _run_verification_step(tmp_path)
    output = blocked.stdout + blocked.stderr

    assert blocked.returncode != 0
    assert '31' in output
    assert sha in output
    assert cleared.returncode == 0


def test_a_head_with_no_required_check_runs_fails_rather_than_warns(
    tmp_path: Path,
) -> None:
    """An updated head whose checks never appear fails the run rather than warning.

    A warning that exits green leaves the runs held with nobody to approve them,
    the stall this workflow exists to end. `all_runs` exceeds `pr_runs` here on
    purpose: code-scanning runs do appear at the merge commit, so a wait that
    counted every event would call this head healthy.
    """
    sha = 'c' * 40
    approve = _run_approve_step(tmp_path, f'31 {sha}\n', pr_runs='0', all_runs='2')
    recorded = (tmp_path / 'pr-catchup-silent.txt').read_text(encoding='utf-8')
    verify = _run_verification_step(tmp_path, silent_lines=recorded)
    output = verify.stdout + verify.stderr

    assert approve.returncode == 0
    assert recorded.split() == ['31', sha]
    assert verify.returncode != 0
    assert '31' in output
    assert sha in output


def test_a_head_whose_runs_are_ungated_stays_green(tmp_path: Path) -> None:
    """Runs that exist and are not held need nothing, and the step passes.

    This is the shape the repository takes if the gate is ever lifted or the update
    is pushed with an App identity: runs appear and report on their own. A bare
    "no gated run found means failure" rule would turn every catch-up red here.
    """
    approve = _run_approve_step(tmp_path, f'31 {"d" * 40}\n', pr_runs='4', all_runs='6')

    assert approve.returncode == 0
    assert (tmp_path / 'pr-catchup-silent.txt').read_text(encoding='utf-8') == ''
    assert (tmp_path / 'pr-catchup-gated.txt').read_text(encoding='utf-8') == ''


def test_a_blind_approval_pass_is_reported_apart_from_a_confirmed_gate(
    tmp_path: Path,
) -> None:
    """A silent Actions lookup failure is reported as unconfirmed, not as clear.

    A held count with no id to show for it is what a failed `gh api` lookup
    looks like from here: it writes nothing to stdout, so the count reads
    non-zero but the listing that would name the run reads empty too. Filing
    that under "still gated" would name a run that was never identified;
    filing it as unconfirmed is the honest report.
    """
    sha = 'd' * 40
    approve = _run_approve_step(
        tmp_path, f'31 {sha}\n', pr_runs='4', gated_count='1', gated_tsv=''
    )

    assert approve.returncode == 0
    assert (tmp_path / 'pr-catchup-gated.txt').read_text(encoding='utf-8') == ''
    blind = (tmp_path / 'pr-catchup-blind.txt').read_text(encoding='utf-8')
    assert blind.split() == ['31', sha]


def test_failure_output_carries_the_operator_recovery_path(tmp_path: Path) -> None:
    """The failed run's output names both ways out: approving now, and an App identity.

    The approval path is unverified for GITHUB_TOKEN, so the run itself has to
    say what to do now and what to change if it keeps happening. Nobody should
    have to re-derive the App-identity fallback from the header comment.
    """
    # The harness supplies REPO, so the step has to be shown to ask for it too;
    # otherwise a real run would print the command with an empty repository.
    assert 'REPO: ${{ github.repository }}' in _extract_step(
        'Fail if any caused run is still awaiting approval'
    )

    blocked = _run_verification_step(tmp_path, '30138052205 27\n')
    output = blocked.stdout + blocked.stderr

    assert (
        f'gh api --method POST repos/{_REPO}/actions/runs/30138052205/approve' in output
    )
    assert 'App installation token' in output
    assert 'github-actions[bot]' in output


def test_header_documents_the_gate_it_works_around() -> None:
    """The header names the approval gate that holds the runs a catch-up causes."""
    prose = _header_prose()
    assert "triggers the PR's checks against the real merge result" not in prose
    assert 'action_required' in prose
    assert (
        'https://github.blog/changelog/2026-06-11-bot-created-pull-requests-can-run-workflows-if-approved/'
        in prose
    )


def test_header_documents_the_unattributed_changes_rule() -> None:
    """The header records that the extra-approval rule does not stall a bot merge.

    A run in a repository whose ruleset sets that rule settled the question: a
    github-actions[bot] merge commit is not read as unattributed,
    so the PR it updates still merges once its checks report.
    """
    prose = _header_prose()
    assert 'require_extra_approval_for_unattributed_changes' in prose
    assert 'does not treat' in prose


def test_a_dispatch_is_honored_only_from_the_default_branch() -> None:
    """A manual dispatch runs the job only from the default branch.

    A dispatched run loads this file from the ref it was dispatched from, while push
    events already arrive only from the default branch. Without this guard a
    contributor could push a branch redefining this workflow and dispatch it, running
    unreviewed code with contents, pull-requests, and actions write.
    """
    directives = ' '.join(_strip_comments(_WORKFLOW).split())
    assert (
        "if: >- github.event_name != 'workflow_dispatch' || github.ref == "
        "format('refs/heads/{0}', github.event.repository.default_branch)" in directives
    )


def test_nothing_runs_this_on_a_timer() -> None:
    """No schedule starts this workflow.

    A push to main by a person or an App starts it; a merge completed under
    GITHUB_TOKEN does not. The header accepts that gap rather than adding a daily
    run that usually finds nothing, so a cron that comes back should come with a
    reason.
    """
    assert 'schedule:' not in _DIRECTIVES
    assert 'cron:' not in _DIRECTIVES


def test_it_can_still_be_asked_for() -> None:
    """A push to main and a manual dispatch both start this workflow."""
    assert 'workflow_dispatch:' in _DIRECTIVES
    assert 'push:' in _DIRECTIVES


def test_a_refused_app_merge_retries_with_the_default_token(tmp_path: Path) -> None:
    """A denied App token falls back and records the SHA for gated-run approval."""
    result = _run_update_step(tmp_path, app_token='app-token', app_refused=True)
    calls = (tmp_path / 'state/merges.tsv').read_text(encoding='utf-8').splitlines()

    assert result.returncode == 0
    assert len(calls) == 2
    assert (tmp_path / 'pr-catchup-updated.txt').read_text(
        encoding='utf-8'
    ).split() == ['31', 'b' * 40]
    assert (tmp_path / 'pr-catchup-refused.txt').read_text(encoding='utf-8') == ''


def test_an_app_merge_needs_no_default_token_run_approval(tmp_path: Path) -> None:
    """An App-attributed SHA is left out of the default-token approval queue."""
    result = _run_update_step(tmp_path, app_token='app-token')

    assert result.returncode == 0
    assert 'updated #31' in result.stdout
    assert (tmp_path / 'pr-catchup-updated.txt').read_text(encoding='utf-8') == ''
