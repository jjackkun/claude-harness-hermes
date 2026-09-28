#!/usr/bin/env bash
# SessionStart hook — 소환된 에이전트(HERMES_AGENT_ID)의 정체성 폴더를 읽어 세션에 넣는다.
# (계획 2026-09-17-summon-soul-injection 목표 1~4; 설계 creation-and-organization.md:20
#  "소환될 때마다 그 폴더를 읽고 출근하는 존재")
#
# 두 번째 길 — 사람이 연 방(`claude --agent <slug>`, hermes-chat, 계획 2026-09-28-hermes-chat 목표 1):
# HERMES_AGENT_ID 가 없으면 입력 JSON 의 agent_type(hooks.md "present when you start Claude Code with
# `claude --agent <name>`") 을 slug 로 보고 명부 id 를 찾는다. 소환 경로(환경변수)가 있으면 그쪽이 우선.
# source 를 가리지 않는다 — startup·resume·compact 모두 넣어야 `--resume` 뒤에도 정체성이 남는다.
#
# SessionStart 훅의 stdout 은 세션 문맥으로 주입된다 — 이 훅은 그 성질을 **쓰는** 훅이다.
# 다른 SessionStart 훅(summons-verify 등)이 stdout 무출력인 이유와 같은 이유로, 여기서는
# 정체성 말고는 아무것도 stdout 에 내지 않는다.
#
# 넣는 것: 머리 한 줄 + SOUL.md(≤4,096 B) + MEMORY.md(≤4,096 B). 합 8,192 B 는 이 프로젝트의
# R-out 임계(claude-posttooluse-output-budget.sh)와 같은 값 — "한 번에 문맥에 넣기엔 많다" 를
# 실측으로 정한 유일한 수치라 새 숫자를 만들지 않는다. 넘치면 자르고 원문 경로를 알린다.
#
# 넣지 않는 경우(전부 stdout 무출력·exit 0): 환경변수도 명부 slug 인 agent_type 도 없음 · id 꼴이 아님 · 폴더 없음(main 포함) ·
# 명부에서 retired(설계 skill-layers.md "은퇴자는 주입에서 빠진다") · 명부를 못 읽음(은퇴 여부를
# 확인 못 하면 넣지 않는다). 훅 오류 하나로 세션이 서면 안 된다 — 어떤 경우에도 exit 0.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
project_dir="${CLAUDE_PROJECT_DIR:-${HERMES_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[agent-soul] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }

HERMES_AGENT_ID="${HERMES_AGENT_ID:-}"
if [[ -z "$HERMES_AGENT_ID" ]]; then
  # --agent 방: agent_type(slug) → 명부 id. 명부 밖(공장·내장)·은퇴자는 빈 값 — 보통 세션과 같이 조용히 끝낸다.
  command -v python3 >/dev/null 2>&1 || exit 0
  slug="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_type") or "")' 2>/dev/null)"
  [[ "$slug" =~ ^[a-z][a-z0-9-]{1,39}$ ]] || exit 0
  lookup_dir="$project_dir/scripts"
  [[ -f "$lookup_dir/hermes_agent_slug.py" ]] || lookup_dir="$(cd "$(dirname "$0")/../../scripts" 2>/dev/null && pwd)"
  HERMES_AGENT_ID="$(PYTHONPATH="$lookup_dir" python3 -c '
import json, sys
from hermes_agent_slug import agent_by_slug
a = agent_by_slug(json.load(open(sys.argv[1], encoding="utf-8")), sys.argv[2])
print(a["agent_id"] if a and a.get("status") != "retired" else "")' "$project_dir/.hermes/agents.json" "$slug" 2>/dev/null)"
  [[ -n "$HERMES_AGENT_ID" ]] || exit 0
  _log "room slug=$slug agent=$HERMES_AGENT_ID"
fi

[[ "$HERMES_AGENT_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
  || { _log "skip:not-an-id ${HERMES_AGENT_ID:0:20}"; exit 0; }
agent_dir="$project_dir/.hermes/agents/$HERMES_AGENT_ID"
[[ -d "$agent_dir" ]] || { _log "skip:no-identity-dir $HERMES_AGENT_ID"; exit 0; }
command -v python3 >/dev/null 2>&1 || { _log "skip:no-python3"; exit 0; }

# 읽기 전에 MEMORY.md 를 기억 이벤트에서 다시 만든다(계획 agent-memory-roundtrip 목표 1) — pull 로 들어온 기억도 이 자리에서 보인다.
# DB 나 memory_events 가 없으면 스크립트가 스스로 건너뛴다. 실패해도 주입은 계속한다.
scripts_dir="$project_dir/scripts"
[[ -f "$scripts_dir/hermes-agent.py" ]] || scripts_dir="$(cd "$(dirname "$0")/../../scripts" 2>/dev/null && pwd)"
if [[ -f "$scripts_dir/hermes-agent.py" ]]; then
  rerr="$(mktemp 2>/dev/null || echo /dev/null)"
  python3 "$scripts_dir/hermes-agent.py" --project "$project_dir" refresh-memory "$HERMES_AGENT_ID" >/dev/null 2>"$rerr" \
    || _log "WARN refresh-memory 실패 agent=$HERMES_AGENT_ID: $(tr '\n' ' ' <"$rerr" 2>/dev/null)"
  [[ "$rerr" != /dev/null ]] && rm -f "$rerr"
fi

# 명부 확인 + 파일 읽기 + 자르기는 렌더러 한 프로세스에서(서브에이전트 훅과 같은 본문 — 계획 2026-09-28-agent-mention-bridge 목표 4).
errf="$(mktemp 2>/dev/null || echo /dev/null)"
SOUL_CAP="${HERMES_SOUL_CAP:-4096}" MEMORY_CAP="${HERMES_MEMORY_CAP:-4096}" HERMES_SCRIPTS_DIR="${scripts_dir:-$project_dir/scripts}" \
python3 "${scripts_dir:-$project_dir/scripts}/hermes_soul_render.py" "$project_dir" "$HERMES_AGENT_ID" 2>"$errf" \
  || { _log "WARN hook-error agent=$HERMES_AGENT_ID → 정체성 없이 시작"; }
# 경고는 세션(stderr)과 로그 양쪽에 — 세션은 이유를 보고, 로그는 나중에 센다.
if [[ -s "$errf" ]]; then cat "$errf" >&2; _log "WARN $(tr '\n' ' ' <"$errf")"; else _log "ok agent=$HERMES_AGENT_ID"; fi
[[ "$errf" != /dev/null ]] && rm -f "$errf"
exit 0
