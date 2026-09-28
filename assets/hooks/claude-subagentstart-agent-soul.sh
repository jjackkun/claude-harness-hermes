#!/usr/bin/env bash
# SubagentStart hook — @agent-<slug> 로 불린 명부 에이전트에게 정체성(SOUL.md)과 기억을 넣는다.
# (계획 2026-09-28-agent-mention-bridge 목표 3)
#
# .claude/agents/<slug>.md 는 이름·설명만 가진 얇은 파일이다(hermes_mention_file.py). 정체성은 파일에
# 굳히지 않고 부를 때마다 여기서 최신본을 넣는다 — 세션 시작 훅(claude-sessionstart-agent-soul.sh)과
# **같은 렌더러**(hermes_soul_render.py)를 써서 두 경로의 본문이 갈라지지 않는다.
#
# 공식 문서(hooks.md SubagentStart): "can't block subagent creation, but they can inject context" —
# stdout 의 hookSpecificOutput.additionalContext 가 서브에이전트 첫 프롬프트 앞에 들어간다.
# 입력 agent_type 은 에이전트 파일 frontmatter 의 name(= slug) 이다.
#
# 넣지 않는 경우(전부 stdout 무출력·exit 0): 입력이 JSON 아님 · slug 꼴 아님(내장 Explore 등) ·
# 명부에 없는 slug(공장 에이전트) · 은퇴자 · 명부를 못 읽음. 훅 오류로 서브에이전트가 서면 안 된다.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
project_dir="${CLAUDE_PROJECT_DIR:-${HERMES_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
log="$project_dir/.hermes/hooks.log"
_log() { mkdir -p "$(dirname "$log")"; printf '[subagent-soul] %s %s\n' "$(date -Is)" "$*" >>"$log" 2>/dev/null || true; }
command -v python3 >/dev/null 2>&1 || exit 0

slug="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("agent_type") or "")' 2>/dev/null)"
[[ "$slug" =~ ^[a-z][a-z0-9-]{1,39}$ ]] || exit 0
scripts_dir="$project_dir/scripts"
[[ -f "$scripts_dir/hermes_soul_render.py" ]] || scripts_dir="$(cd "$(dirname "$0")/../../scripts" 2>/dev/null && pwd)"
[[ -f "$scripts_dir/hermes_soul_render.py" ]] || { _log "skip:no-renderer $slug"; exit 0; }

# slug → 명부 id. 명부 밖(공장·내장)·은퇴자는 빈 값 — 조용히 끝낸다.
agent_id="$(PYTHONPATH="$scripts_dir" python3 -c '
import json, sys
from hermes_agent_slug import agent_by_slug
a = agent_by_slug(json.load(open(sys.argv[1], encoding="utf-8")), sys.argv[2])
print(a["agent_id"] if a and a.get("status") != "retired" else "")' "$project_dir/.hermes/agents.json" "$slug" 2>/dev/null)"
[[ -n "$agent_id" ]] || exit 0

# 읽기 전에 기억 이벤트에서 MEMORY.md 를 다시 만든다 — 세션 시작 훅과 같은 순서. 실패해도 주입은 계속.
if [[ -f "$scripts_dir/hermes-agent.py" ]]; then
  python3 "$scripts_dir/hermes-agent.py" --project "$project_dir" refresh-memory "$agent_id" >/dev/null 2>&1 \
    || _log "WARN refresh-memory 실패 agent=$agent_id"
fi

errf="$(mktemp 2>/dev/null || echo /dev/null)"
text="$(SOUL_CAP="${HERMES_SOUL_CAP:-4096}" MEMORY_CAP="${HERMES_MEMORY_CAP:-4096}" HERMES_SCRIPTS_DIR="$scripts_dir" \
  python3 "$scripts_dir/hermes_soul_render.py" "$project_dir" "$agent_id" 2>"$errf")" \
  || _log "WARN render-error agent=$agent_id"
if [[ -s "$errf" ]]; then _log "WARN $slug $(tr '\n' ' ' <"$errf")"; fi
[[ "$errf" != /dev/null ]] && rm -f "$errf"
[[ -n "$text" ]] || { _log "skip:empty $slug"; exit 0; }

printf '%s\n' "$text" | python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SubagentStart",
                  "additionalContext": sys.stdin.read()}}, ensure_ascii=False))' \
  && _log "ok $slug agent=$agent_id"
exit 0
