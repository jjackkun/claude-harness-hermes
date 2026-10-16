#!/usr/bin/env bash
# Stop hook — 마지막 답변이 영어 위주면 끝내기를 막고 "한국어로 다시 써라" 를 Claude 에게 돌려준다.
#
# 기억(메모리)은 참고라 긴 작업 끝 보고에서 놓친다 — 같은 날 두 번 어긴 뒤 강제 장치로 만들었다.
# 판정은 korean_reply_check.py 가 한다. 이 파일은 stdin 읽기·끄기 스위치·시간 상한·로그만 맡는다.
#
# 통과(막지 않음): 끄기 스위치 · python3 없음 · 판정 오류 · 시간 초과 — 판정 실패로 세션을 막지 않는다.
# stdin 이 비어 와도(형제 훅 stdin 경쟁) 판정 모듈이 최근 transcript 로 대신한다.
# 끄기: KOREAN_GUARD_DISABLED=1
# 계획: docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md

set -uo pipefail

[[ "${KOREAN_GUARD_DISABLED:-0}" == "1" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
CHECK="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/korean_reply_check.py"
LOG="$PROJECT_DIR/.hermes/hooks.log"
TIME_LIMIT=2

# stdin 은 훅 프로세스 안에서만 읽을 수 있으므로 여기서 먼저 읽는다.
input="$(cat 2>/dev/null || true)"

command -v python3 >/dev/null 2>&1 || exit 0
[[ -f "$CHECK" ]] || exit 0

_timeout=()
command -v timeout >/dev/null 2>&1 && _timeout=(timeout "$TIME_LIMIT")

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
printf '%s' "$input" | CLAUDE_PROJECT_DIR="$PROJECT_DIR" ${_timeout[@]+"${_timeout[@]}"} python3 "$CHECK" 2>>"$LOG"
exit 0
