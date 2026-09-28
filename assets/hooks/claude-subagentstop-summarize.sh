#!/usr/bin/env bash
# SubagentStop hook — 명부 에이전트를 @ 로 부른 대화를 그 에이전트 몫으로 요약한다(C-29).
# (계획 2026-09-28-agent-conversation-memory 목표 3)
#
# 메인 세션 요약에는 다른 이야기가 섞이므로 나누지 않고, 서브에이전트 자신의 기록(agent_transcript_path — 입력에 온다, 실측)을
# 같은 요약기(hermes-summarize.py)로 따로 요약해 session_id = sub:<서브에이전트 id>, agent_id = 명부 id 로 저장한다.
# 요약하는 호출: SubagentStart 기록(task.assigned task_id=<서브에이전트 id> match=mention)이 있는 것만 —
#   방 안에서는 Claude Code 내부 보조(입력 추천·/btw)도 agent_type = 방 slug 로 SubagentStop 이 오지만 Start 기록이 없다.
# 요약은 haiku 호출이라 setsid 백그라운드로 던진다(retrospective 훅과 같은 방식) — SubagentStop 이 기다리지 않는다.
#   HERMES_SUMMARY_FOREGROUND=1 이면 앞에서 돈다(시험용).
# 어떤 경우에도 exit 0 · stdout 무출력.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
SCRIPTS="$PROJECT_DIR/scripts"
DB="$PROJECT_DIR/.hermes/state.db"
[[ -f "$DB" && -f "$SCRIPTS/hermes-summarize.py" && -f "$SCRIPTS/hermes_summary_owner.py" ]] || exit 0

# 서브에이전트 id · 기록 경로 · 명부 id(Start 기록에서). 셋 중 하나라도 없으면 요약하지 않는다.
PLAN="$(printf '%s' "$INPUT" | PYTHONPATH="$SCRIPTS" python3 -c '
import json, os, re, sys
from hermes_summary_owner import mention_owner_id
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
sub, path = str(d.get("agent_id") or ""), str(d.get("agent_transcript_path") or "")
if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", sub) or "\n" in path or not os.path.isfile(path):   # 줄바꿈 경로는 줄 단위 전달을 흐트린다
    sys.exit(0)
owner = mention_owner_id(sys.argv[1], sub)
if owner:
    print(sub); print(path); print(owner)
' "$PROJECT_DIR" 2>/dev/null)"
[[ -n "$PLAN" ]] || exit 0
SUB="$(sed -n 1p <<<"$PLAN")"; TRANSCRIPT="$(sed -n 2p <<<"$PLAN")"; OWNER="$(sed -n 3p <<<"$PLAN")"

run() {
  timeout 60 python3 "$SCRIPTS/hermes-summarize.py" --db "$DB" --transcript "$TRANSCRIPT" \
    --session-id "sub:$SUB" --agent-id "$OWNER" --project-dir "$PROJECT_DIR" \
    >>"$PROJECT_DIR/.hermes/hooks.log" 2>&1 || true
}
if [[ "${HERMES_SUMMARY_FOREGROUND:-0}" == 1 ]]; then
  run
else
  export DB TRANSCRIPT SUB OWNER PROJECT_DIR SCRIPTS CLAUDE_PROJECT_DIR="$PROJECT_DIR"
  setsid bash -c "$(declare -f run); run" </dev/null >/dev/null 2>&1 &
fi
exit 0
