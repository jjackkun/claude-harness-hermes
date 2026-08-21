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
    from hermes_reuse import ensure_reuse_table, mark_reused
except ImportError:  # 헬퍼 미복사 시에도 회상 자체는 동작해야 한다
    ensure_reuse_table = None
    mark_reused = None

try:
    from hermes_redact import redact
except ImportError:  # 마스킹 헬퍼 부재 시 원문 스니펫을 내보내지 않는다(보수적)
    redact = None

SLOT_KEYS = ["decisions", "open", "prefs", "facts", "next"]

MAX_SESSIONS = 5           # 회상 결과로 보여줄 세션 수
MAX_QUERY_KEYWORDS = 8     # 질의 키워드 상한 — 실측상 5개를 넘으면 recall 이 평탄해진다
FTS_SCAN_LIMIT = 400       # bm25 상위 스캔 행수. 한 세션이 여러 행을 차지해도 5세션을 채운다
SNIPPET_LEN = 200          # 요약 없는 세션의 원문 스니펫 길이

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


def extract_query_keywords(query: str) -> list:
    """질의 문자열을 검색 키워드로 분해한다.

    LIKE 통짜 매칭은 사용자가 친 어순이 원문에 그대로 있어야만 걸린다. 키워드로
    쪼개야 "무효화 메모이제이션 버전" 처럼 재구성된 질의가 잡힌다.
    """
    tokens = re.findall(r"[a-z0-9가-힣_\-]+", query.lower())
    return [t for t in tokens if t not in QUERY_STOP_WORDS and len(t) >= 2]


def search_history(con, keywords: list) -> list:
    """1단계 — 대화 원문(FTS5)에서 관련 세션을 bm25 관련도순으로 찾는다.

    반환: [(session_id, 관련도 최상위 행의 content)] — content 는 스니펫 폴백에 재사용한다.
    """
    if not keywords:
        return []
    match = " OR ".join('"%s"' % kw.replace('"', "") for kw in keywords)
    try:
        rows = con.execute(
            "SELECT session_id, content FROM session_history "
            "WHERE session_history MATCH ? ORDER BY bm25(session_history) LIMIT ?",
            (match, FTS_SCAN_LIMIT),
        ).fetchall()
    except sqlite3.OperationalError:
        return []  # FTS5 미탑재 빌드 — 요약 검색만으로 계속한다

    found, seen = [], set()
    for sid, content in rows:
        if sid in seen:
            continue
        seen.add(sid)
        found.append((sid, content or ""))
        if len(found) >= MAX_SESSIONS:
            break
    return found


def search_summaries(con, keywords: list) -> list:
    """2단계 — 요약문에만 있는 어휘를 보완한다.

    요약은 원문의 재서술이라 원문에 없는 표현을 쓸 수 있다(요약기가 고른 단어).
    원문 검색으로 갈아끼우기만 하면 그 어휘가 통째로 사라지므로 합집합으로 남긴다.
    """
    if not keywords:
        return []
    found = []
    for kw in keywords:
        for (sid,) in con.execute(
            "SELECT session_id FROM session_summary "
            "WHERE slots_json LIKE ? ORDER BY updated_at DESC LIMIT ?",
            ("%" + kw + "%", MAX_SESSIONS),
        ):
            if sid not in found:
                found.append(sid)
    return found


def format_snippet(content: str, db_path: str) -> str:
    """요약이 없는 세션을 원문 스니펫으로 보여준다.

    원문은 시크릿 관문을 아직 통과하지 않은 구간이라 마스킹 없이는 내보내지 않는다.
    """
    if redact is None:
        return "(요약 없음 — 마스킹 헬퍼 부재로 원문 생략)"
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(db_path)))
    return "■ 원문 발췌:\n- " + redact(content[:SNIPPET_LEN], project_dir)


def do_query(db_path, query) -> None:
    if not os.path.isfile(db_path):
        print("[hermes-recall] DB 없음")
        return
    con = connect_db(db_path)
    _ensure_schema(con)
    try:
        keywords = extract_query_keywords(query)[:MAX_QUERY_KEYWORDS]
        hits = search_history(con, keywords)
        snippets = dict(hits)
        ordered = [sid for sid, _ in hits]
        for sid in search_summaries(con, keywords):
            if sid not in ordered:
                ordered.append(sid)
        ordered = ordered[:MAX_SESSIONS]

        if not ordered:
            print("[hermes-recall] '%s' 일치 기록 없음" % query)
            return

        for sid in ordered:
            row = con.execute(
                "SELECT slots_json FROM session_summary WHERE session_id=?", (sid,)
            ).fetchone()
            print("== %s ==" % sid)
            block = format_inject(_load_slots(row[0])) if row else ""
            print(block or format_snippet(snippets.get(sid, ""), db_path))
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
