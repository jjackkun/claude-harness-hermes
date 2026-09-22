#!/usr/bin/env bash
# SessionStart hook — 사용자 성향(승인됐거나 자동 활성 기준을 넘은 것)을 세션에 넣는다.
# (계획 2026-09-22-user-persona-distill 목표 4)
#
# SessionStart 훅의 stdout 은 세션 문맥으로 주입된다. 넣는 것은 `hermes-persona.py render` 의 글 하나 —
# 상한 4,096 B(SOUL 주입과 같은 값)와 "승인 대기 N건" 알림 줄은 render 가 책임진다.
# 소환된 에이전트 세션(HERMES_AGENT_ID)에도 넣는다 — 성향은 에이전트가 아니라 일을 맡긴 사람의 것이다.
#
# 넣지 않는 경우(전부 stdout 무출력·exit 0): python3 없음 · 스크립트 없음 · 성향 DB 없음 · render 실패.
# 훅 오류 하나로 세션이 서면 안 된다 — 어떤 경우에도 exit 0.
set -uo pipefail
cat >/dev/null 2>&1 || true   # stdin(JSON)을 비운다 — 쓰지 않지만 SIGPIPE 를 막는다
project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")" 2>/dev/null; printf '[persona] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }

command -v python3 >/dev/null 2>&1 || exit 0
cli="$project_dir/scripts/hermes-persona.py"
[[ -f "$cli" ]] || exit 0
db="${HERMES_PERSONA_DB:-$HOME/.hermes/global.db}"
[[ -f "$db" ]] || exit 0

err="$(mktemp 2>/dev/null || echo /dev/null)"
# 상한 5초 — render 실측 0.04초, sqlite 기본 잠금 대기(5초)와 같은 값. 넘으면 잠금·파일시스템 문제라 주입을 건너뛴다.
runner=(python3); command -v timeout >/dev/null 2>&1 && runner=(timeout 5 python3)
out="$("${runner[@]}" "$cli" render --db "$db" 2>"$err")" || { _log "WARN render 실패·시간 초과: $(tr '\n' ' ' <"$err" 2>/dev/null)"; out=""; }
[[ "$err" != /dev/null ]] && rm -f "$err"
[[ -n "$out" ]] && printf '%s\n' "$out"
exit 0
