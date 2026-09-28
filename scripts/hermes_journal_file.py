#!/usr/bin/env python3
"""작업 이력에서 올릴 줄을 고르고 `.hermes/journal.jsonl` 로 내보내고 들이는 것만 담당한다.

고르는 규칙은 select 한 곳뿐이다 — 매번 같은 부분집합을 써야 merge=union 과 event_id 중복 제거가 안전하다.
  올림: task.assigned · decision · agent.created · 교훈(lesson) 붙은 줄 · 명부 에이전트 호출의 task.finished ·
        올린 인계의 끝남 기록 전부(_CLOSING 4종 — 하나라도 빠지면 다른 컴퓨터에서 인계가 영원히 대기로 보인다)
  안 올림: 명부 밖 보조 호출(code-reviewer·Explore 등)의 task.finished — 하루 수십 줄이라 git 이력만 어지럽힌다
사람이 쓴 문장(intent 작업 지시 · 교훈 · decision 줄의 결정)은 판정을 통과한 것(clean·keep)만 나간다.
두 세션이 동시에 붙여도 줄이 겹치지 않게 파일을 잠그고 그 안에서 다시 읽는다(hermes_jsonl_lock).
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 6

공개: FILE · select · judge_items · export · import_
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_handoff_queue import _CLOSING  # noqa: E402  (인계를 닫는 종류 — 같은 목록을 두 곳에 두지 않는다)
from hermes_journal_schema import COLUMNS, ensure_schema  # noqa: E402
from hermes_jsonl_lock import locked_append  # noqa: E402
from hermes_privacy_pending import allowed  # noqa: E402
from hermes_roster import load_roster  # noqa: E402

FILE = os.path.join(".hermes", "journal.jsonl")
_ALWAYS = ("task.assigned", "decision", "agent.created")


def _roster_keys(project: str) -> set:
    keys = set()
    for a in load_roster(project).get("agents", []):
        keys.update(k for k in (a.get("slug"), a.get("agent_id")) if k)
    return keys


def _template(evidence) -> str:
    try:
        return (json.loads(evidence) or {}).get("template") or ""
    except (ValueError, TypeError, AttributeError):
        return ""


def select(con, project: str) -> list:
    """올릴 줄(dict), 시각 순."""
    ensure_schema(con)
    rows = [dict(zip(COLUMNS, r)) for r in con.execute(
        "SELECT {} FROM journal_events ORDER BY ts, event_id".format(", ".join(COLUMNS)))]
    roster = _roster_keys(project)
    handed = {r["task_id"] for r in rows if r["kind"] == "task.assigned"}
    out = []
    for r in rows:
        if (r["kind"] in _ALWAYS or r["lesson"]
                or (r["kind"] == "task.finished" and _template(r["evidence"]) in roster)
                or (r["kind"] in _CLOSING and r["task_id"] in handed)):
            out.append(r)
    return out


def _texts(row: dict) -> list:
    texts = [t for t in (row["intent"], row["lesson"]) if t]   # intent = 사람이 준 작업 지시 원문(hermes-summon)
    if row["kind"] == "decision" and row["decision"]:
        texts.append(row["decision"])
    return texts


def judge_items(con, project: str) -> list:
    return [("journal", r["event_id"], t) for r in select(con, project) for t in _texts(r)]




def export(con, project: str) -> int:
    rows = [r for r in select(con, project) if all(allowed(con, t) for t in _texts(r))]
    if not rows:
        return 0
    return locked_append(os.path.join(project, FILE), "event_id", rows)


def import_(con, project: str) -> int:
    path = os.path.join(project, FILE)
    if not os.path.isfile(path):
        return 0
    ensure_schema(con)
    got = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if not isinstance(row, dict) or not row.get("event_id"):
                continue
            try:
                cur = con.execute("INSERT OR IGNORE INTO journal_events ({}) VALUES ({})".format(
                    ", ".join(COLUMNS), ", ".join("?" * len(COLUMNS))), tuple(row.get(c) for c in COLUMNS))
                got += cur.rowcount
            except Exception:                  # 받는 쪽이 모르는 kind(옛 CHECK) — 그 줄만 건너뛴다
                continue
    con.commit()
    return got
