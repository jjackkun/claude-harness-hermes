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
# 단, **같은 agent_id 의 SubagentStart(task.assigned)가 있을 때만**이다(계획 2026-09-28-hermes-chat 목표 2).
# `claude --agent <slug>` 방에서는 Claude Code 내부 보조 호출(입력 추천·/btw)이 agent_type=<방 주인 slug> 로
# Stop 에만 온다 — 이것을 명부 에이전트의 호출로 적으면 횟수가 부풀려진다. Start 가 없으면 내부 보조(template=claude)로 적는다.
#
# 이력이 없는 구 스키마·rollback 상태에서도 죽지 않는다(exit 0).

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
JOURNAL="$PROJECT_DIR/scripts/hermes-journal.py"
[[ -f "$JOURNAL" && -f "$PROJECT_DIR/.hermes/state.db" ]] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

EVENT="$(printf '%s' "$INPUT" | PYTHONPATH="$PROJECT_DIR/scripts" python3 -c '
import json, sqlite3, sys
try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(1)
agent_id = data.get("agent_id") or ""
if not agent_id:
    sys.exit(1)


def started(db, task_id):
    """이 agent_id 의 task.assigned(SubagentStart 훅)가 이력에 있나. 판정 불가(DB·표 문제)면 True —
    예전 동작(명부 id 로 적기)을 지켜 이력을 잃지 않는다."""
    try:
        con = sqlite3.connect(db)
        try:
            # ⚠️ 이 파이썬은 bash 작은따옴표 안이다 — SQL 에 작은따옴표를 쓰면 bash 가 벗겨 열 이름이 된다.
            return con.execute("SELECT 1 FROM journal_events WHERE task_id=? AND kind=? LIMIT 1",
                               (task_id, "task.assigned")).fetchone() is not None
        finally:
            con.close()
    except sqlite3.Error:
        return True


actor_id = agent_id
template = data.get("agent_type") or "unknown"
try:                                   # 명부 slug 면 명부 id — 명부·모듈이 없으면 예전 그대로
    from hermes_agent_slug import agent_by_slug
    owner = agent_by_slug(json.load(open(sys.argv[1], encoding="utf-8")), data.get("agent_type") or "")
    if owner and owner.get("status") != "retired":
        if started(sys.argv[2], agent_id):
            actor_id = owner["agent_id"]
        else:                          # Start 없는 Stop = Claude Code 내부 보조 호출
            template = "claude"
except (ImportError, OSError, ValueError):
    pass
event = {
    "kind": "task.finished",
    "task_id": agent_id,
    "actor": "agent:" + actor_id,
    "session_id": data.get("session_id") or None,
    "claimed": "success",
    "evidence": {"template": template},
}
print(json.dumps(event, ensure_ascii=False))
' "$PROJECT_DIR/.hermes/agents.json" "$PROJECT_DIR/.hermes/state.db" 2>/dev/null)" || exit 0
[[ -n "$EVENT" ]] || exit 0

python3 "$JOURNAL" --project "$PROJECT_DIR" emit --json "$EVENT" >/dev/null 2>&1
exit 0
