#!/usr/bin/env python3
"""작업 이력에서 보기를 계산한다. 쓰기는 하지 않는다(파생).

  thread   — 한 작업의 이벤트를 시간순으로
  graph    — parent_task_id · caused_by 간선
  mismatch — 에이전트가 성공이라 했는데 기계가 실패로 본 것
  gaps     — 시작만 있고 끝이 없는 작업(Stop 훅·heartbeat 가 쓴다)
계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 9·6·13
"""

import json
from datetime import datetime, timedelta, timezone

_COLS = "event_id, ts, kind, task_id, parent_task_id, caused_by, actor, requested_by, claimed, verified, evidence, intent, decision"


def _rows(con, where: str, args=()) -> list:
    cur = con.execute(f"SELECT {_COLS} FROM journal_events {where}", args)
    names = [d[0] for d in cur.description]
    return [dict(zip(names, r)) for r in cur.fetchall()]


def thread(con, task_id: str) -> list:
    """한 작업의 이벤트를 시간순으로."""
    return _rows(con, "WHERE task_id = ? ORDER BY ts, event_id", (task_id,))


def graph(con, task_id: str = None) -> dict:
    """작업 사이의 간선. task_id 를 주면 그 작업과 자식만."""
    where = "WHERE task_id = ? OR parent_task_id = ?" if task_id else ""
    args = (task_id, task_id) if task_id else ()
    rows = _rows(con, where + " ORDER BY ts, event_id", args)
    edges = []
    for r in rows:
        if r["parent_task_id"]:
            edges.append({"from": r["parent_task_id"], "to": r["task_id"], "type": "parent"})
        for caused in json.loads(r["caused_by"]) if r["caused_by"] else []:
            edges.append({"from": caused, "to": r["event_id"], "type": "caused_by"})
    return {"nodes": sorted({r["task_id"] for r in rows}), "edges": edges}


def mismatch(con) -> list:
    """주장과 검증이 어긋난 것 — 에이전트 성적의 바탕(G-12 의 보기 하나)."""
    return _rows(con, "WHERE claimed = 'success' AND verified = 'fail' ORDER BY ts DESC")


def gaps(con, universe: str = None, stale_minutes: int = None) -> list:
    """끝나지 않은 작업.

    stale_minutes 를 주면 마지막 이벤트가 그보다 오래된 것만 — heartbeat 가 끊긴 작업이다.
    주지 않으면 미완료 전부(세션 종료 시 Stop 훅이 쓴다).
    """
    where = "WHERE kind = 'task.started'"
    args = []
    if universe:
        where += " AND universe_id = ?"
        args.append(universe)
    started = _rows(con, where + " ORDER BY ts", tuple(args))
    out = []
    for row in started:
        events = thread(con, row["task_id"])
        if any(e["kind"] in ("task.finished", "tombstone") for e in events):
            continue
        if stale_minutes is not None and not _is_stale(events[-1]["ts"], stale_minutes):
            continue
        out.append({"task_id": row["task_id"], "started_ts": row["ts"],
                    "last_ts": events[-1]["ts"], "actor": row["actor"]})
    return out


def _is_stale(ts: str, minutes: int) -> bool:
    try:
        last = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return False
    return datetime.now(timezone.utc) - last > timedelta(minutes=minutes)
