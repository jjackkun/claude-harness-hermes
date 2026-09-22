#!/usr/bin/env python3
"""성향에 대한 결정(승인·거부)과 합치기 별칭을 global.db 에 둔다.

관찰(persona_observation)은 고치지 않는다 — 결정과 별칭은 따로 쌓여 언제든 되돌릴 수 있다.
결정의 주체는 둘이다: human(사람이 review 에서 정함) · auto(기계가 기준을 넘겨 정함).
라벨은 `면/키` 꼴이다.
근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md §6
"""

from datetime import datetime, timezone

_SCHEMAS = (
    "CREATE TABLE IF NOT EXISTS persona_decision ("
    " label TEXT PRIMARY KEY,"
    " state TEXT NOT NULL CHECK (state IN ('approved', 'rejected')),"
    " decided_by TEXT NOT NULL,"
    " decided_at TEXT NOT NULL)",
    "CREATE TABLE IF NOT EXISTS persona_alias ("
    " from_label TEXT PRIMARY KEY,"
    " to_label TEXT NOT NULL,"
    " decided_by TEXT NOT NULL,"
    " decided_at TEXT NOT NULL)",
)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_schema(con) -> None:
    """표가 없으면 만든다(멱등)."""
    for ddl in _SCHEMAS:
        con.execute(ddl)
    con.commit()


def set_decision(con, label: str, state: str, by: str = "human") -> None:
    """승인 또는 거부. 같은 라벨의 이전 결정은 덮는다(마지막 결정이 유효)."""
    con.execute(
        "INSERT INTO persona_decision (label, state, decided_by, decided_at) VALUES (?, ?, ?, ?) "
        "ON CONFLICT(label) DO UPDATE SET state = excluded.state, "
        "decided_by = excluded.decided_by, decided_at = excluded.decided_at",
        (label, state, by, _now()),
    )
    con.commit()


def decisions(con) -> dict:
    """라벨 → 상태(approved·rejected)."""
    return dict(con.execute("SELECT label, state FROM persona_decision"))


def set_alias(con, from_label: str, to_label: str, by: str = "human") -> None:
    """from 을 to 로 합친다. 사람이 정한 별칭이 기계 별칭을 덮는다."""
    con.execute(
        "INSERT INTO persona_alias (from_label, to_label, decided_by, decided_at) VALUES (?, ?, ?, ?) "
        "ON CONFLICT(from_label) DO UPDATE SET to_label = excluded.to_label, "
        "decided_by = excluded.decided_by, decided_at = excluded.decided_at",
        (from_label, to_label, by, _now()),
    )
    con.commit()


def aliases(con) -> dict:
    """from 라벨 → to 라벨 (사람이 정한 것만 — 기계 병합은 볼 때마다 다시 계산한다)."""
    return dict(con.execute("SELECT from_label, to_label FROM persona_alias"))
