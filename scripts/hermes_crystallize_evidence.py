#!/usr/bin/env python3
"""결정화 증거 수집 — 패턴 키의 검색어, 세션 이력 증거, 개인 층(에이전트 기억) 증거, 패턴 수.
hermes-crystallize.py 에서 떼어냈다(R-size 500 초과, 2026-09-20). 표준 모듈만 쓴다.
공개 함수 5개: derive_search_terms · fetch_evidence · fetch_memory_evidence · get_pattern_count · evidence_for
"""
import json
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


def _evidence_rows(con, term: str, limit: int) -> list:
    """한 검색어로 찾은 (출처, 문장). 공통 요약(에이전트 대화 요약 제외, C-29)과 실수 신호에서 찾는다.
    대화 원문은 저장하지 않는다(계획 carry-agent-knowledge 목표 10)."""
    like = "%" + term + "%"
    rows = [("요약", r[0]) for r in con.execute(
        "SELECT slots_json FROM session_summary WHERE slots_json LIKE ? AND (agent_id IS NULL OR agent_id = '') "
        "ORDER BY updated_at DESC LIMIT ?", (like, limit)).fetchall()]
    try:
        rows += [("신호", r[0]) for r in con.execute(
            "SELECT content FROM session_signals WHERE content LIKE ? ORDER BY ts DESC LIMIT ?", (like, limit)).fetchall()]
    except sqlite3.OperationalError:
        pass                                        # 신호 표가 아직 없음(신호가 한 번도 안 난 소우주)
    return rows


def _summary_lines(raw: str, term: str) -> list:
    """요약 5칸 중 검색어가 든 항목만."""
    try:
        data = json.loads(raw) if raw else {}
    except ValueError:
        return [raw]
    return [str(x) for v in data.values() if isinstance(v, list) for x in v if term.lower() in str(x).lower()]


def _term_snippets(con, term: str, limit: int) -> list:
    out = []
    for kind, text in _evidence_rows(con, term, limit):
        lines = _summary_lines(text, term) if kind == "요약" else [text]
        out += [f"[{kind}] {x[:300].strip()}" for x in lines]
    return out


def fetch_evidence(db_path: str, search_terms: list[str], limit: int = 5) -> str:
    if not os.path.isfile(db_path):
        return "(DB 없음)"
    try:
        con = connect_db(db_path)
        snippets: list[str] = []
        for term in search_terms[:3]:
            try:
                snippets += [e for e in _term_snippets(con, term, limit) if e not in snippets]
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
