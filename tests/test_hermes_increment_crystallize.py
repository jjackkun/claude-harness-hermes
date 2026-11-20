"""실수 감지 키가 결정화 대상에 오르는지 — G5 (계획 2026-11-20-worktree-finish).

R-iface-waiver: 공개 심볼은 전부 pytest 수집 대상 테스트 함수다. 지는 책임은 하나 —
"실수 감지 훅이 센 키도 세션 저장이 결정화 목록에 올린다" 는 계약.

왜: 실수 감지 훅(claude-userpromptsubmit-mistake-detect.sh)은 hermes-increment.py 로 count 만 올리고,
세션 저장(update_patterns)은 그 세션 요약 키만 돌았다. jj-agent-room 에서 worktree-not-synced 가
104번 쌓이고도 결정화 대상에 한 번도 오르지 않았다(2026-11-20 실측).
"""

import importlib.util
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


storage = _load("_storage_under_test", SCRIPTS / "hermes_save_session_storage.py")
keys = _load("_mistake_keys_under_test", SCRIPTS / "hermes_mistake_keys.py")


@pytest.fixture
def db(tmp_path):
    path = tmp_path / "state.db"
    subprocess.run([sys.executable, str(SCRIPTS / "hermes-init.py"), "--db", str(path)], check=True, capture_output=True)
    return str(path)


def bump(db, key, times):
    for _ in range(times):
        subprocess.run([sys.executable, str(SCRIPTS / "hermes-increment.py"), "--db", db, "--key", key], check=True, capture_output=True)


def test_a_mistake_key_counted_three_times_is_a_target_at_the_next_save(db):
    bump(db, "worktree-not-synced", 3)
    assert "worktree-not-synced" in storage.update_patterns(db, ["some-summary-key"], "session-1")


def test_below_three_it_is_not(db):
    bump(db, "css-property-missing", 2)
    assert "css-property-missing" not in storage.update_patterns(db, [], "session-1")


def test_repeated_mistake_is_never_a_target(db):
    bump(db, "repeated-mistake", 5)
    assert "repeated-mistake" not in storage.update_patterns(db, [], "session-1")


@pytest.mark.parametrize("state", [1, -1])
def test_a_judged_key_is_not_a_target_again(db, state):
    bump(db, "worktree-not-synced", 4)
    con = sqlite3.connect(db)
    con.execute("UPDATE pattern_count SET crystallized=? WHERE pattern_key='worktree-not-synced'", (state,))
    con.commit()
    con.close()
    assert "worktree-not-synced" not in storage.update_patterns(db, [], "session-1")


def test_a_key_listed_by_the_session_and_the_hook_appears_once(db):
    bump(db, "worktree-not-synced", 3)
    targets = storage.update_patterns(db, ["worktree-not-synced"], "session-1")
    assert targets.count("worktree-not-synced") == 1


def test_summary_keys_still_behave_as_before(db):
    for i in range(3):
        targets = storage.update_patterns(db, ["summary-key"], f"session-{i}")
    assert targets == ["summary-key"]


def test_the_key_list_matches_the_hook():
    """훅이 내는 detect_key 와 목록이 같아야 한다 — 훅에 키를 더하고 목록을 잊으면 또 구멍이 생긴다."""
    hook = (ROOT / "assets" / "hooks" / "claude-userpromptsubmit-mistake-detect.sh").read_text(encoding="utf-8")
    in_hook = set(re.findall(r'detect_key="([a-z0-9-]+)"', hook))
    assert in_hook == set(keys.MISTAKE_KEYS)
    assert keys.NOT_CRYSTALLIZED <= set(keys.MISTAKE_KEYS)


def test_the_list_is_installed_with_the_hermes_scripts():
    conf = (ROOT / "presets" / "workflow" / "hermes.conf").read_text(encoding="utf-8")
    assert re.search(r"^\s+hermes_mistake_keys\.py$", conf, re.M)
