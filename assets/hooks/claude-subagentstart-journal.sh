#!/usr/bin/env bash
# SubagentStart hook — @agent-<slug> 로 명부 에이전트가 불리면 작업 이력에 task.assigned 를 남긴다.
# (계획 2026-09-28-agent-mention-bridge 목표 5)
#
# 소환 경로(hermes-summon.py)와 같은 모양: task.assigned 의 actor 는 **부른 쪽**(환경에서 채움),
# 매칭 근거는 decision 에. 담당자는 같은 task_id 의 task.finished(SubagentStop 훅) actor 로 드러난다.
# task_id 는 서브에이전트 인스턴스 id — Start·Stop 훅 입력에 똑같이 온다.
# evidence 는 허용 키만(hermes_journal_schema.EVIDENCE_KEYS) — 그래서 "mention" 은 decision 에 적는다.
# nonce 는 없다 — 서브에이전트는 세션이 아니라 이미 판정된 부모 세션 안의 호출이다(RV-06 은 세션 규칙).
#
# 명부 밖(내장·공장 에이전트)은 적지 않는다 — 그쪽은 SubagentStop 훅이 예전처럼 finished 만 남긴다.
# 이력이 없는 구 스키마·rollback·입력 손상에서도 죽지 않는다(exit 0).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
JOURNAL="$PROJECT_DIR/scripts/hermes-journal.py"
[[ -f "$JOURNAL" && -f "$PROJECT_DIR/.hermes/state.db" ]] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

EVENT="$(printf '%s' "$INPUT" | PYTHONPATH="$PROJECT_DIR/scripts" python3 -c '
import json, sys
from hermes_agent_slug import agent_by_slug
try:
    data = json.load(sys.stdin)
    roster = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
sub_id, slug = data.get("agent_id") or "", data.get("agent_type") or ""
agent = agent_by_slug(roster, slug) if sub_id and slug else None
if agent is None:
    sys.exit(1)
print(json.dumps({
    "kind": "task.assigned",
    "task_id": sub_id,
    "session_id": data.get("session_id") or None,
    "decision": "match=mention slug=%s agent=%s" % (slug, agent["agent_id"]),
    "evidence": {"template": slug},
}, ensure_ascii=False))
' "$PROJECT_DIR/.hermes/agents.json" 2>/dev/null)" || exit 0
[[ -n "$EVENT" ]] || exit 0

python3 "$JOURNAL" --project "$PROJECT_DIR" emit --json "$EVENT" >/dev/null 2>&1
exit 0
