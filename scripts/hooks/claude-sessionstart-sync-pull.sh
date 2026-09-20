#!/usr/bin/env bash
# SessionStart hook — refs/hermes/sync 를 받아 새 조각을 복호·적재한다 (계획 3 목표 8·14).
#
# 순서: 이식 정책 확인 → age 확인 → hermes-sync.py pull → 새 조각이 있으면 재색인 훅이
# (같은 SessionStart 에서 뒤에 돌며) session_history 로 올린다. 열쇠가 없으면 H-10 안내를
# 로그에 남기고 push 는 보류된다(push 는 Stop 훅에서 같은 판정을 거친다).
#
# 중요: SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 stdout 무출력.
#       모든 진단은 .hermes/hooks.log 로만. 세션 시작을 절대 블로킹하지 않는다(exit 0).
#       age 가 없는 컴퓨터(zeroday 동료)는 한 줄만 남기고 건너뛴다.
# 비활성화: HERMES_DISABLED=1 · HERMES_SYNC_ON_SESSION_START=0

set -uo pipefail
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0
[[ "${HERMES_SYNC_ON_SESSION_START:-1}" == "0" ]] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
scripts_dir="$project_dir/scripts"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[hermes-sync-pull] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }

[[ -f "$scripts_dir/hermes-sync.py" ]] || exit 0
[[ -f "$project_dir/.hermes/state.db" ]] || { _log "action=skip:no-db"; exit 0; }
[[ -f "$project_dir/.hermes/sync.json" ]] || { _log "action=skip:sync-off"; exit 0; }
if ! command -v age >/dev/null 2>&1; then
  _log "action=skip:no-age — age 가 없어 pull 을 건너뜁니다(설치기가 깐다: 공장에서 bash update-all.sh)"
  exit 0
fi

timeout "${HERMES_SYNC_TIMEOUT:-60}" python3 "$scripts_dir/hermes-sync.py" --project "$project_dir" pull \
  >>"$log" 2>&1 || _log "action=pull-failed rc=$?"
exit 0
