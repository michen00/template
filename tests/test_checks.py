from __future__ import annotations

__all__ = ()

import pytest

from checks import check_pr_title
from checks._common import (
    SUBJECT_MAX_DEFAULT,
    check_subject,
    parse_max_length,
    subject_max_length,
)
from checks.check_commit_messages import check_commits


@pytest.fixture(autouse=True)
def _isolated_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep a developer's shell or a CI runner from changing what the checks see."""
    for name in (
        'SUBJECT_MAX_LENGTH',
        'GITHUB_ACTIONS',
        'PR_WARNINGS_FILE',
        'PR_TITLE',
    ):
        monkeypatch.delenv(name, raising=False)


def _title(length: int) -> str:
    """Return a valid Conventional Commit title exactly ``length`` characters long."""
    return 'feat: ' + 'a' * (length - len('feat: '))


def test_the_default_maximum_is_fifty() -> None:
    """With no argument and no variable, the maximum is git's 50."""
    assert subject_max_length() == SUBJECT_MAX_DEFAULT == 50


def test_the_environment_sets_the_maximum(monkeypatch: pytest.MonkeyPatch) -> None:
    """SUBJECT_MAX_LENGTH sets the maximum that check_subject applies."""
    monkeypatch.setenv('SUBJECT_MAX_LENGTH', '72')
    assert subject_max_length() == 72
    assert check_subject(_title(56)).ok


def test_an_argument_beats_the_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    """An explicit maximum wins over SUBJECT_MAX_LENGTH."""
    monkeypatch.setenv('SUBJECT_MAX_LENGTH', '72')
    assert subject_max_length(60) == 60


@pytest.mark.parametrize('value', ['', ' ', '0', '-5', '7.5', 'seventy', '72 chars'])
def test_an_unusable_variable_falls_back_to_the_default(value: str) -> None:
    """A variable that is neither a positive whole number nor off falls back to 50."""
    assert subject_max_length(environ={'SUBJECT_MAX_LENGTH': value}) == 50


@pytest.mark.parametrize('setting', ['off', 'OFF', ' Off ', 'none', 'false'])
def test_off_leaves_the_length_unchecked(setting: str) -> None:
    """`off`, or `none` or `false` in any case, turns the length rule off."""
    assert parse_max_length(setting) is None
    assert subject_max_length(setting) is None
    assert subject_max_length(environ={'SUBJECT_MAX_LENGTH': setting}) is None


def test_an_unchecked_length_keeps_every_other_rule() -> None:
    """With the length off, a long subject passes and a trailing period still blocks."""
    assert check_subject(_title(200), max_length='off').ok
    assert check_subject('fix: guard the empty body.', max_length='off').errors == [
        'subject: must not end with a period'
    ]


@pytest.mark.parametrize('first_word', ['Guard', 'URL-encode'])
def test_a_capitalized_start_blocks(first_word: str) -> None:
    """A capital blocks, a capitalized verb included: it can be reworded."""
    found = check_subject(f'fix: {first_word} the empty body')
    assert not found.ok
    assert f"must start lowercase ('{first_word}')" in found.errors[0]


@pytest.mark.parametrize('setting', ['', 'sixty', '0', '-3', '3.5'])
def test_an_unusable_argument_is_an_error(setting: str) -> None:
    """An argument is the caller's own, so a bad one is raised rather than replaced."""
    with pytest.raises(ValueError, match='positive whole number or off'):
        subject_max_length(setting)


@pytest.mark.parametrize(('max_length', 'bound'), [(None, 50), (40, 40)])
def test_the_error_names_the_applied_bound(max_length: int | None, bound: int) -> None:
    """The length error reports the maximum that was actually applied."""
    found = check_subject(_title(51), label='title', max_length=max_length)
    assert found.errors == [f'title: 51 chars exceeds hard max {bound}']


def test_commit_subjects_take_the_same_maximum() -> None:
    """check_commits passes its maximum through to every subject it checks."""
    rows = [('0123456789abcdef', 'A Developer', _title(56))]
    assert not check_commits(rows).ok
    assert check_commits(rows, max_length=72).ok
    assert check_commits(rows, max_length='off').ok


def test_max_length_passes_a_title_that_fails_at_the_default() -> None:
    """``--max-length 72`` passes a 56-character title that fails at 50."""
    assert check_pr_title.main([_title(56)]) == 1
    assert check_pr_title.main([_title(56), '--max-length', '72']) == 0


def test_off_on_the_command_line_says_so(capsys: pytest.CaptureFixture[str]) -> None:
    """`--max-length off` passes a long title, and the log says so."""
    assert check_pr_title.main([_title(60), '--max-length', 'off']) == 0
    assert capsys.readouterr() == ('title OK, length not checked\n', '')


@pytest.mark.parametrize('setting', ['0', '-3', 'sixty'])
def test_an_unusable_flag_is_a_usage_error(
    setting: str, capsys: pytest.CaptureFixture[str]
) -> None:
    """A bad `--max-length` stops with a usage error that names the flag."""
    with pytest.raises(SystemExit) as stopped:
        check_pr_title.main(['docs: fix a typo', '--max-length', setting])
    assert stopped.value.code == 2
    assert 'argument --max-length: expected a positive whole number or off' in (
        capsys.readouterr().err
    )


def test_the_squash_suffix_is_not_counted(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    """A title at the maximum passes cleanly, whatever its pull request number."""
    monkeypatch.setenv('PR_NUMBER', '100')
    assert check_pr_title.main([_title(50)]) == 0
    assert capsys.readouterr().err == ''
