#!/usr/bin/env python3
"""기억 이벤트(memory_events)를 에이전트 폴더 `memory.jsonl` 로 내보내고, 받은 파일에서 DB 로 들이는 것만 담당한다.

- 파일은 추가만 한다 — 한 줄 = 이벤트 하나. 이미 있는 memory_id 는 다시 쓰지 않는다.
- 본문이 있는 이벤트는 **판정을 통과한 것(clean·keep)만** 나간다. 검토 대기·지움·미판정은 나가지 않는다
  (추가만 하는 파일이라 먼저 쓰고 나중에 철회하면 원문이 git 이력에 남는다).
- 본문 없는 철회(memory.retracted)는 그대로 나간다.
- 폴더(SOUL 이 있는 명부 에이전트)가 없는 에이전트 기억은 쓰지 않는다 — 떠돌이 폴더를 만들지 않는다.
- 들이기: memory_id 로 중복을 거른다(INSERT OR IGNORE). 파일 속 agent_id 가 폴더 이름과 다른 줄은 버린다(git 으로 온 값).
  MEMORY.md 는 들인 에이전트만 다시 만든다.
- 경로에는 안전한 id(영숫자·-·_)만 쓴다. 동시에 붙여도 겹치지 않게 잠근다(hermes_jsonl_lock).
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 4

공개: FILE · judge_items · export · import_
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_memory_events import COLUMNS, ensure_memory_schema  # noqa: E402
from hermes_jsonl_lock import SAFE_ID, locked_append  # noqa: E402
from hermes_privacy_pending import allowed  # noqa: E402

FILE = "memory.jsonl"


def _agents_dir(project: str) -> str:
    return os.path.join(project, ".hermes", "agents")




def _rows(con) -> list:
    ensure_memory_schema(con)
    cur = con.execute("SELECT {} FROM memory_events ORDER BY ts, memory_id".format(", ".join(COLUMNS)))
    return [dict(zip(COLUMNS, r)) for r in cur.fetchall()]


def judge_items(con) -> list:
    """판정할 문장 [(kind, ref, text)] — 본문이 있는 이벤트."""
    return [("memory", r["memory_id"], r["body"]) for r in _rows(con) if r["body"]]


def export(con, project: str) -> int:
    """판정을 통과한 새 이벤트를 에이전트별 파일 끝에 붙인다. 붙인 줄 수."""
    by_agent = {}
    for row in _rows(con):
        aid = str(row["agent_id"] or "")
        if not SAFE_ID.fullmatch(aid) or not os.path.isfile(os.path.join(_agents_dir(project), aid, "SOUL.md")):
            continue
        if row["body"] and not allowed(con, row["body"]):
            continue
        by_agent.setdefault(aid, []).append(row)
    return sum(locked_append(os.path.join(_agents_dir(project), aid, FILE), "memory_id", rows)
               for aid, rows in by_agent.items())


def _file_rows(path: str, aid: str) -> list:
    """파일의 줄 중 이 폴더(aid) 몫으로 쓸 수 있는 것. agent_id 가 폴더와 다른 줄은 버린다(git 으로 온 값)."""
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if isinstance(row, dict) and row.get("memory_id") and row.get("agent_id") == aid:
                rows.append(row)
    return rows


def import_(con, project: str) -> set:
    """모든 에이전트 폴더의 파일에서 DB 에 없는 이벤트를 넣는다. 새 줄이 들어간 에이전트 id 집합."""
    ensure_memory_schema(con)
    touched = set()
    base = _agents_dir(project)
    sql = "INSERT OR IGNORE INTO memory_events ({}) VALUES ({})".format(", ".join(COLUMNS), ", ".join("?" * len(COLUMNS)))
    for aid in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, aid, FILE)
        if not os.path.isfile(path):
            continue
        for row in _file_rows(path, aid):
            if con.execute(sql, tuple(row.get(c) for c in COLUMNS)).rowcount:
                touched.add(aid)
    con.commit()
    return touched
