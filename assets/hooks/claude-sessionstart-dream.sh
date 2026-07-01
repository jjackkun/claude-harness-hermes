#!/usr/bin/env bash
# SessionStart hook — 헤르메스 드리밍 자동 트리거 (cron 대체).
#
# source 가 startup/resume 일 때만, 마지막 드림 이후 throttle 시간이 지났으면
# 드리밍을 setsid 백그라운드로 1회 구동한다. 세션 시작을 절대 블로킹하지 않는다.
#
# 중요: SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로, 이 훅은
#       stdout 으로 아무것도 출력하지 않는다. 모든 진단은 .hermes/hooks.log 로만.
#
# 비활성화: HERMES_DISABLED=1 (전체) 또는 HERMES_DREAM_ON_SESSION_START=0 (이 트리거만)
# 설계: docs/superpowers/specs/2026-07-01-hermes-dream-sessionstart-trigger-design.md

set -uo pipefail

# [게이트 0] 옵트아웃
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
[[ "${HERMES_DREAM_ON_SESSION_START:-1}" == "0" ]] && exit 0

# [게이트 1] python3 필수
command -v python3 >/dev/null 2>&1 || exit 0

# stdin JSON 은 훅 프로세스 안에서만 읽을 수 있으므로 여기서 먼저 읽는다.
input="$(cat 2>/dev/null || true)"

# source 추출 — jq 우선, jq 부재 시 python3 폴백 (Stop 훅 C2 패턴).
source_val=""
if command -v jq >/dev/null 2>&1; then
  source_val="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
else
  source_val="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("source", "") or "")
' 2>/dev/null || true)"
fi

# project_dir 해석 — 워크트리 경로는 메인 루트로 정규화(백그라운드 워크트리 세션이
# 워크트리 안의 없는 .hermes 를 보지 않도록, serena 훅과 동일 처리).
raw_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
project_dir="$(printf '%s' "$raw_dir" | sed 's|/.claude/worktrees/[^/]*$||')"
log_file="$project_dir/.hermes/hooks.log"

# 진단 로그는 파일로만 (stdout 오염 금지). .hermes 부재 시(비-hermes 프로젝트) 조용히 no-op.
_log() {
  [[ -d "$project_dir/.hermes" ]] || return 0
  echo "[hermes-dream-hook] $(date -Iseconds) $*" >>"$log_file" 2>/dev/null || true
}

# [게이트 2] source 게이트 — startup/resume 만. clear/compact 는 작업 중간이라 제외.
case "$source_val" in
  startup|resume) ;;
  *) _log "source=$source_val action=skip:source"; exit 0 ;;
esac

# [게이트 3] DB 존재
db_path="$project_dir/.hermes/state.db"
[[ ! -f "$db_path" ]] && { _log "source=$source_val action=skip:no-db"; exit 0; }

# [게이트 4] throttle — 마지막 드림 마커 mtime 이 throttle 시간 이내면 미실행.
throttle_hours="${HERMES_DREAM_THROTTLE_HOURS:-20}"
marker="$project_dir/.hermes/dream-last-run"
if [[ -f "$marker" ]] && [[ -n "$(find "$marker" -mmin "-$((throttle_hours * 60))" 2>/dev/null)" ]]; then
  _log "source=$source_val action=skip:throttle(${throttle_hours}h)"
  exit 0
fi

# 드림 스크립트 존재 확인 (마커 touch 前 — 스크립트 없으면 throttle 소모 안 함).
scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
[[ ! -f "$scripts_dir/hermes-dream.py" ]] && { _log "source=$source_val action=skip:no-script"; exit 0; }

# 마커 선-touch (동시 세션 이중 기동 방지). 실패해도 비차단.
mkdir -p "$project_dir/.hermes" 2>/dev/null || true
touch "$marker" 2>/dev/null || true

_log "source=$source_val action=run throttle=${throttle_hours}h"

# setsid 백그라운드 분리 — 세션 시작 비차단. 자동 실행은 dry-run(--apply 없음).
HERMES_DB_PATH="$db_path" \
HERMES_PROJECT_DIR="$project_dir" \
HERMES_SCRIPTS_DIR="$scripts_dir" \
HERMES_LOG="$log_file" \
setsid bash -c '
  timeout 600 python3 "$HERMES_SCRIPTS_DIR/hermes-dream.py" \
    --db "$HERMES_DB_PATH" \
    --project-dir "$HERMES_PROJECT_DIR" \
    >>"$HERMES_LOG" 2>&1 || true
  echo "[hermes-dream-hook] dream done $(date -Iseconds)" >>"$HERMES_LOG"
' </dev/null >/dev/null 2>&1 &

exit 0
