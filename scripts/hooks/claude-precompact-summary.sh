#!/usr/bin/env bash
# PreCompact hook — 컨텍스트 압축 직전에 세션 저장 + 5슬롯 롤링 요약을 한 번 돌린다.
#
# 왜: 세션 기억(`session_summary`)은 Stop 훅에서만 쓰였다. 긴 세션이 압축된 뒤 그 세션이
# 비정상 종료되면 압축 시점까지의 결정·미완 작업은 어디에도 남지 않는다(계획 2026-09-21-precompact-summary).
#
# 무엇을 하지 않는가:
#   - 새 요약 형식을 만들지 않는다. Stop 훅과 **같은** 도구(hermes-save-session → hermes-summarize)를 부른다.
#   - 결정화·드리밍은 부르지 않는다 — 압축은 한 세션에 여러 번 일어날 수 있고 그때마다 모델 호출이 붙으면 크레딧이 샌다.
#   - `trigger`(manual/auto)로 동작을 가르지 않는다. 둘 다 "여기서 컨텍스트가 잘린다" 는 같은 사건이다.
#
# 대화를 막지 않는다: 입력만 읽고 즉시 rc 0, 처리는 setsid 백그라운드(Stop 훅과 같은 방식).
set -uo pipefail

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && exit 0

# stdin JSON 에서 transcript_path·session_id 를 한 번에 꺼낸다(jq 없으면 python3).
transcript=""
session_id=""
if command -v jq >/dev/null 2>&1; then
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  parsed="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("transcript_path", "") or "")
print(d.get("session_id", "") or "")
' 2>/dev/null || true)"
  transcript="$(printf '%s\n' "$parsed" | sed -n 1p)"
  session_id="$(printf '%s\n' "$parsed" | sed -n 2p)"
fi

[[ -z "$transcript" || ! -f "$transcript" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
db_path="$project_dir/.hermes/state.db"
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
[[ -f "$db_path" ]] || exit 0

# CLAUDE_PROJECT_DIR 를 반드시 넘긴다 — 마스킹(hermes_redact)이 `.env` 정답지를 찾는 기준이다.
# 없으면 cwd 로 폴백해 값 기반 마스킹이 조용히 무력화된다(Stop 훅 주석과 같은 이유).
HERMES_TRANSCRIPT="$transcript" \
HERMES_SESSION_ID="$session_id" \
HERMES_PROJECT_DIR="$project_dir" \
CLAUDE_PROJECT_DIR="$project_dir" \
HERMES_DB_PATH="$db_path" \
HERMES_SCRIPTS_DIR="$scripts_dir" \
HERMES_LOG="$project_dir/.hermes/hooks.log" \
setsid bash -c '
  echo "[precompact] $(date "+%F %T") session=$HERMES_SESSION_ID" >>"$HERMES_LOG" 2>/dev/null
  timeout 20 python3 "$HERMES_SCRIPTS_DIR/hermes-save-session.py" \
    --db "$HERMES_DB_PATH" \
    --transcript "$HERMES_TRANSCRIPT" \
    --project-id "$(basename "$HERMES_PROJECT_DIR")" \
    --session-id "$HERMES_SESSION_ID" \
    >>"$HERMES_LOG" 2>&1 || true
  timeout 60 python3 "$HERMES_SCRIPTS_DIR/hermes-summarize.py" \
    --db "$HERMES_DB_PATH" \
    --transcript "$HERMES_TRANSCRIPT" \
    --project-id "$(basename "$HERMES_PROJECT_DIR")" \
    --session-id "$HERMES_SESSION_ID" \
    --project-dir "$HERMES_PROJECT_DIR" \
    >>"$HERMES_LOG" 2>&1 || true
' </dev/null >/dev/null 2>&1 &

exit 0
