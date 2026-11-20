#!/usr/bin/env bash
# SessionStart hook — main 에 안 들어간 worktree 목록을 세션 시작에 한 번 알린다(G3). 막지 않는다.
# 판정은 worktree_notice.py 가 한다. 이 파일은 stdin·끄기·시간 상한·로그만 맡는다. 판정 실패·시간 초과는 조용히 통과한다.
# 끄기: WORKTREE_NOTICE_DISABLED=1
# 계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (G3)

set -uo pipefail

[[ "${WORKTREE_NOTICE_DISABLED:-0}" == "1" ]] && exit 0

CHECK="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/worktree_notice.py"
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
[[ $? -eq 124 ]] && echo "[worktree-notice] ${TIME_LIMIT}초 넘어 통과" >>"$log"
exit 0
