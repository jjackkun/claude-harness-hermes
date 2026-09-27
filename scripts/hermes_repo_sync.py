#!/usr/bin/env python3
"""저장소 사본이 원격보다 앞/뒤인지 — **망 없이** 이미 받아 둔 원격 추적 ref 로만 판정한다
(계획 2026-09-27-dashboard-sync-before-verdict).

왜: 우주 대시보드가 "뒤처짐" 을 냈는데 실제로는 설치가 아니라 **사본**이 옛것이었다(2026-09-22,
ai-create 가 origin 보다 10 커밋 뒤). 설치를 판정하기 전에 사본부터 가른다.

fetch 는 하지 않는다 — 대시보드는 외부 자원 0 인 보기 전용 도구다. 대신 마지막 fetch 시각을
함께 돌려 "이 비교 자체가 옛것일 수 있다" 를 사람이 알게 한다.
판정 불가는 synced 로 합치지 않는다(fail-closed): no_git · no_upstream · unknown 은 따로 둔다.

공개 함수 1개: repo_sync
"""
import os
import subprocess
from datetime import datetime

_GIT_TIMEOUT = 10


def _git(path: str, *args: str):
    """성공하면 stdout(strip), 실패하면 None."""
    try:
        r = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True, timeout=_GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def _fetched_at(path: str):
    rel = _git(path, "rev-parse", "--git-path", "FETCH_HEAD")
    if not rel:
        return None
    try:
        mtime = os.path.getmtime(rel if os.path.isabs(rel) else os.path.join(path, rel))
    except OSError:
        return None
    return datetime.fromtimestamp(mtime).isoformat(timespec="minutes")


def _state(ahead: int, behind: int) -> str:
    if ahead and behind:
        return "diverged"
    if behind:
        return "behind"
    return "ahead" if ahead else "synced"


def repo_sync(path: str) -> dict:
    """{state, ahead, behind, fetched_at}. state: synced·behind·ahead·diverged·no_git·no_upstream·unknown."""
    result = {"state": "unknown", "ahead": 0, "behind": 0, "fetched_at": None}
    top = _git(path, "rev-parse", "--show-toplevel")
    # 상위 폴더의 저장소를 이 소우주의 것으로 오인하지 않는다.
    if top is None or os.path.realpath(top) != os.path.realpath(path):
        return dict(result, state="no_git")
    result = dict(result, fetched_at=_fetched_at(path))
    if _git(path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}") is None:
        return dict(result, state="no_upstream")
    counts = _git(path, "rev-list", "--left-right", "--count", "HEAD...@{u}")
    try:
        ahead, behind = (int(n) for n in counts.split())
    except (AttributeError, ValueError):
        return result
    return dict(result, state=_state(ahead, behind), ahead=ahead, behind=behind)
