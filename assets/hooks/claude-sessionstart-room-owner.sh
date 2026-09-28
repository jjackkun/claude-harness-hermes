#!/usr/bin/env bash
# SessionStart hook — 사람이 연 방(`claude --agent <slug>`, hermes-chat)의 주인을 작업 이력에 한 줄 남긴다.
# (계획 2026-09-28-hermes-chat 목표 3)
#
# 주인은 "불린" 것이 아니라 방 자체라 @ 호출 이력(match=mention)에 잡히지 않는다 — 상태줄이 "없음" 으로 보였다(사용자 지적).
# 모양: task.assigned · decision "match=owner slug=<slug> agent=<명부 id>" · actor "agent:<slug>".
#   actor 가 명부 id 가 아닌 이유(C-28): 이 세션에는 소환 nonce 가 없어 "정말 그 에이전트인가" 를 보증하지 못한다.
#   task.assigned 는 gap-check(task.started 만 봄)이 닫지 않고, 방 보기의 "일하는 중"(match=mention 만 봄)에도 안 든다.
# 한 세션에 한 번 — resume·compact 로 다시 불려도 같은 session_id 의 주인 줄이 있으면 적지 않는다.
# 적지 않는 경우(전부 exit 0): 소환 세션(HERMES_AGENT_ID) · agent_type 없음·slug 꼴 아님 · 명부 밖 · 은퇴자 · 이력 없음.
# stdout 은 세션 문맥으로 주입되므로 아무것도 내지 않는다.
set -uo pipefail
[[ -z "${HERMES_AGENT_ID:-}" ]] || exit 0
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
JOURNAL="$PROJECT_DIR/scripts/hermes-journal.py"
[[ -f "$JOURNAL" && -f "$PROJECT_DIR/.hermes/state.db" && -f "$PROJECT_DIR/.hermes/agents.json" ]] || exit 0
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

EVENT="$(printf '%s' "$INPUT" | PYTHONPATH="$PROJECT_DIR/scripts" python3 -c '
import json, re, sqlite3, sys
from hermes_agent_slug import agent_by_slug
try:
    data = json.load(sys.stdin)
    roster = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(1)
slug, session = data.get("agent_type") or "", data.get("session_id") or ""
if not session or not re.fullmatch(r"[a-z][a-z0-9-]{1,39}", slug):
    sys.exit(1)
agent = agent_by_slug(roster, slug)
if agent is None or agent.get("status") == "retired":
    sys.exit(1)
try:
    con = sqlite3.connect("file:%s?mode=ro" % sys.argv[2], uri=True)
    seen = con.execute("SELECT 1 FROM journal_events WHERE kind=? AND session_id=? AND decision LIKE ? LIMIT 1",
                       ("task.assigned", session, "match=owner %")).fetchone()
    con.close()
except sqlite3.Error:
    seen = None                     # 표가 아직 없음 — emit 이 만든다
if seen:
    sys.exit(1)
print(json.dumps({
    "kind": "task.assigned",
    "session_id": session,
    "actor": "agent:%s" % slug,
    "decision": "match=owner slug=%s agent=%s" % (slug, agent["agent_id"]),
    "evidence": {"template": slug},
}, ensure_ascii=False))
' "$PROJECT_DIR/.hermes/agents.json" "$PROJECT_DIR/.hermes/state.db" 2>/dev/null)" || exit 0
[[ -n "$EVENT" ]] || exit 0

python3 "$JOURNAL" --project "$PROJECT_DIR" emit --json "$EVENT" >/dev/null 2>&1
exit 0
