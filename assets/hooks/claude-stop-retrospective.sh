#!/usr/bin/env bash
# Stop hook — 헤르메스 러닝 루프 (Retrospective).
#
# 동작: 세션 종료 시 transcript 를 SQLite 에 저장하고,
#       반복 패턴 3회 이상 감지 시 결정화 세션을 자동 생성한다.
#
# 비차단 — 항상 exit 0. 오류는 .hermes/hooks.log 에 기록.
# 비활성화: env HERMES_DISABLED=1

set -uo pipefail

[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0

command -v python3 >/dev/null 2>&1 || exit 0

# stdin 은 훅 프로세스 안에서만 읽을 수 있으므로 여기서 먼저 읽는다.
input="$(cat 2>/dev/null || true)"

# stdin JSON 에서 transcript_path 와 session_id 를 한 번에 추출한다.
# jq 우선, jq 부재 시 python3 폴백 (C2).
transcript=""
session_id=""
if command -v jq >/dev/null 2>&1; then
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
else
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

project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
db_path="$project_dir/.hermes/state.db"
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"

[[ ! -f "$db_path" ]] && exit 0

# 이후 모든 처리를 setsid 백그라운드로 위임
# - setsid: WSL2 에서 Claude Code 의 process group 감시·파이프 EOF 대기를 완전히 벗어남
# - </dev/null >/dev/null: stdin/stdout 분리. stderr 는 진단용 로그 파일로 보존 (M2).
HERMES_TRANSCRIPT="$transcript" \
HERMES_SESSION_ID="$session_id" \
HERMES_PROJECT_DIR="$project_dir" \
HERMES_DB_PATH="$db_path" \
HERMES_SCRIPTS_DIR="$scripts_dir" \
HERMES_LOG="$project_dir/.hermes/hooks.log" \
setsid bash -c '
  # 1. 세션 저장 + 패턴 집계 (--session-id 전달 — 같은 세션 재저장 시 교체, C2)
  save_output=$(timeout 20 python3 "$HERMES_SCRIPTS_DIR/hermes-save-session.py" \
    --db "$HERMES_DB_PATH" \
    --transcript "$HERMES_TRANSCRIPT" \
    --project-id "$(basename "$HERMES_PROJECT_DIR")" \
    --session-id "$HERMES_SESSION_ID" \
    2>>"$HERMES_LOG" || true)

  # 1.5 롤링 요약 (핑퐁 델타 기반 5슬롯 갱신 + 옵시디언 노트 내보내기)
  timeout 60 python3 "$HERMES_SCRIPTS_DIR/hermes-summarize.py" \
    --db "$HERMES_DB_PATH" \
    --transcript "$HERMES_TRANSCRIPT" \
    --project-id "$(basename "$HERMES_PROJECT_DIR")" \
    --session-id "$HERMES_SESSION_ID" \
    --project-dir "$HERMES_PROJECT_DIR" \
    >>"$HERMES_LOG" 2>&1 || true

  # 2. 결정화
  crystallize_keys=$(printf "%s" "$save_output" | grep "^\[hermes\] CRYSTALLIZE:" | sed "s/\[hermes\] CRYSTALLIZE://" | head -1)
  if [[ -n "$crystallize_keys" ]]; then
    python3 "$HERMES_SCRIPTS_DIR/hermes-crystallize.py" \
      --db "$HERMES_DB_PATH" \
      --crystallize "$crystallize_keys" \
      --project-dir "$HERMES_PROJECT_DIR" \
      >>"$HERMES_LOG" 2>&1 || true
  fi

  # 3. 진화
  evolve_lines=$(printf "%s" "$save_output" | grep "^\[hermes\] EVOLVE:" | sed "s/\[hermes\] EVOLVE://" | head -2)
  if [[ -n "$evolve_lines" ]]; then
    _evolve_input=$(mktemp /tmp/hermes-evolve-input-XXXXXX)
    printf "%s\n" "$evolve_lines" > "$_evolve_input"
    while IFS= read -r evolve_line; do
      [[ -z "$evolve_line" ]] && continue
      keyword="${evolve_line%%|*}"
      feedback="${evolve_line#*|}"
      python3 "$HERMES_SCRIPTS_DIR/hermes-evolve-skill.py" \
        --db "$HERMES_DB_PATH" \
        --keyword "$keyword" \
        --feedback "$feedback" \
        >>"$HERMES_LOG" 2>&1 || true
    done < "$_evolve_input"
    rm -f "$_evolve_input"
  fi

  # 4. 결과 상관 — 주입 원장 ↔ transcript 편집경로 대조
  timeout 30 python3 "$HERMES_SCRIPTS_DIR/hermes-correlate.py" \
    --db "$HERMES_DB_PATH" \
    --transcript "$HERMES_TRANSCRIPT" \
    --session-id "$HERMES_SESSION_ID" \
    >>"$HERMES_LOG" 2>&1 || true

  # 5. 정리 — 측정 신호 기반 강등·톰브스톤
  timeout 30 python3 "$HERMES_SCRIPTS_DIR/hermes-prune.py" \
    --db "$HERMES_DB_PATH" \
    >>"$HERMES_LOG" 2>&1 || true

  # 6. 대화 원본 git 텍스트 export (다른 컴퓨터 이식용)
  if [[ -n "$HERMES_SESSION_ID" ]]; then
    timeout 30 python3 "$HERMES_SCRIPTS_DIR/hermes-export-history.py" \
      --db "$HERMES_DB_PATH" \
      --project "$HERMES_PROJECT_DIR" \
      --session "$HERMES_SESSION_ID" \
      >>"$HERMES_LOG" 2>&1 || true
  fi

  # 완료 마커 — 진단 및 테스트의 완료 대기용
  echo "[hermes] hook done: session=$HERMES_SESSION_ID $(date -Iseconds)" >>"$HERMES_LOG"
' </dev/null >/dev/null 2>&1 &

exit 0
