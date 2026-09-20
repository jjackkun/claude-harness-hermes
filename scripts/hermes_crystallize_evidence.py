#!/usr/bin/env python3
"""결정화 증거 수집 — 패턴 키의 검색어, 세션 이력 증거, 개인 층(에이전트 기억) 증거, 패턴 수.
hermes-crystallize.py 에서 떼어냈다(R-size 500 초과, 2026-09-20). 표준 모듈만 쓴다.
공개 함수 5개: derive_search_terms · fetch_evidence · fetch_memory_evidence · get_pattern_count · evidence_for
"""
import os
import re
import sqlite3
import sys


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    print(f"[hermes-crystallize] {msg}", file=sys.stderr)


def derive_search_terms(key: str) -> list[str]:
    """임의 패턴 키에서 검색 토큰 목록을 도출한다."""
    tokens = re.split(r"[-_\s]+", key)
    terms = [key.replace("-", " "), key]
    terms += [t for t in tokens if len(t) >= 2]
    seen: set[str] = set()
    result = []
    for t in terms:
        if t not in seen:
            seen.add(t)
            result.append(t)
    return result[:5]


def fetch_evidence(db_path: str, search_terms: list[str], limit: int = 5) -> str:
    if not os.path.isfile(db_path):
        return "(DB 없음)"
    try:
        con = connect_db(db_path)
        snippets: list[str] = []
        for term in search_terms[:3]:
            try:
                # FTS5 MATCH 는 하이픈 등을 구문으로 해석하므로 phrase 인용 필수
                rows = con.execute(
                    "SELECT role, content FROM session_history "
                    "WHERE session_history MATCH ? "
                    "ORDER BY timestamp DESC LIMIT ?",
                    ('"' + term.replace('"', '""') + '"', limit),
                ).fetchall()
                for role, content in rows:
                    short = content[:300].replace("\n", " ").strip()
                    entry = f"[{role}] {short}"
                    if entry not in snippets:
                        snippets.append(entry)
                if len(snippets) >= limit:
                    break
            except Exception as e:
                _log(f"증거 검색 실패(term={term}): {e}")
                continue
        con.close()
        return "\n".join(f"- {s}" for s in snippets[:limit]) if snippets else "(기록 없음)"
    except Exception as e:
        _log(f"증거 조회 DB 오류: {e}")
        return "(DB 쿼리 실패)"


def get_pattern_count(db_path: str, key: str) -> int:
    try:
        con = connect_db(db_path)
        row = con.execute(
            "SELECT count FROM pattern_count WHERE pattern_key=?", (key,)
        ).fetchone()
        con.close()
        return row[0] if row else 0
    except Exception as e:
        _log(f"pattern_count 조회 실패({key}): {e}")
        return 0


def fetch_memory_evidence(db_path: str, agent_id: str, about: str, limit: int = 10) -> str:
    """개인 스킬 결정화(C-21)의 증거는 그 에이전트의 같은 about 기억(철회되지 않은 것)이다 — 대화 원문이 아니다."""
    con = connect_db(db_path)
    try:
        rows = con.execute(
            "SELECT ts, body FROM memory_events WHERE agent_id=? AND about=? AND kind='memory.added' "
            "AND memory_id NOT IN (SELECT revises FROM memory_events WHERE kind='memory.retracted' AND revises IS NOT NULL) "
            "ORDER BY ts DESC LIMIT ?", (agent_id, about, limit)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    finally:
        con.close()
    return "\n".join(f"- [{ts}] {body}" for ts, body in rows)


def evidence_for(db_path: str, key: str, meta: dict, is_fallback: bool, agent_id: str, about: str):
    """(evidence, count). 개인 층은 그 에이전트의 같은 about 기억이 증거다."""
    if about:
        evidence = fetch_memory_evidence(db_path, agent_id, about)
        return evidence, max(get_pattern_count(db_path, key), len(evidence.splitlines()))
    evidence = fetch_evidence(db_path, meta["search_terms"], limit=10 if is_fallback else 5)
    return evidence, get_pattern_count(db_path, key)
