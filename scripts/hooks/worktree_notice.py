#!/usr/bin/env python3
"""G3 시작 알림 — main 에 안 들어간 worktree(앞선 커밋 또는 커밋 안 된 변경)를 세션 시작에 한 번 알린다. 막지 않는다.

stdin: SessionStart 페이로드(cwd). 알릴 것이 있을 때만 stdout 에 additionalContext JSON.
메인 체크아웃은 세지 않는다(그곳의 커밋 안 된 변경은 평소 작업이다). 10개까지 이름을 보이고 나머지는 수로.
판정 실패는 조용히 넘어간다 — 알림이 세션 시작을 막지 않는다.
계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (G3)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worktree_state as ws  # noqa: E402 — 같은 폴더의 판정 모듈

# 압축(compact)·clear 마다 다시 알리지 않는다 — 새 세션과 이어 하기에서만(코드 리뷰 L1).
NOTICE_SOURCES = {"startup", "resume", None}
SHOW_MAX = 10


def unmerged(cwd: str) -> list[ws.WorktreeState]:
    found, main = [], ws.default_main(cwd)
    for path, _branch in ws.list_worktrees(cwd)[1:]:  # 첫 줄은 메인 체크아웃
        if not Path(path).is_dir():
            continue
        try:
            state = ws.state_of(path, main, with_stray=False)
        except ws.WorktreeStateError:
            continue
        if state.ahead or state.changes:
            found.append(state)
    return found


def render(states: list[ws.WorktreeState], here: str) -> str:
    lines = [
        f"[worktree-unmerged] main 에 안 들어간 worktree {len(states)}개 — 일이 끝난 것은 그 worktree 세션에서 "
        "worktree-finish 스킬로 합치고 지우십시오. 다른 세션이 쓰는 중일 수 있으니 남의 worktree 는 옮기거나 지우지 않습니다."
    ]
    for s in states[:SHOW_MAX]:
        mark = " (이 세션)" if Path(s.path).resolve() == Path(here).resolve() else ""
        lines.append(f"  - {s.branch or Path(s.path).name}{mark} · 커밋 {s.ahead} · 변경 {s.changes} · 마지막 {s.last_commit[:16]}")
    if len(states) > SHOW_MAX:
        lines.append(f"  … 외 {len(states) - SHOW_MAX}개")
    return "\n".join(lines)


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        payload = {}
    payload = payload if isinstance(payload, dict) else {}
    if payload.get("source") not in NOTICE_SOURCES:
        return 0
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if not cwd or not Path(cwd).is_dir():
        return 0
    try:
        states = unmerged(cwd)
        here = ws._git(cwd, "rev-parse", "--show-toplevel").strip()
    except ws.WorktreeStateError as e:
        print(f"[worktree-notice] 판정 실패 — 넘어감: {e}", file=sys.stderr)
        return 0
    if states:
        out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": render(states, here)}}
        print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
