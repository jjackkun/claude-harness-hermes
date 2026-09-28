#!/usr/bin/env python3
"""작업 이력에서 명부 에이전트의 활동(방 구성원 · 최근 불린 때)을 모으는 것만 담당한다. 읽기 전용.

"방" 은 세션 하나다. 손님의 "방에 있다" = 이 방에서 불린 적 있음(사용자 결정 2026-09-28).
근거는 task.finished 한 건 = 한 번 불림 — 소환(hermes-summon)과 @agent-<slug>(SubagentStop 훅) 모두 이 모양으로 남는다.
  명부 에이전트   actor 가 명부 id (main 제외)
  내부 보조       evidence.template == "claude" — 세션 폴더에 대화 파일이 없는 Claude Code 내부 호출(2026-09-28 확인)
  명부 밖         그 밖(code-reviewer · claude-code-guide 등) — 종류별 건수
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


def collect_room(project: str, roster: dict, session_id: str) -> dict:
    """{"members": [{name, slug, agent_id, count, last}], "tools": {종류: 건수}, "internal": 건수}. members 는 최근순."""
    agents = _roster_ids(roster)
    members, tools, internal = {}, {}, 0
    rows = _rows(project, "SELECT actor, evidence, ts FROM journal_events "
                          "WHERE kind='task.finished' AND session_id=? ORDER BY ts", (session_id,))
    for actor, evidence, ts in rows:
        actor_id = (actor or "").split(":", 1)[-1]
        if actor_id in agents:
            m = members.setdefault(actor_id, {"name": agents[actor_id]["name"], "slug": agents[actor_id].get("slug"),
                                              "agent_id": actor_id, "count": 0, "last": ""})
            m["count"] += 1
            m["last"] = max(m["last"], ts or "")
            continue
        try:
            template = (json.loads(evidence or "{}") or {}).get("template") or "unknown"
        except ValueError:
            template = "unknown"
        if template == INTERNAL_TEMPLATE:
            internal += 1
        else:
            tools[template] = tools.get(template, 0) + 1
    ordered = sorted(members.values(), key=lambda m: m["last"], reverse=True)
    return {"members": ordered, "tools": tools, "internal": internal}


def last_seen(project: str) -> dict:
    """명부 id → 마지막으로 불린 시각(모든 방, task.finished 기준). 불린 적 없으면 키 없음."""
    rows = _rows(project, "SELECT actor, MAX(ts) FROM journal_events "
                          "WHERE kind='task.finished' AND actor LIKE 'agent:%' GROUP BY actor", ())
    return {actor.split(":", 1)[1]: ts for actor, ts in rows if actor and ts}
