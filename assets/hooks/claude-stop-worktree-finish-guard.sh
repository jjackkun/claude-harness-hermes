#!/usr/bin/env bash
# Stop hook — 계획서를 completed 로 옮겼는데 main 에 합치지 않은 worktree 세션의 끝내기를 한 번 막는다(G2).
#
# 데스크톱 앱이 만든 worktree 에서 일을 끝내고도 main 에 합치지 않아, 다른 세션이 같은 일을 다시 했다
# (2026-11-19 jj-agent-room 결재 A3). 판정은 worktree_finish_guard.py 가 하고, 이 파일은 stdin·끄기·시간 상한·로그만 맡는다.
# 통과(막지 않음): 끄기 스위치 · python3 없음 · 판정 오류 · 시간 초과 — 판정 실패로 세션을 막지 않는다.
# 끄기: WORKTREE_FINISH_GUARD_DISABLED=1
# 계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (G2)

set -uo pipefail

[[ "${WORKTREE_FINISH_GUARD_DISABLED:-0}" == "1" ]] && exit 0

CHECK="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/worktree_finish_guard.py"
TIME_LIMIT=5

input="$(cat 2>/dev/null || true)"
command -v python3 >/dev/null 2>&1 || exit 0
[[ -f "$CHECK" ]] || exit 0

_timeout=()
command -v timeout >/dev/null 2>&1 && _timeout=(timeout "$TIME_LIMIT")
log=/dev/null
[[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "$CLAUDE_PROJECT_DIR" ]] && mkdir -p "$CLAUDE_PROJECT_DIR/.hermes" 2>/dev/null \
  && log="$CLAUDE_PROJECT_DIR/.hermes/hooks.log"  # worktree 에는 .hermes 가 없다 — 만들어서라도 남긴다(코드 리뷰 H1)

printf '%s' "$input" | ${_timeout[@]+"${_timeout[@]}"} python3 "$CHECK" 2>>"$log"
[[ $? -eq 124 ]] && echo "[worktree-finish-guard] ${TIME_LIMIT}초 넘어 통과" >>"$log"
exit 0
