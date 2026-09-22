#!/usr/bin/env python3
"""사용자 성향 표(`global.db`) 읽기·쓰기와 스키마 자가수리.

Step 1 범위: 대화 기록 파일별 워터마크만. 관찰 표는 Step 2 에서 더한다.
근거: docs/exec-plans/active/2026-09-22-user-persona-distill-plan.md §4
"""

from datetime import datetime, timezone

_SCHEMA = (
    "CREATE TABLE IF NOT EXISTS persona_source_watermark ("
    " path TEXT PRIMARY KEY,"
    " line INTEGER NOT NULL,"
    " updated_at TEXT NOT NULL)"
)


def ensure_schema(con) -> None:
    """표가 없으면 만든다(멱등)."""
    con.execute(_SCHEMA)
    con.commit()


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
