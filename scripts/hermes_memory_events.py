#!/usr/bin/env python3
"""기억 이벤트 `memory_events` 의 스키마와 INSERT(추가 전용)만 담당한다.

git 이 커밋마다 고유 해시를 붙여 충돌 없이 쌓듯, 기억에도 PK(UUIDv7)를 붙인다(C-14, 사용자 제안).
`MEMORY.md` 는 이 이벤트에서 계산한 **보기**이지 원본이 아니다 — 사람도 기계도 이벤트를 고쳐 쓰지
않는다. UPDATE·DELETE 는 트리거가 막는다(journal_events 와 같은 모양).
설계: docs/hermes-universe/design/agent/memory-events.md
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 8

공개 함수 4개: ensure_memory_schema · memory_disabled · record · MemoryRejected
"""

import hashlib

KINDS = ("memory.added", "memory.revised", "memory.retracted")
COLUMNS = ("memory_id", "kind", "agent_id", "universe_id", "ts",
           "about", "revises", "content_hash", "source_event", "body")

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS memory_events (
  memory_id     TEXT PRIMARY KEY,
  kind          TEXT NOT NULL CHECK (kind IN ('memory.added','memory.revised','memory.retracted')),
  agent_id      TEXT NOT NULL,
  universe_id   TEXT NOT NULL,
  ts            TEXT NOT NULL,
  about         TEXT,
  revises       TEXT,
  content_hash  TEXT,
  source_event  TEXT,
  body          TEXT
);
CREATE INDEX IF NOT EXISTS memory_agent_idx ON memory_events(agent_id, ts);
CREATE INDEX IF NOT EXISTS memory_about_idx ON memory_events(agent_id, about);
CREATE TRIGGER IF NOT EXISTS memory_no_update BEFORE UPDATE ON memory_events
  BEGIN SELECT RAISE(ABORT,'memory_events is append-only'); END;
CREATE TRIGGER IF NOT EXISTS memory_no_delete BEFORE DELETE ON memory_events
  BEGIN SELECT RAISE(ABORT,'memory_events is append-only'); END;
"""


class MemoryRejected(ValueError):
    """허용목록 밖의 값 — 기록하지 않는다."""


_PINS_SQL = """
CREATE TABLE IF NOT EXISTS memory_pins (
  agent_id   TEXT NOT NULL,
  memory_id  TEXT NOT NULL,
  pinned_at  TEXT NOT NULL,
  PRIMARY KEY (agent_id, memory_id)
);
"""


def ensure_memory_schema(con) -> None:
    con.executescript(SCHEMA_SQL)
    con.executescript(_PINS_SQL)     # 핀(주입 항상 포함, 계획 agent-teaching 목표 10) — 이벤트 표는 그대로
    con.commit()


def memory_disabled(con) -> bool:
    """tombstone rollback 상태인가 — 이름 바뀐 사본만 있고 원 테이블이 없을 때."""
    names = {r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'memory_events%'")}
    return "memory_events" not in names and any(
        n.startswith("memory_events_disabled_") for n in names)


def content_hash(body: str) -> str:
    """본문 해시 — 완전 중복(같은 문장을 두 곳에서 저장)을 '합침' 으로 묶는 보조 칸(C-15)."""
    return hashlib.sha256((body or "").encode("utf-8")).hexdigest()


def record(con, event: dict) -> str:
    """기억 이벤트 한 건을 넣고 memory_id 를 돌려준다. 최신 자동 승리는 없다 — 그냥 쌓는다."""
    if memory_disabled(con):
        return ""
    ensure_memory_schema(con)
    unknown = sorted(set(event) - set(COLUMNS))
    if unknown:
        raise MemoryRejected(f"모르는 칸: {', '.join(unknown)}")
    row = {c: event.get(c) for c in COLUMNS}
    if row["kind"] not in KINDS:
        raise MemoryRejected(f"모르는 kind: {row['kind']} (허용: {', '.join(KINDS)})")
    for required in ("memory_id", "agent_id", "universe_id", "ts"):
        if not row[required]:
            raise MemoryRejected(f"{required} 는 비울 수 없다")
    if row["body"] and not row["content_hash"]:
        row["content_hash"] = content_hash(row["body"])
    con.execute("INSERT INTO memory_events ({}) VALUES ({})".format(
        ", ".join(COLUMNS), ", ".join("?" * len(COLUMNS))), tuple(row[c] for c in COLUMNS))
    con.commit()
    return row["memory_id"]
