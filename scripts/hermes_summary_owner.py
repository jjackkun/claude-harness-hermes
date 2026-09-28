#!/usr/bin/env python3
"""대화 요약의 주인 찾기와 `session_summary` 주인 칸(agent_id · person) 보장만 담당한다(C-29).

- 칸: agent_id 가 있으면 그 에이전트의 대화 기억, 비면 소우주 공통(예전 뜻 그대로). 다섯 생성 지점이 모두 이것을 부른다.
- 칸: person = 그 대화를 나눈 사람의 이름표(git user.name). 비면 칸이 생기기 전 요약(계획 carry-agent-knowledge 목표 1).
- 방: 방 세션(`claude --agent`)의 주인 = 방 주인 기록(journal task.assigned `match=owner … agent=<id>`, room-owner 훅).
- @ 호출: SubagentStart 기록(task.assigned task_id=<서브에이전트 id> `match=mention … agent=<id>`)이 있는 호출만.
  Claude Code 내부 보조(입력 추천·/btw)도 방 안에서 같은 agent_type 으로 SubagentStop 이 오지만 Start 기록이 없다.
계획: docs/exec-plans/completed/2026-09-28-agent-conversation-memory.md 목표 1 · 2 · 3

공개: ensure_agent_column · is_agent_session · room_owner_id · mention_owner_id
"""

import os
import sqlite3


def _add_column(con, name: str) -> None:
    """칸 더하기 — 다른 프로세스가 먼저 더했으면(PRAGMA 와 ALTER 사이 경쟁, DB 리뷰 HIGH) 그 오류만 삼킨다."""
    try:
        con.execute(f"ALTER TABLE session_summary ADD COLUMN {name} TEXT")
    except sqlite3.OperationalError as exc:
        if "duplicate column" not in str(exc).lower():
            raise                                   # 락 시간 초과 등 다른 원인은 그대로 올린다


def ensure_agent_column(con) -> None:
    """있는 session_summary 에 agent_id · person 칸을 더한다. 표가 없으면 아무것도 안 한다(만드는 쪽이 먼저 CREATE). 두 번 불러도 같다."""
    cols = [r[1] for r in con.execute("PRAGMA table_info(session_summary)")]
    for name in ("agent_id", "person"):
        if cols and name not in cols:
            _add_column(con, name)
    if cols:
        con.execute("CREATE INDEX IF NOT EXISTS session_summary_agent_idx ON session_summary(agent_id, updated_at)")


def is_agent_session(con, session_id: str) -> bool:
    """이 세션 요약에 주인(agent_id)이 있는가 — 공통 재료(lifecycle 등)에서 뺄 세션. 칸이 없는 옛 DB 면 아니다."""
    try:
        row = con.execute("SELECT agent_id FROM session_summary WHERE session_id=?", (session_id,)).fetchone()
    except sqlite3.OperationalError:
        return False
    return bool(row and row[0])


def _agent_from_decision(project: str, sql: str, params: tuple) -> str:
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return ""
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        row = con.execute(sql, params).fetchone()
        con.close()
    except sqlite3.Error:
        return ""                                   # 이력 표가 없음 — 주인 모름 = 공통
    words = (row[0] if row else "") or ""
    return next((w[len("agent="):] for w in words.split() if w.startswith("agent=")), "")


def room_owner_id(project: str, session_id: str) -> str:
    """이 세션이 방이면 방 주인 명부 id, 아니면 빈 문자열."""
    return _agent_from_decision(
        project, "SELECT decision FROM journal_events WHERE kind='task.assigned' AND session_id=? "
                 "AND decision LIKE 'match=owner %' ORDER BY ts LIMIT 1", (session_id,))


def mention_owner_id(project: str, subagent_id: str) -> str:
    """이 서브에이전트가 명부 에이전트 @ 호출이면(SubagentStart 기록 있음) 명부 id, 아니면 빈 문자열."""
    return _agent_from_decision(
        project, "SELECT decision FROM journal_events WHERE kind='task.assigned' AND task_id=? "
                 "AND decision LIKE 'match=mention %' LIMIT 1", (subagent_id,))
