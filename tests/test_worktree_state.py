"""worktree_state.py 단위 시험 — 임시 git 저장소에서 worktree 상태 판정이 맞는지 본다.

R-iface-waiver: 공개 심볼은 전부 pytest 수집 대상 테스트 함수다. 지는 책임은 하나 —
`worktree_state.py` 의 상태 판정 계약. pytest 는 `test_` 로 시작하는 공개 함수만 수집한다.

무엇을 지키는가: 마무리 스킬(G1)·Stop 훅(G2)·시작 알림(G3)·계획서 편집 경고(G4)가 모두 이 판정에
딛고 선다. 여기가 조용히 틀리면 합치지 않은 브랜치를 "합쳐짐" 으로, 지우면 안 되는 파일을
"다시 만들 수 있음" 으로 읽는다.
계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (Step 1)
"""

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

_SRC = Path(__file__).resolve().parent.parent / "assets" / "hooks" / "worktree_state.py"
_spec = importlib.util.spec_from_file_location("_worktree_state_under_test", _SRC)
ws = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = ws  # dataclass 는 정의 중에 자기 모듈을 sys.modules 에서 찾는다
_spec.loader.exec_module(ws)

# 커밋 게이트 안에서 돌면 git 이 GIT_DIR·GIT_INDEX_FILE 등을 넘긴다 — 임시 저장소가 아닌 곳을 가리키지 않게 지운다.
_GIT_LOCATION = ("GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_PREFIX")
_ENV = {**{k: v for k, v in os.environ.items() if k not in _GIT_LOCATION}, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
PLAN = "docs/exec-plans/active/2026-11-20-x-plan.md"
DONE = "docs/exec-plans/completed/2026-11-20-x-plan.md"


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, env=_ENV, check=True, capture_output=True, text=True).stdout


def move_plan(wt):
    (Path(wt) / DONE).parent.mkdir(parents=True, exist_ok=True)
    git(wt, "mv", PLAN, DONE)


def write(root, rel, text="x\n"):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


@pytest.fixture
def repo(tmp_path):
    """main 에 계획서 하나가 있는 저장소와, 그 위의 worktree 하나(브랜치 feat)."""
    main = tmp_path / "main"
    main.mkdir()
    git(main, "init", "-q", "-b", "main")
    write(main, ".gitignore", "node_modules/\n.env\nserver/uploads/\n__pycache__/\n")
    write(main, PLAN, "# plan\n")
    git(main, "add", "-A")
    git(main, "commit", "-qm", "init")
    wt = tmp_path / "wt"
    git(main, "worktree", "add", "-q", "-b", "feat", str(wt))
    return main, wt


def test_a_fresh_worktree_has_nothing_to_merge(repo):
    main, wt = repo
    s = ws.state_of(wt)
    assert (s.branch, s.ahead, s.changes, s.touched_plans, s.completed_plans, s.stray_ignored) == ("feat", 0, 0, [], [], [])
    assert s.is_main_checkout is False
    assert ws.state_of(main).is_main_checkout is True


def test_commits_ahead_and_the_plans_they_touch(repo):
    _, wt = repo
    write(wt, PLAN, "# plan\n- [x] G1\n")
    write(wt, "src/a.txt")
    git(wt, "add", "-A")
    git(wt, "commit", "-qm", "work")
    s = ws.state_of(wt)
    assert (s.ahead, s.changes, s.touched_plans, s.completed_plans) == (1, 0, [PLAN], [])


def test_uncommitted_edits_count_as_changes_and_touch_the_plan(repo):
    _, wt = repo
    write(wt, PLAN, "# plan\n- [x] G1\n")
    write(wt, "new/file.txt")
    s = ws.state_of(wt)
    assert (s.ahead, s.changes, s.touched_plans) == (0, 2, [PLAN])


def test_a_committed_move_to_completed_is_seen(repo):
    _, wt = repo
    move_plan(wt)
    git(wt, "commit", "-qm", "done")
    s = ws.state_of(wt)
    assert s.completed_plans == ["2026-11-20-x-plan.md"]
    assert PLAN in s.touched_plans


@pytest.mark.parametrize("staged", [True, False])
def test_an_uncommitted_move_to_completed_is_seen_staged_or_not(repo, staged):
    _, wt = repo
    if staged:
        move_plan(wt)
    else:
        (Path(wt) / DONE).parent.mkdir(parents=True)
        os.rename(Path(wt) / PLAN, Path(wt) / DONE)
    assert ws.state_of(wt).completed_plans == ["2026-11-20-x-plan.md"]


def test_a_move_with_heavy_edits_is_still_seen(repo):
    _, wt = repo
    move_plan(wt)
    write(wt, DONE, "".join(f"line {i}\n" for i in range(200)))
    git(wt, "add", "-A")
    git(wt, "commit", "-qm", "done and rewritten")
    assert ws.state_of(wt).completed_plans == ["2026-11-20-x-plan.md"]


def test_once_merged_into_main_nothing_is_left(repo):
    main, wt = repo
    move_plan(wt)
    git(wt, "commit", "-qm", "done")
    git(main, "merge", "-q", "--ff-only", "feat")
    s = ws.state_of(wt)
    assert (s.ahead, s.changes, s.completed_plans, s.touched_plans) == (0, 0, [], [])


def test_ignored_files_outside_the_allowlist_are_stray(repo):
    _, wt = repo
    write(wt, "node_modules/pkg/index.js")
    write(wt, "server/uploads/help/a.bin")
    write(wt, "src/__pycache__/m.pyc")
    os.symlink("/nonexistent/.env", Path(wt) / ".env")
    assert ws.state_of(wt).stray_ignored == ["server/uploads/"]


def test_a_real_env_file_is_stray_but_a_link_is_not(repo):
    _, wt = repo
    write(wt, ".env", "A=1\n")
    assert ws.state_of(wt).stray_ignored == [".env"]


def test_detached_head_has_no_branch(repo):
    _, wt = repo
    git(wt, "checkout", "-q", "--detach")
    assert ws.state_of(wt).branch is None


def test_list_worktrees_and_linked_check(repo):
    main, wt = repo
    listed = ws.list_worktrees(main)
    assert [(Path(p).resolve(), b) for p, b in listed] == [(main.resolve(), "main"), (wt.resolve(), "feat")]
    assert (ws.is_linked_worktree(wt), ws.is_linked_worktree(main)) == (True, False)


def test_a_missing_main_branch_is_an_error_not_a_guess(repo):
    _, wt = repo
    with pytest.raises(ws.WorktreeStateError):
        ws.state_of(wt, main_branch="trunk")


@pytest.mark.parametrize("ignore_line", [".claude/settings.local.json", ".claude/"])
def test_session_permissions_are_kept_even_inside_claude(repo, ignore_line):
    _, wt = repo
    (Path(wt) / ".gitignore").write_text(f"{ignore_line}\n", encoding="utf-8")
    git(wt, "commit", "-qam", "ignore")
    write(wt, ".claude/skills/x/SKILL.md")
    write(wt, ".claude/settings.local.json", "{}\n")
    assert ws.state_of(wt).stray_ignored == [".claude/settings.local.json" if ignore_line != ".claude/" else ".claude/"]


def test_a_plan_born_and_finished_in_the_branch_is_seen(repo):
    """main 에 없던 계획서를 가지에서 쓰고 completed 로 옮겨도 잡는다 — 2026-11-20 jj-agent-room 복제본 실측에서 놓쳤다."""
    _, wt = repo
    born = "docs/exec-plans/active/2026-11-20-born-plan.md"
    write(wt, born, "# born\n")
    git(wt, "add", "-A")
    git(wt, "commit", "-qm", "plan")
    (Path(wt) / "docs/exec-plans/completed").mkdir(parents=True, exist_ok=True)
    git(wt, "mv", born, "docs/exec-plans/completed/2026-11-20-born-plan.md")
    git(wt, "commit", "-qm", "done")
    assert ws.state_of(wt).completed_plans == ["2026-11-20-born-plan.md"]


def test_editing_a_plan_already_completed_in_main_is_not_finishing(repo):
    main, wt = repo
    (Path(main) / DONE).parent.mkdir(parents=True, exist_ok=True)
    git(main, "mv", PLAN, DONE)
    git(main, "commit", "-qm", "done in main")
    git(wt, "merge", "-q", "--ff-only", "main")
    write(wt, DONE, "# plan\nretro\n")
    assert ws.state_of(wt).completed_plans == []


def test_session_permissions_copied_from_main_are_safe_to_lose(repo):
    """앱은 메인의 settings.local.json 을 worktree 로 복사한다 — 메인과 같으면 지워도 잃지 않는다."""
    main, wt = repo
    (Path(main) / ".gitignore").write_text(".claude/settings.local.json\n", encoding="utf-8")
    git(main, "add", "-A"); git(main, "commit", "-qm", "ignore")
    git(wt, "merge", "-q", "--ff-only", "main")
    write(main, ".claude/settings.local.json", '{"a": 1}\n')
    write(wt, ".claude/settings.local.json", '{"a": 1}\n')
    assert ws.state_of(wt).stray_ignored == []
    write(wt, ".claude/settings.local.json", '{"a": 2}\n')
    assert ws.state_of(wt).stray_ignored == [".claude/settings.local.json"]
