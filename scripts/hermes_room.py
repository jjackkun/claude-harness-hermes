#!/usr/bin/env python3
"""작업 이력에서 명부 에이전트의 활동(방 구성원 · 최근 불린 때)을 모으는 것만 담당한다. 읽기 전용.

"방" 은 세션 하나다. 손님의 "방에 있다" = 이 방에서 불린 적 있음(사용자 결정 2026-09-28).
근거는 task.finished 한 건 = 한 번 불림 — 소환(hermes-summon)과 @agent-<slug>(SubagentStop 훅) 모두 이 모양으로 남는다.
  명부 에이전트   actor 가 명부 id (main 제외)
  내부 보조       evidence.template == "claude" — 세션 폴더에 대화 파일이 없는 Claude Code 내부 호출(2026-09-28 확인)
  명부 밖         그 밖(code-reviewer · claude-code-guide 등) — 종류별 건수
  일하는 중       이 방의 @ 호출 task.assigned(decision "match=mention … agent=<id>") 중 같은 task_id 의 finished 가 아직 없는 것.
                  시간 상한은 두지 않는다 — 끝 기록이 빠지는 것은 SubagentStop 훅 실패뿐이고, 세션이 죽으면 방도 새로 열린다.
  방 주인         `claude --agent <slug>` 로 연 방의 주인 — task.assigned decision "match=owner … agent=<id>"(room-owner 훅).
                  불린 것이 아니라 방 자체라 손님 횟수에 넣지 않는다(계획 2026-09-28-hermes-chat 목표 3).
DB·표가 없으면 빈 결과(오류 아님) — 상태줄·슬래시 명령이 세션을 흔들면 안 된다.
계획: docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 1·2

공개: INTERNAL_TEMPLATE · collect_room · last_seen
"""

import json
import os
import sqlite3

INTERNAL_TEMPLATE = "claude"
_MAIN = "main"


def _rows(project: str, sql: str, params: tuple) -> list:
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            return con.execute(sql, params).fetchall()
        finally:
            con.close()
    except sqlite3.Error:
        return []                                   # 표가 아직 없음(구 스키마·rollback) — 빈 결과


def _roster_ids(roster: dict) -> dict:
    return {a["agent_id"]: a for a in roster.get("agents") or [] if a.get("name") != _MAIN}


def _working(project: str, agents: dict, session_id: str) -> list:
    """이 방에서 @ 로 불려 아직 안 끝난 명부 에이전트 id(시작 순, 중복 없음)."""
    rows = _rows(project, "SELECT a.decision FROM journal_events a WHERE a.kind='task.assigned' AND a.session_id=? "
                          "AND a.decision LIKE 'match=mention %' AND NOT EXISTS (SELECT 1 FROM journal_events f "
                          "WHERE f.kind='task.finished' AND f.task_id=a.task_id) ORDER BY a.ts", (session_id,))
    ids = [w[len("agent="):] for (d,) in rows for w in (d or "").split() if w.startswith("agent=")]
    return [i for n, i in enumerate(ids) if i in agents and i not in ids[:n]]


def _owner(project: str, agents: dict, session_id: str) -> str:
    """이 방 주인의 명부 이름. 주인 줄이 없거나 명부에서 사라졌으면 빈 문자열."""
    rows = _rows(project, "SELECT decision FROM journal_events WHERE kind='task.assigned' AND session_id=? "
                          "AND decision LIKE 'match=owner %' ORDER BY ts LIMIT 1", (session_id,))
    ids = [w[len("agent="):] for (d,) in rows for w in (d or "").split() if w.startswith("agent=")]
    return agents[ids[0]]["name"] if ids and ids[0] in agents else ""


def _template(evidence) -> str:
    try:
        return (json.loads(evidence or "{}") or {}).get("template") or "unknown"
    except ValueError:
        return "unknown"


def _member(agents: dict, agent_id: str) -> dict:
    a = agents[agent_id]
    return {"name": a["name"], "slug": a.get("slug"), "agent_id": agent_id, "count": 0, "last": ""}


def collect_room(project: str, roster: dict, session_id: str) -> dict:
    """{"owner": 이름|"", "members": [{name, slug, agent_id, count, last}], "working": [이름…], "tools": {종류: 건수}, "internal": 건수}.
    members 는 최근순, count 는 끝난 호출 + 지금 일하는 중인 호출."""
    agents = _roster_ids(roster)
    members, tools, internal = {}, {}, 0
    rows = _rows(project, "SELECT actor, evidence, ts FROM journal_events "
                          "WHERE kind='task.finished' AND session_id=? ORDER BY ts", (session_id,))
    for actor, evidence, ts in rows:
        actor_id = (actor or "").split(":", 1)[-1]
        if actor_id in agents:
            m = members.setdefault(actor_id, _member(agents, actor_id))
            m["count"] += 1
            m["last"] = max(m["last"], ts or "")
            continue
        template = _template(evidence)
        if template == INTERNAL_TEMPLATE:
            internal += 1
        else:
            tools[template] = tools.get(template, 0) + 1
    working = _working(project, agents, session_id)
    for agent_id in working:
        members.setdefault(agent_id, _member(agents, agent_id))["count"] += 1
    ordered = sorted(members.values(), key=lambda m: m["last"], reverse=True)
    return {"owner": _owner(project, agents, session_id), "members": ordered,
            "working": [agents[i]["name"] for i in working], "tools": tools, "internal": internal}


def last_seen(project: str) -> dict:
    """명부 id → 마지막으로 불린 시각(모든 방, task.finished 기준). 불린 적 없으면 키 없음."""
    rows = _rows(project, "SELECT actor, MAX(ts) FROM journal_events "
                          "WHERE kind='task.finished' AND actor LIKE 'agent:%' GROUP BY actor", ())
    return {actor.split(":", 1)[1]: ts for actor, ts in rows if actor and ts}
