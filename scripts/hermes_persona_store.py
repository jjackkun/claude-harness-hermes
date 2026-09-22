#!/usr/bin/env python3
"""사용자 성향 표(`global.db`) 읽기·쓰기와 스키마 자가수리.

표 둘: 대화 기록 파일별 워터마크, 관찰(한 발화에서 본 성향 하나 = 한 줄).
같은 성향이 여러 세션에서 반복되면 같은 key 로 여러 줄이 쌓인다 — Step 3 점수의 재료다.
성향 표는 `~/.hermes/global.db` 에 둔다. 기억 운반(sync)은 이 DB 를 읽지 않는다(목표 5).
근거: docs/exec-plans/active/2026-09-22-user-persona-distill-plan.md §4
"""

from datetime import datetime, timezone

_SCHEMAS = (
    "CREATE TABLE IF NOT EXISTS persona_source_watermark ("
    " path TEXT PRIMARY KEY,"
    " line INTEGER NOT NULL,"
    " updated_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS persona_observation ("
    " id INTEGER PRIMARY KEY AUTOINCREMENT,"
    " facet TEXT NOT NULL,"
    " key TEXT NOT NULL,"
    " statement TEXT NOT NULL,"
    " quote TEXT NOT NULL,"
    " tier TEXT NOT NULL,"
    " source_path TEXT,"
    " line INTEGER,"
    " session_id TEXT,"
    " observed_at TEXT,"
    " created_at TEXT NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_persona_observation_key ON persona_observation(facet, key)",
)

_OBS_FIELDS = ("facet", "key", "statement", "quote", "tier",
               "source_path", "line", "session_id", "observed_at")


def ensure_schema(con) -> None:
    """표가 없으면 만든다(멱등)."""
    for ddl in _SCHEMAS:
        con.execute(ddl)
    con.commit()


def add_observation(con, obs: dict) -> None:
    """관찰 한 줄을 쌓는다. 근거 인용이 없으면 ValueError — 인용 없는 성향은 추측이다."""
    if not str(obs.get("quote") or "").strip():
        raise ValueError("근거 인용(quote)이 없는 관찰은 저장하지 않는다")
    for required in ("facet", "key", "statement", "tier"):
        if not str(obs.get(required) or "").strip():
            raise ValueError(f"관찰에 {required} 가 없다")
    con.execute(
        f"INSERT INTO persona_observation ({', '.join(_OBS_FIELDS)}, created_at) "
        f"VALUES ({', '.join('?' * len(_OBS_FIELDS))}, ?)",
        tuple(obs.get(f) for f in _OBS_FIELDS) + (datetime.now(timezone.utc).isoformat(),),
    )
    con.commit()


def list_keys(con) -> list:
    """이미 있는 성향 (면, 키, 문장) — 추출 프롬프트가 같은 성향에 같은 키를 쓰게 한다."""
    return [tuple(r) for r in con.execute(
        "SELECT facet, key, MIN(statement) FROM persona_observation "
        "GROUP BY facet, key ORDER BY facet, key"
    )]


def get_watermark(con, path: str) -> int:
    """이 대화 기록 파일에서 이미 읽은 줄 수. 처음 보는 파일은 0."""
    row = con.execute(
        "SELECT line FROM persona_source_watermark WHERE path = ?", (path,)
    ).fetchone()
    return int(row[0]) if row else 0


def set_watermark(con, path: str, line: int) -> None:
    """읽은 줄 수를 기록한다."""
    con.execute(
        "INSERT INTO persona_source_watermark (path, line, updated_at) VALUES (?, ?, ?) "
        "ON CONFLICT(path) DO UPDATE SET line = excluded.line, updated_at = excluded.updated_at",
        (path, int(line), datetime.now(timezone.utc).isoformat()),
    )
    con.commit()
