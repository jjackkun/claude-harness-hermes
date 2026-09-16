#!/usr/bin/env bash
# SessionStart hook — 소환된 세션(HERMES_SUMMON_NONCE)의 토큰을 검증한다 (계획 4 목표 6·16).
#
# 짝 없음(missing)·다른 에이전트(mismatch)·재사용(used)·만료(expired)면 판정 파일에
# unverified:<사유> 를 남기고 로그에 경고한다. 이력 기록기는 그 세션의 행위자를
# system:unverified-session 으로 찍는다. **세션은 멈추지 않는다** — 훅 오류 하나로 루프
# 전체가 서면 안 된다(계획 §6). ok 면 토큰을 사용 표시하고 pending 파일을 지운다.
#
# 소환되지 않은 보통 세션(환경변수 없음)은 아무것도 하지 않는다.
# summons 표가 없는 구 스키마 DB 는 첫 실행 때 만든다(목표 16).
# 중요: SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 stdout 무출력.

set -uo pipefail
[[ -n "${HERMES_SUMMON_NONCE:-}" ]] || exit 0

project_dir="${CLAUDE_PROJECT_DIR:-${HERMES_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
scripts_dir="$project_dir/scripts"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[summons-verify] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }

[[ -f "$scripts_dir/hermes_summons.py" && -f "$project_dir/.hermes/state.db" ]] || { _log "skip:no-module-or-db"; exit 0; }
INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: print("")' 2>/dev/null)"

VERDICT="$(PYTHONPATH="$scripts_dir" python3 - "$project_dir" "$HERMES_SUMMON_NONCE" "${HERMES_AGENT_ID:-}" "$SESSION_ID" <<'PY' 2>/dev/null
import os, sqlite3, sys
from hermes_summons import consume, verify, write_verdict
project, nonce, agent_id, session_id = sys.argv[1:5]
con = sqlite3.connect(os.path.join(project, ".hermes", "state.db"))
ok, reason = verify(con, nonce, agent_id)
verdict = "ok" if ok else f"unverified:{reason}"
if ok:
    consume(con, project, nonce, session_id)
con.close()
write_verdict(project, nonce, verdict)
print(verdict)
PY
)" || VERDICT="unverified:hook-error"

if [[ "$VERDICT" == "ok" ]]; then
  _log "ok agent=${HERMES_AGENT_ID:-} nonce=${HERMES_SUMMON_NONCE:0:8}…"
else
  _log "WARN $VERDICT agent=${HERMES_AGENT_ID:-} nonce=${HERMES_SUMMON_NONCE:0:8}… → 이 세션의 행위자는 system:unverified-session 으로 기록된다"
  echo "[summons-verify WARN] 소환 토큰 검증 실패($VERDICT) — 이 세션의 이력은 system:unverified-session 으로 남습니다." >&2
fi
exit 0
