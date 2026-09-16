#!/usr/bin/env bash
# SessionStart hook — 기한 지난 미시작 봉투를 만료 처리한다 (계획 4 목표 11, RV-08).
#
# 시간 데몬이 아니라 세션 시작 때 돈다(cron 없이). 기한(expires_at)이 지났는데 task.started 도
# handoff.question 도 없는 봉투에 handoff.expired 를 붙인다. expires_at 없는 봉투는 만료 없음.
# journal_events 없는 구 스키마·rollback 상태에서도 죽지 않는다(exit 0).
# 중요: SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 stdout 무출력.

set -uo pipefail
[[ "${HERMES_DISABLED:-0}" == "1" ]] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
scripts_dir="$project_dir/scripts"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[handoff-expiry] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }

[[ -f "$scripts_dir/hermes_handoff.py" && -f "$project_dir/.hermes/state.db" ]] || exit 0

N="$(PYTHONPATH="$scripts_dir" python3 - "$project_dir" <<'PY' 2>>"$log"
import os, sys
project = sys.argv[1]
db = os.path.join(project, ".hermes", "state.db")
try:
    from hermes_handoff import check_expired
    print(check_expired(db, project))
except Exception as exc:
    print(0)
    print(f"[handoff-expiry] skip: {exc}", file=sys.stderr)
PY
)" || N=0
[[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || exit 0
_log "만료 처리 ${N}건"
echo "[handoff-expiry] 기한 지난 인계 봉투 ${N}건을 만료 처리했습니다 (handoff.expired)." >&2
exit 0
