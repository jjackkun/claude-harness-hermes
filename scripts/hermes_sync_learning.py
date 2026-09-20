#!/usr/bin/env python3
"""발전 재료(세션 요약 · 패턴 수)를 운반 조각으로 내고 되넣는다 (T-17, 계획 2026-09-20-transport-plain 목표 1).

왜 따로: 결정화·드림·강등은 `session_summary`·`pattern_count` 에서 나온다. 이 둘이 컴퓨터를 따라가지 않으면
A 에서 2번 본 패턴과 B 에서 1번 본 패턴이 합쳐지지 않아 다중 컴퓨터 학습이 끊긴다(2026-09-20 실측).
원격 배치:
  summary/<session_id>/<updated_at 압축>.json   요약 한 판 = 파일 1개. 같은 세션이 갱신되면 새 파일. 받는 쪽은 updated_at 최신만 반영
  pattern/<key 해시>/<count>-<crystallized>.json  패턴 수가 오를 때마다 새 파일. 받는 쪽은 키별 max(count)·max(crystallized)
자유 글(slots_json · pattern_key)은 `lock` 이 있으면 암호문, 없으면(평문 모드, T-18) 그대로.
공개 함수 4개: outgoing_learning · import_learning · seal_text · open_text(운반 모듈이 같은 규칙으로 잠그고 푼다)
"""
import hashlib
import json
import sqlite3

import hermes_crypto as crypto
from hermes_keys import key_path

_SUMMARY_SQL = """
CREATE TABLE IF NOT EXISTS session_summary (
  session_id     TEXT PRIMARY KEY,
  project_id     TEXT,
  slots_json     TEXT,
  last_msg_count INTEGER DEFAULT 0,
  turn_count     INTEGER DEFAULT 0,
  updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS pattern_count (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern_key  TEXT NOT NULL UNIQUE,
  count        INTEGER DEFAULT 1,
  last_seen    DATETIME DEFAULT CURRENT_TIMESTAMP,
  crystallized INTEGER DEFAULT 0
);
"""


def seal_text(lock: str, text):
    """자물쇠가 있으면 암호문, 없으면 그대로(평문 모드)."""
    if not text or not lock:
        return text
    return crypto.encrypt_to([lock], text.encode(), armor=True).decode()


def open_text(universe_id: str, text):
    """암호문이면 마스터로 풀고, 평문이면 그대로. 열쇠가 없는 컴퓨터는 평문만 읽는다."""
    if not text or not str(text).startswith("-----BEGIN AGE"):
        return text
    return crypto.decrypt_with(key_path(universe_id, "master"), text.encode()).decode()


def _stamp(value) -> str:
    return "".join(ch for ch in str(value or "0") if ch.isalnum())


def outgoing_learning(con, lock, done: set, project: str = None) -> dict:
    """아직 올리지 않은 요약·패턴을 {원격 경로: 바이트} 로. 자유 글은 업로드 직전 마스킹(T-20) 뒤 잠근다."""
    try:
        from hermes_redact import redact
    except ImportError:
        redact = None
    def free(text):
        if text and redact is not None:
            text = redact(text, project_dir=project)
        return seal_text(lock, text)
    out = {}
    try:
        rows = con.execute("SELECT session_id, project_id, slots_json, last_msg_count, turn_count, updated_at "
                           "FROM session_summary").fetchall()
    except sqlite3.OperationalError:
        rows = []
    for sid, pid, slots, lmc, tc, upd in rows:
        remote = f"summary/{sid}/{_stamp(upd)}.json"
        if remote in done:
            continue
        body = {"session_id": sid, "project_id": pid, "slots_json": free(slots),
                "last_msg_count": lmc, "turn_count": tc, "updated_at": upd}
        out[remote] = json.dumps(body, ensure_ascii=False, sort_keys=True).encode()
    try:
        rows = con.execute("SELECT pattern_key, count, last_seen, crystallized FROM pattern_count").fetchall()
    except sqlite3.OperationalError:
        rows = []
    for key, cnt, seen, cry in rows:
        digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
        remote = f"pattern/{digest}/{int(cnt or 0)}-{int(cry or 0)}.json"
        if remote in done:
            continue
        body = {"pattern_key": free(key), "count": cnt, "last_seen": seen, "crystallized": cry}
        out[remote] = json.dumps(body, ensure_ascii=False, sort_keys=True).encode()
    return out


def import_learning(con, universe_id: str, remote: str, data: bytes, when: str) -> bool:
    """summary/·pattern/ 조각을 되넣는다. 요약은 updated_at 최신만, 패턴은 키별 max. 받은 경로는 sync_cursor 에 적는다."""
    try:
        body = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return False
    con.executescript(_SUMMARY_SQL)
    if remote.startswith("summary/"):
        slots = open_text(universe_id, body.get("slots_json"))
        sid, upd = body.get("session_id"), body.get("updated_at") or ""
        if not sid:
            return False
        cur = con.execute("SELECT updated_at FROM session_summary WHERE session_id = ?", (sid,)).fetchone()
        if not cur or (cur[0] or "") < upd:
            con.execute("INSERT OR REPLACE INTO session_summary "
                        "(session_id, project_id, slots_json, last_msg_count, turn_count, updated_at) VALUES (?,?,?,?,?,?)",
                        (sid, body.get("project_id"), slots, body.get("last_msg_count") or 0,
                         body.get("turn_count") or 0, upd))
    elif remote.startswith("pattern/"):
        key = open_text(universe_id, body.get("pattern_key"))
        if not key:
            return False
        con.execute("INSERT INTO pattern_count (pattern_key, count, last_seen, crystallized) VALUES (?,?,?,?) "
                    "ON CONFLICT(pattern_key) DO UPDATE SET count = max(count, excluded.count), "
                    "crystallized = max(crystallized, excluded.crystallized), "
                    "last_seen = max(coalesce(last_seen, ''), coalesce(excluded.last_seen, ''))",
                    (key, int(body.get("count") or 0), body.get("last_seen"), int(body.get("crystallized") or 0)))
    else:
        return False
    con.execute("INSERT OR REPLACE INTO sync_cursor (path, imported_at) VALUES (?, ?)", (remote, when))
    con.commit()
    return True
