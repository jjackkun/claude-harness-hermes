#!/usr/bin/env python3
"""에이전트와 나눈 대화 요약을 `.hermes/agents/<id>/conversations/<사람>/<세션>.json` 으로 내보내고 들이는 것만 담당한다.

- 내용은 5칸 요약뿐이다(원문 아님). 항목마다 **판정을 통과한 것(clean·keep)만** 넣는다.
- 세션 하나 = 파일 하나. 요약이 갱신되면 그 파일만 바뀐다. 사람별 폴더라 거를 때 파일 안 칸에만 기대지 않는다.
- 사람 칸이 빈 요약(칸 이전)은 이 컴퓨터의 사람 것으로 쓴다 — 그 요약은 이 컴퓨터에서 쌓였다.
- 들이기: updated_at 이 더 새 것만 반영한다. 파일 속 주인·사람이 폴더(에이전트 id · 사람 폴더)와 다르면 버린다.
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 5

공개: SLOT_KEYS · judge_items · export · import_
"""

import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_person import person  # noqa: E402
from hermes_privacy_pending import allowed  # noqa: E402
from hermes_summary_owner import ensure_agent_column  # noqa: E402

SLOT_KEYS = ("decisions", "open", "prefs", "facts", "next")


def _safe(name: str) -> str:
    return re.sub(r"[^\w.-]", "_", str(name or "")) or "_"


def _slots(raw) -> dict:
    try:
        data = json.loads(raw) if raw else {}
    except ValueError:
        data = {}
    return {k: [str(x) for x in (data.get(k) or []) if str(x).strip()] for k in SLOT_KEYS}


def _agent_rows(con) -> list:
    ensure_agent_column(con)
    return con.execute("SELECT session_id, agent_id, person, slots_json, updated_at, turn_count "
                       "FROM session_summary WHERE agent_id IS NOT NULL AND agent_id != ''").fetchall()


def judge_items(con, agent_only: bool = False) -> list:
    """판정할 요약 항목 [(kind, ref, text)]. agent_only 면 에이전트 요약만(아니면 공통 포함)."""
    ensure_agent_column(con)
    sql = "SELECT session_id, slots_json FROM session_summary"
    if agent_only:
        sql += " WHERE agent_id IS NOT NULL AND agent_id != ''"
    items = []
    for sid, raw in con.execute(sql).fetchall():
        items += [("summary", sid, text) for k in SLOT_KEYS for text in _slots(raw)[k]]
    return items


def export(con, project: str) -> int:
    """에이전트 요약 파일을 쓴다(내용이 바뀐 것만). 쓴 파일 수."""
    written, me = 0, person(project)
    for sid, aid, who, raw, upd, turns in _agent_rows(con):
        folder = os.path.join(project, ".hermes", "agents", aid)
        if not os.path.isfile(os.path.join(folder, "SOUL.md")):
            continue
        slots = {k: [t for t in v if allowed(con, t)] for k, v in _slots(raw).items()}
        body = {"session_id": sid, "agent_id": aid, "person": who or me, "updated_at": upd,
                "turn_count": turns or 0, "slots": slots}
        path = os.path.join(folder, "conversations", _safe(who or me), _safe(sid) + ".json")
        written += _write_if_changed(path, json.dumps(body, ensure_ascii=False, sort_keys=True, indent=1) + "\n")
    return written


def _write_if_changed(path: str, text: str) -> int:
    """내용이 같으면 안 쓴다(git 에 헛 변경을 만들지 않는다). 쓰면 1."""
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            if fh.read() == text:
                return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(path + ".tmp", path)
    return 1


def _load(path: str):
    try:
        with open(path, encoding="utf-8") as fh:
            body = json.load(fh)
    except (OSError, ValueError):
        return None
    return body if isinstance(body, dict) and body.get("session_id") and body.get("agent_id") else None


def import_(con, project: str) -> int:
    """파일에서 DB 보다 새 요약을 들인다. 반영한 수."""
    ensure_agent_column(con)
    got = 0
    for path in sorted(glob.glob(os.path.join(project, ".hermes", "agents", "*", "conversations", "*", "*.json"))):
        body = _load(path)
        parts = path.split(os.sep)
        if body is None or body["agent_id"] != parts[-4] or _safe(body.get("person")) != parts[-2]:
            continue
        cur = con.execute(
            "INSERT INTO session_summary (session_id, project_id, slots_json, last_msg_count, turn_count, updated_at, "
            "agent_id, person) VALUES (?,?,?,0,?,?,?,?) "
            "ON CONFLICT(session_id) DO UPDATE SET slots_json=excluded.slots_json, turn_count=excluded.turn_count, "
            "updated_at=excluded.updated_at, agent_id=excluded.agent_id, person=excluded.person "
            "WHERE IFNULL(session_summary.updated_at, '') < excluded.updated_at",
            (body["session_id"], "", json.dumps(body.get("slots") or {}, ensure_ascii=False),
             body.get("turn_count") or 0, body.get("updated_at") or "", body["agent_id"], body.get("person")))
        got += cur.rowcount
    con.commit()
    return got
