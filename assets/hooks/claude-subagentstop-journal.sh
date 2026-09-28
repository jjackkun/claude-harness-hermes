#!/usr/bin/env bash
# SubagentStop hook — 하위 에이전트가 끝나면 작업 이력에 task.finished 를 남긴다.
#
# 훅 입력에 agent_id · agent_type · session_id 가 온다(V-4 확인, 2026-09-15). 덕분에
# 대화형 세션에서도 "누가(어느 직무 템플릿으로) 무엇을 맡았는지" 를 사람이 적지 않아도 찍힌다.
# 계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 7
#
# 명부 에이전트(agent_type 이 명부 slug — @agent-<slug>)면 actor 를 **명부 id** 로 적는다 — 그래야 그 에이전트의
# 이력으로 모인다(계획 2026-09-28-agent-mention-bridge 목표 5). 명부 밖은 예전처럼 서브에이전트 id.
#
# 이력이 없는 구 스키마·rollback 상태에서도 죽지 않는다(exit 0).

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
JOURNAL="$PROJECT_DIR/scripts/hermes-journal.py"
[[ -f "$JOURNAL" && -f "$PROJECT_DIR/.hermes/state.db" ]] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

EVENT="$(printf '%s' "$INPUT" | PYTHONPATH="$PROJECT_DIR/scripts" python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(1)
agent_id = data.get("agent_id") or ""
if not agent_id:
    sys.exit(1)
actor_id = agent_id
try:                                   # 명부 slug 면 명부 id — 명부·모듈이 없으면 예전 그대로
    from hermes_agent_slug import agent_by_slug
    owner = agent_by_slug(json.load(open(sys.argv[1], encoding="utf-8")), data.get("agent_type") or "")
    actor_id = owner["agent_id"] if owner else agent_id
except (ImportError, OSError, ValueError):
    pass
event = {
    "kind": "task.finished",
    "task_id": agent_id,
    "actor": "agent:" + actor_id,
    "session_id": data.get("session_id") or None,
    "claimed": "success",
    "evidence": {"template": data.get("agent_type") or "unknown"},
}
print(json.dumps(event, ensure_ascii=False))
' "$PROJECT_DIR/.hermes/agents.json" 2>/dev/null)" || exit 0
[[ -n "$EVENT" ]] || exit 0

python3 "$JOURNAL" --project "$PROJECT_DIR" emit --json "$EVENT" >/dev/null 2>&1
exit 0
