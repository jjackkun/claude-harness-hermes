#!/usr/bin/env python3
"""올리기 전 판정 결과(문장 해시별 상태)를 DB 에 적고 읽는 것만 담당한다.

상태:
  clean   — 판정해 보니 업무 문장. 올려도 된다.
  pending — 개인적·업무 무관으로 걸렸거나 판정에 실패했다. 사람이 정하기 전엔 **파일로 나가지 않는다.**
  keep    — 사람이 "둠" 을 골랐다. 올린다.
  drop    — 사람이 "지움" 을 골랐다. 올리지 않는다.
사람의 결정(keep·drop)은 기계 판정이 덮어쓰지 않는다.
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 2 · 3

판정 표에는 **대기(pending) 문장만 원문**을 둔다(사람에게 보이려고). 통과·둠·지움은 해시만으로 충분해 원문을 비운다.
파일로 나가는 문장은 판정 전에 `scrub` 으로 지금 규칙에 맞춰 가린다 — 판정한 문장과 파일에 쓴 문장의 해시가 같아야
게이트가 통과한다. 계획: docs/exec-plans/active/2026-09-29-privacy-gate-hardening.md 목표 1·3

공개: ensure_table · text_hash · scrub · mark · status_of · allowed · pending_rows · decide
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402

_HUMAN = ("keep", "drop")
_ALLOWED = ("clean", "keep")


def ensure_table(con) -> None:
    con.execute("CREATE TABLE IF NOT EXISTS privacy_review ("
                " hash TEXT PRIMARY KEY, kind TEXT NOT NULL, ref TEXT, text TEXT NOT NULL,"
                " status TEXT NOT NULL CHECK (status IN ('clean','pending','keep','drop')),"
                " ts TEXT DEFAULT CURRENT_TIMESTAMP)")


def text_hash(text: str) -> str:
    return hashlib.sha256(str(text).strip().encode("utf-8")).hexdigest()[:32]


def scrub(text, project=None):
    """지금 마스킹 규칙으로 가린 문장. 판정·비교·쓰기가 모두 이 값을 쓴다."""
    return redact(text, project) if text else text


def mark(con, kind: str, ref: str, text: str, status: str) -> None:
    """기계 판정을 적는다(clean·pending). 사람이 이미 정한 문장은 건드리지 않는다."""
    ensure_table(con)
    kept = str(text).strip() if status == "pending" else ""     # 대기만 원문 — 나머지는 해시로 충분
    con.execute("INSERT INTO privacy_review (hash, kind, ref, text, status) VALUES (?,?,?,?,?) "
                "ON CONFLICT(hash) DO UPDATE SET status=excluded.status, text=excluded.text, ts=CURRENT_TIMESTAMP "
                "WHERE privacy_review.status NOT IN ('keep','drop')",
                (text_hash(text), kind, ref, kept, status))


def status_of(con, text: str):
    """판정 상태. 한 번도 판정하지 않았으면 None."""
    ensure_table(con)
    row = con.execute("SELECT status FROM privacy_review WHERE hash=?", (text_hash(text),)).fetchone()
    return row[0] if row else None


def allowed(con, text: str) -> bool:
    """파일·운반으로 내보내도 되는가 — 판정을 통과했거나(clean) 사람이 둠(keep). 미판정·대기·지움은 아니다."""
    return status_of(con, text) in _ALLOWED


def pending_rows(con) -> list:
    """사람이 정할 문장 [(hash, kind, ref, text)], 오래된 순."""
    ensure_table(con)
    return con.execute("SELECT hash, kind, ref, text FROM privacy_review WHERE status='pending' "
                       "ORDER BY ts, hash").fetchall()


def decide(con, hash_: str, choice: str) -> bool:
    """사람의 결정(keep·drop)을 적는다. 그런 문장이 없으면 False."""
    if choice not in _HUMAN:
        raise ValueError(f"choice 는 {_HUMAN} 중 하나: {choice}")
    ensure_table(con)
    cur = con.execute("UPDATE privacy_review SET status=?, text='', ts=CURRENT_TIMESTAMP WHERE hash=?", (choice, hash_))
    return cur.rowcount > 0
