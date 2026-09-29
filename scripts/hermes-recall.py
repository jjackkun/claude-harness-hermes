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
import re
import sqlite3
import sys
from datetime import datetime

try:
    from hermes_summary_owner import ensure_agent_column
except ImportError:  # 헬퍼 미복사 — 칸 없이도 회상은 돈다(아래 조회는 칸이 있을 때만 거른다)
    ensure_agent_column = None

SLOT_KEYS = ["decisions", "open", "prefs", "facts", "next"]


def _common_only(con) -> str:
    """공통 요약만(C-29) — 에이전트의 대화는 그 에이전트 출근 본문으로만 간다.
    칸이 없으면(도우미 미복사로 칸을 못 더한 옛 DB) 모두 공통이므로 거를 것이 없다 — 칸을 가정하면 회상이 죽는다(코드 리뷰 HIGH)."""
    cols = [r[1] for r in con.execute("PRAGMA table_info(session_summary)")]
    return "agent_id IS NULL" if "agent_id" in cols else "1=1"

MAX_SESSIONS = 5           # 회상 결과로 보여줄 세션 수
MAX_QUERY_KEYWORDS = 8     # 질의 키워드 상한 — 실측상 5개를 넘으면 recall 이 평탄해진다

# 질의 불용어. 규칙은 hermes-search.py:extract_keywords 와 같은 계열이다.
QUERY_STOP_WORDS = {
    "그리고", "그래서", "하지만", "때문에", "합니다", "입니다", "있습니다",
    "the", "and", "for", "with", "this", "that",
}


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
    if ensure_agent_column is not None:
        ensure_agent_column(con)   # C-29 — 에이전트 대화 요약은 공통 회상에서 뺀다
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
        "WHERE project_id=? AND session_id != ? AND " + _common_only(con) + " "
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
        block = format_inject(summary["slots"])
        if block:
            print(block)
    finally:
        con.close()


def extract_query_keywords(query: str) -> list:
    """질의 문자열을 검색 키워드로 분해한다.

    LIKE 통짜 매칭은 사용자가 친 어순이 원문에 그대로 있어야만 걸린다. 키워드로
    쪼개야 "무효화 메모이제이션 버전" 처럼 재구성된 질의가 잡힌다.
    """
    tokens = re.findall(r"[a-z0-9가-힣_\-]+", query.lower())
    return [t for t in tokens if t not in QUERY_STOP_WORDS and len(t) >= 2]


def search_summaries(con, keywords: list) -> list:
    """요약(5칸)에서 키워드가 든 세션을 최근순으로 찾는다. 원문은 저장하지 않으므로(T-23) 회상 검색은 요약뿐이다."""
    if not keywords:
        return []
    found = []
    for kw in keywords:
        for (sid,) in con.execute(
            "SELECT session_id FROM session_summary "
            "WHERE slots_json LIKE ? AND " + _common_only(con) + " ORDER BY updated_at DESC LIMIT ?",
            ("%" + kw + "%", MAX_SESSIONS),
        ):
            if sid not in found:
                found.append(sid)
    return found


def do_query(db_path, query) -> None:
    if not os.path.isfile(db_path):
        print("[hermes-recall] DB 없음")
        return
    con = connect_db(db_path)
    _ensure_schema(con)
    try:
        keywords = extract_query_keywords(query)[:MAX_QUERY_KEYWORDS]
        ordered = search_summaries(con, keywords)[:MAX_SESSIONS]

        if not ordered:
            print("[hermes-recall] '%s' 일치 기록 없음" % query)
            return

        for sid in ordered:
            row = con.execute(
                "SELECT slots_json FROM session_summary WHERE session_id=?", (sid,)
            ).fetchone()
            print("== %s ==" % sid)
            print(format_inject(_load_slots(row[0])) if row else "")
            print("")
    finally:
        con.close()


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
