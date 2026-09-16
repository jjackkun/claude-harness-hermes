#!/usr/bin/env python3
"""헤르메스 루프 — 「내가 대신 결정한 것」 기록.

에이전트가 사람에게 묻지 않고 정한 판단을 반복마다 저장하고, 종료 보고서가
모아 보여준다. 줄을 빠뜨린 반복(missing)과 결정이 없던 반복(none)을 구분한다
— 빈칸과 빠뜨림이 같아 보이면 기록이 강제되지 않는다.
출처: obra/superpowers subagent-driven-development "Rulings" · "Finish" 절.
규칙: assets/rules/harness/decision-ledger.md
"""

import re
from datetime import datetime

import hermes_loop as core
from hermes_redact import redact

NONE_WORDS = ("없음", "none")

# CREATE IF NOT EXISTS — 이 기능 이전에 만든 state.db 에도 무손실로 붙는다
DECISION_SCHEMA = """
CREATE TABLE IF NOT EXISTS loop_decisions (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  loop_id    TEXT NOT NULL,
  iteration  INTEGER NOT NULL,
  kind       TEXT NOT NULL,
  text       TEXT,
  created_at TEXT NOT NULL
)
"""

_LINE_RE = re.compile(r"^DECISION:[ \t]*(.*)$", re.M)


def parse_decision_lines(block):
    """REPORT 블록 본문에서 DECISION: 값들을 순서대로 추출."""
    return [v.strip() for v in _LINE_RE.findall(block or "")]


def classify(entries):
    """DECISION 값 목록 → [(kind, text)].

    값이 하나도 없으면 missing, '없음' 만 있으면 none, 나머지는 ruling.
    """
    items = [e.strip() for e in (entries or []) if e and e.strip()]
    if not items:
        return [("missing", None)]
    rulings = [e for e in items if e.lower() not in NONE_WORDS]
    if not rulings:
        return [("none", None)]
    return [("ruling", e) for e in rulings]


def _connect(db_path):
    con = core.connect_db(db_path)
    con.execute(DECISION_SCHEMA)
    return con


def record(db_path, loop_id, iteration, entries):
    """반복 1회의 결정 기록 저장 — 텍스트는 마스킹 경유 (G12)."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    con = _connect(db_path)
    con.executemany(
        "INSERT INTO loop_decisions (loop_id, iteration, kind, text,"
        " created_at) VALUES (?,?,?,?,?)",
        [(loop_id, iteration, kind, redact(text) if text else None, now)
         for kind, text in classify(entries)])
    con.commit()
    con.close()
    _mirror_to_journal(db_path, loop_id, iteration, entries)


def _mirror_to_journal(db_path, loop_id, iteration, entries):
    """같은 결정을 작업 이력에도 남긴다(G-9 — 흡수가 아니라 병기).

    loop_decisions 는 report.html 이 읽으므로 그대로 두고, 대화형·헤드리스를 한자리에서
    보려면 journal 에도 있어야 한다. 이력이 없거나 거부돼도 루프를 멈추지 않는다.
    """
    try:
        import os
        import sys
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from hermes_journal import emit
        project = os.path.dirname(os.path.dirname(os.path.abspath(db_path)))
        for kind, text in classify(entries):
            emit(db_path, project, {
                "kind": "decision", "task_id": loop_id,
                "evidence": {"reason": kind},
                "decision": (redact(text) if text else None),
            })
    except Exception as exc:                      # noqa: BLE001 — 이력은 루프를 막지 않는다
        print(f"[hermes-loop] 결정을 작업 이력에 남기지 못했다: {exc}", file=__import__("sys").stderr)


def fetch(db_path, loop_id):
    """[(iteration, kind, text)] — 정한 순서(반복 → 기록 순)."""
    con = _connect(db_path)
    rows = con.execute(
        "SELECT iteration, kind, text FROM loop_decisions WHERE loop_id=?"
        " ORDER BY iteration, id", (loop_id,)).fetchall()
    con.close()
    return rows
