"""사람이 정한 판정(둠·지움)을 운반 조각으로 내고, 받은 조각을 판정 표에 넣는 것만 담당한다.

조각: `decision/<문장 해시>/<결정 시각 압축>-<상태>.json` = {hash, status, decided_at} — **원문이 없다.**
경로에 상태를 넣어, 두 컴퓨터가 같은 초에 다른 결정을 내려도 서로 다른 경로가 되게 한다(같은 경로에 다른 내용이 겹치지 않게).
기계 판정(clean·pending)은 규칙 버전에 따라 달라지므로 나르지 않는다. 사람의 결정은 의도라 규칙이 바뀌어도 유효하다.
받는 규칙(한 문장 UPSERT): 행이 없으면 만든다 · 기계 판정은 사람 결정이 덮고 원문을 비운다 ·
사람 결정끼리는 결정 시각이 더 새로운 쪽이 이기고, **같은 시각이면 지움(drop)이 이긴다** — 어느 컴퓨터가 받아도 같은 상태로 수렴하고 안전한 쪽이다.
잘못된 조각(해시 모양 아님 · keep/drop 아님 · 시각 없음)은 받지 않는다 — 특히 clean 을 심을 수 없다.
계획: docs/exec-plans/completed/2026-09-29-carry-privacy-decisions.md

공개: PREFIX · outgoing_decisions · import_decision
"""

import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_privacy_pending import ensure_table  # noqa: E402

PREFIX = "decision/"
_HASH_RE = re.compile(r"^[0-9a-f]{32}$")            # text_hash 는 sha256 앞 32자(16진)
_HUMAN = ("keep", "drop")
# 결정 시각 형식: `decide` 가 쓰는 SQLite CURRENT_TIMESTAMP(UTC). 글자로 비교하므로 형식이 다르면 순서가 틀리다 → 이 모양만 받는다.
_WHEN_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")


def _stamp(value) -> str:
    return "".join(ch for ch in str(value or "0") if ch.isalnum())


def outgoing_decisions(con, done: set) -> dict:
    """아직 올리지 않은 사람 결정 {원격 경로: 바이트}. 판정 표가 아직 없으면 빈 결과."""
    try:
        rows = con.execute("SELECT hash, status, ts FROM privacy_review WHERE status IN ('keep','drop')").fetchall()
    except sqlite3.OperationalError:
        return {}
    out = {}
    for hash_, status, when in rows:
        remote = f"{PREFIX}{hash_}/{_stamp(when)}-{status}.json"
        if remote not in done:
            out[remote] = json.dumps({"hash": hash_, "status": status, "decided_at": when},
                                     ensure_ascii=False, sort_keys=True).encode()
    return out


def _valid(body: dict) -> bool:
    when = body.get("decided_at")
    return (isinstance(body.get("hash"), str) and bool(_HASH_RE.match(body["hash"]))
            and body.get("status") in _HUMAN
            and isinstance(when, str) and bool(_WHEN_RE.match(when)))


def import_decision(con, body: dict) -> bool:
    """받은 결정 한 건을 판정 표에 넣는다. 받을 수 없는 조각이면 False."""
    if not _valid(body):
        return False
    ensure_table(con)
    con.execute("INSERT INTO privacy_review (hash, kind, ref, text, status, ts) VALUES (?, 'decision', '', '', ?, ?) "
                "ON CONFLICT(hash) DO UPDATE SET status=excluded.status, text='', ts=excluded.ts "
                "WHERE privacy_review.status NOT IN ('keep','drop') OR privacy_review.ts < excluded.ts "
                "OR (privacy_review.ts = excluded.ts AND excluded.status = 'drop')",
                (body["hash"], body["status"], body["decided_at"]))
    return True
