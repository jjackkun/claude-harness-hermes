#!/usr/bin/env python3
"""G4 판정 — 편집하려는 active 계획서를 다른 worktree(또는 메인 체크아웃)도 고치는 중이면 알린다. 막지 않는다.

stdin: PreToolUse 페이로드(cwd · tool_input.file_path). 겹칠 때만 stdout 에 additionalContext JSON.
"고치는 중" = 그쪽이 main 에 없는 커밋이나 커밋 안 된 변경으로 같은 파일을 건드렸다. 자기 worktree 는 세지 않는다.
2026-11-19 jj-agent-room: 두 세션이 같은 결재 계획서로 같은 단계를 따로 만들었다 — 편집 전에 알았다면 막을 수 있었다.
계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (G4)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worktree_state as ws  # noqa: E402 — 같은 폴더의 판정 모듈

ACTIVE = "docs/exec-plans/active/"


def _plan_rel(top: Path, cwd: str, file_path: str) -> str | None:
    """저장소 기준 경로 — active 계획서(.md)가 아니거나 저장소 밖이면 None."""
    target = Path(file_path) if Path(file_path).is_absolute() else Path(cwd) / file_path
    try:
        rel = target.resolve().relative_to(top).as_posix()
    except ValueError:
        return None
    return rel if rel.startswith(ACTIVE) and rel.endswith(".md") else None


def _touching(path: str, branch: str | None, is_main: bool, rel: str, main: str) -> str | None:
    """이 worktree 가 rel 을 고치는 중이면 보일 한 줄, 아니면 None. 판정 실패도 None."""
    try:
        if not ws.touches(path, rel, main):
            return None
        when = ws._git(path, "log", "-1", "--format=%cI").strip()[:16]
    except ws.WorktreeStateError:
        return None
    label = f"메인 체크아웃({branch})" if is_main else (branch or Path(path).name)
    return f"{label} · {path} · 마지막 커밋 {when}"


def overlaps(cwd: str, file_path: str) -> tuple[str, list[str]]:
    """(저장소 기준 경로, 같은 파일을 고치는 다른 곳들). 계획서가 아니면 ("", [])."""
    top = Path(ws._git(cwd, "rev-parse", "--show-toplevel").strip()).resolve()
    rel = _plan_rel(top, cwd, file_path)
    if rel is None:
        return "", []
    main = ws.default_main(cwd)
    found = (
        _touching(path, branch, i == 0, rel, main)
        for i, (path, branch) in enumerate(ws.list_worktrees(cwd))
        if Path(path).is_dir() and Path(path).resolve() != top
    )
    return rel, [line for line in found if line]


def _read_input(raw: str) -> tuple[str, str] | None:
    """(cwd, file_path) — 읽을 수 없거나 비었으면 None."""
    try:
        payload = json.loads(raw or "{}")
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
    file_path = str((payload.get("tool_input") or {}).get("file_path") or "")
    return (cwd, file_path) if cwd and file_path and Path(cwd).is_dir() else None


def main() -> int:
    got = _read_input(sys.stdin.read())
    if got is None:
        return 0
    cwd, file_path = got
    try:
        rel, others = overlaps(cwd, file_path)
    except ws.WorktreeStateError as e:
        print(f"[plan-overlap] 판정 실패 — 넘어감: {e}", file=sys.stderr)
        return 0
    if not others:
        return 0
    text = (
        f"[plan-overlap] {rel} 을 다른 곳에서도 고치는 중입니다 — 두 세션이 같은 일을 하고 있을 수 있습니다.\n"
        + "\n".join(f"  - {o}" for o in others)
        + "\n  → 그쪽 상태를 사용자에게 알리고 이어서 할지 물으십시오. 그쪽 변경을 옮기거나 지우지 않습니다."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
