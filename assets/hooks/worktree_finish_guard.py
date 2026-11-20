#!/usr/bin/env python3
"""G2 판정 — 계획서를 completed 로 옮겼는데 main 에 합치지 않은 worktree 세션의 끝내기를 한 번 막는다.

stdin: Stop 훅 페이로드(session_id · cwd · stop_hook_active). 막을 때만 stdout 에 {"decision":"block","reason":…}.
통과: stop_hook_active · cwd 없음(마무리로 지움) · worktree 아님 · completed 이동 없음 · 이미 합침(조상이거나 main 과 내용이 같음) ·
같은 완료 계획서 묶음으로 이 세션에 이미 한 번 막음(커밋이 이어져도 다시 막지 않는다 — 코드 리뷰 M2). 판정 실패(git 오류 등)도 통과 — 세션을 막지 않는다.
기록: <git 공통 폴더>/worktree-finish-guard/<session_id> 에 막은 계획서 묶음 하나. 7일 지난 기록은 쓸 때 지운다.
계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (G2)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worktree_state as ws  # noqa: E402 — 같은 폴더의 판정 모듈

RECORD_DAYS = 7


def _git(cwd: str, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=10, check=True).stdout


def _same_tree_as_main(cwd: str, main: str) -> bool:
    """main 과 내용이 같다 — squash 로 합쳐 조상 관계는 없지만 이미 들어간 경우(코드 리뷰 M3)."""
    return subprocess.run(["git", "diff", "--quiet", f"refs/heads/{main}", "HEAD"], cwd=cwd, timeout=10).returncode == 0


def _prune(folder: Path) -> None:
    cutoff = time.time() - RECORD_DAYS * 86400
    for old in folder.glob("*"):
        if old.is_file() and old.stat().st_mtime < cutoff:
            old.unlink(missing_ok=True)


def _record(cwd: str, session: str) -> Path:
    common = Path(_git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir").strip())
    return common / "worktree-finish-guard" / (re.sub(r"[^A-Za-z0-9_-]", "_", session) or "unknown")


def _reason(state: ws.WorktreeState) -> str:
    plans = ", ".join(state.completed_plans)
    return (
        f"[worktree-finish] 계획서 {plans} 를 completed 로 옮겼는데, 이 worktree 의 일이 main 에 없습니다 "
        f"(main 에 없는 커밋 {state.ahead}개 · 커밋 안 된 변경 {state.changes}개).\n"
        "  → worktree-finish 스킬을 불러 합치고 지우십시오(스킬 기준 폴더의 scripts/finish.sh, 셸 위치는 이 worktree).\n"
        "  → PR 로 합치는 저장소라면 PR 상태를 사용자에게 알리십시오.\n"
        "  → 합치지 않을 이유가 있으면 그 이유를 사용자에게 말하고 끝내십시오. 이 세션에서 같은 계획서로는 다시 막지 않습니다."
    )


def _unmerged_finished(cwd: str) -> ws.WorktreeState | None:
    """계획서를 completed 로 옮겼는데 main 에 없는 일이 남은 worktree 의 상태 — 아니면 None."""
    if not ws.is_linked_worktree(cwd):
        return None
    main = ws.default_main(cwd)
    state = ws.state_of(cwd, main, with_stray=False)
    if not state.completed_plans or (state.ahead == 0 and state.changes == 0):
        return None
    if state.changes == 0 and _same_tree_as_main(cwd, main):
        return None
    return state


def _first_time(cwd: str, session: str, key: str) -> bool:
    """이 세션에서 이 계획서 묶음으로 처음 막는가 — 처음이면 기록하고 True."""
    record = _record(cwd, session)
    if record.is_file() and record.read_text(encoding="utf-8").strip() == key:
        return False
    record.parent.mkdir(parents=True, exist_ok=True)
    _prune(record.parent)
    record.write_text(key + "\n", encoding="utf-8")
    return True


def decide(payload: dict) -> str | None:
    """막을 때 reason, 아니면 None."""
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if payload.get("stop_hook_active") or not cwd or not Path(cwd).is_dir():
        return None
    try:
        state = _unmerged_finished(cwd)
        if state is None or not _first_time(cwd, str(payload.get("session_id") or ""), "\n".join(state.completed_plans)):
            return None
    except (ws.WorktreeStateError, subprocess.SubprocessError, OSError) as e:
        print(f"[worktree-finish-guard] 판정 실패 — 통과: {e}", file=sys.stderr)
        return None
    return _reason(state)


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    reason = decide(payload if isinstance(payload, dict) else {})
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
