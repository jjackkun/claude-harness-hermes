#!/usr/bin/env python3
"""헤르메스 회상 스크립트.

--inject: UserPromptSubmit 훅에서 호출. 같은 프로젝트의 직전(다른) 세션 요약 중
          open+decisions 를 stdout 으로 출력해 컨텍스트에 주입한다.
          recall_marker 로 세션당 1회만 주입한다.
--query:  /hermes-recall 스킬에서 호출. 요약을 키워드로 검색해 출력한다.

사용법:
  python3 hermes-recall.py --inject --db PATH --project-id ID --session-id ID
  python3 hermes-recall.py --query "키워드" --db PATH
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime

try:
    from hermes_reuse import ensure_reuse_table, mark_reused
except ImportError:  # 헬퍼 미복사 시에도 회상 자체는 동작해야 한다
    ensure_reuse_table = None
    mark_reused = None

SLOT_KEYS = ["decisions", "open", "prefs", "facts", "next"]


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.execute("""
        CREATE TABLE IF NOT EXISTS session_summary (
            session_id     TEXT PRIMARY KEY,
            project_id     TEXT,
            slots_json     TEXT,
            last_msg_count INTEGER DEFAULT 0,
            turn_count     INTEGER DEFAULT 0,
            updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    con.execute("""
        CREATE TABLE IF NOT EXISTS recall_marker (
            session_id  TEXT PRIMARY KEY,
            injected_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)


def _load_slots(raw: str) -> dict:
    try:
        return json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return {}


def already_injected(con, session_id: str) -> bool:
    return con.execute(
        "SELECT 1 FROM recall_marker WHERE session_id=?", (session_id,)
    ).fetchone() is not None


def mark_injected(con, session_id: str) -> None:
    con.execute(
        "INSERT OR IGNORE INTO recall_marker (session_id, injected_at) VALUES (?, ?)",
        (session_id, datetime.now().isoformat()),
    )
    con.commit()


def latest_other_summary(con, project_id: str, exclude_session_id: str):
    row = con.execute(
        "SELECT session_id, slots_json FROM session_summary "
        "WHERE project_id=? AND session_id != ? "
        "ORDER BY updated_at DESC LIMIT 1",
        (project_id, exclude_session_id),
    ).fetchone()
    if not row:
        return None
    return {"session_id": row[0], "slots": _load_slots(row[1])}


def format_inject(slots: dict) -> str:
    dec = slots.get("decisions") or []
    opn = slots.get("open") or []
    parts = []
    if dec:
        parts.append("■ 직전 세션 결정사항:")
        parts += [f"- {d}" for d in dec]
    if opn:
        parts.append("■ 직전 세션 미해결 과제:")
        parts += [f"- {o}" for o in opn]
    if not parts:
        return ""
    return "[헤르메스 회상] 이전 작업 맥락입니다.\n" + "\n".join(parts)


def do_inject(db_path, project_id, session_id) -> None:
    if not os.path.isfile(db_path) or not session_id:
        return
    con = connect_db(db_path)
    _ensure_schema(con)
    try:
        if already_injected(con, session_id):
            return
        summary = latest_other_summary(con, project_id, session_id)
        mark_injected(con, session_id)  # 직전 요약 유무와 무관하게 1회로 마킹
        if not summary:
            return
        # 재활용 추적(Part D): 다른 세션의 요약을 주입 = 그 원본 세션을 재참조.
        # 원본 세션에 last_reused_at 을 기록해 ② 미사용 신호를 공급한다.
        if mark_reused is not None:
            ensure_reuse_table(con)
            mark_reused(con, [summary["session_id"]])
        block = format_inject(summary["slots"])
        if block:
            print(block)
    finally:
        con.close()


def do_query(db_path, query) -> None:
    if not os.path.isfile(db_path):
        print("[hermes-recall] DB 없음")
        return
    con = connect_db(db_path)
    _ensure_schema(con)
    rows = con.execute(
        "SELECT session_id, slots_json FROM session_summary "
        "WHERE slots_json LIKE ? ORDER BY updated_at DESC LIMIT 5",
        (f"%{query}%",),
    ).fetchall()
    con.close()
    if not rows:
        print(f"[hermes-recall] '{query}' 일치 요약 없음")
        return
    for sid, raw in rows:
        print(f"== {sid} ==")
        print(format_inject(_load_slots(raw)) or "(요약 비어있음)")
        print("")


def main():
    parser = argparse.ArgumentParser(description="헤르메스 회상")
    parser.add_argument("--db", required=True)
    parser.add_argument("--inject", action="store_true")
    parser.add_argument("--query", default="")
    parser.add_argument("--project-id", default="")
    parser.add_argument("--session-id", default="")
    args = parser.parse_args()

    if args.inject:
        do_inject(args.db, args.project_id, args.session_id)
    elif args.query:
        do_query(args.db, args.query)
    else:
        print("[hermes-recall] --inject 또는 --query 필요", file=sys.stderr)


if __name__ == "__main__":
    main()
