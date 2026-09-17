"""journal_events 의 옛 CHECK 제약을 새 KINDS 로 옮기는 마이그레이션만 담당한다.

SQLite 는 CHECK 를 ALTER 로 못 바꾼다. RENAME 방식은 중간에 죽으면 `journal_events` 가
사라진 채 남아 `schema_disabled`(rollback 사본 이름 규칙)와 어긋난다. 그래서
새 표 생성 → 복사 → 옛 표 DROP → 이름 되돌리기를 **한 트랜잭션**으로 묶는다 —
어디서 죽어도 원상이다. 인덱스·추가전용 트리거는 호출측 ensure_schema 가 다시 만든다.
(계획 2026-09-17-design-coverage-gaps 목표 3)
"""

_TABLE = "journal_events"
_STAGING = "journal_events_new"


def needs_migration(con, kinds) -> bool:
    """표가 있고, 그 CREATE 문에 KINDS 중 하나라도 빠져 있으면 True."""
    row = con.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?", (_TABLE,)
    ).fetchone()
    if not row or not row[0]:
        return False
    return not all(f"'{k}'" in row[0] for k in kinds)


def _create_staging_sql(schema_sql: str) -> str:
    create = schema_sql.strip().split(";")[0]
    head = f"CREATE TABLE IF NOT EXISTS {_TABLE}"
    if not create.startswith(head):
        raise RuntimeError("SCHEMA_SQL 의 첫 문장이 journal_events CREATE 가 아니다")
    return create.replace(head, f"CREATE TABLE {_STAGING}", 1)


def migrate_kind_check(con, schema_sql: str, kinds) -> bool:
    """옮겼으면 True, 할 일이 없었으면 False. 실패하면 롤백하고 예외를 올린다."""
    if not needs_migration(con, kinds):
        return False
    cols = [r[1] for r in con.execute(f"PRAGMA table_info({_TABLE})")]
    col_list = ", ".join(cols)
    saved = con.isolation_level
    con.isolation_level = None          # 자동 트랜잭션을 끄고 손으로 묶는다
    try:
        con.execute("BEGIN IMMEDIATE")
        con.execute(f"DROP TABLE IF EXISTS {_STAGING}")   # 이전 실패의 잔해
        con.execute(_create_staging_sql(schema_sql))
        con.execute(f"INSERT INTO {_STAGING} ({col_list}) SELECT {col_list} FROM {_TABLE}")
        before = con.execute(f"SELECT count(*) FROM {_TABLE}").fetchone()[0]
        after = con.execute(f"SELECT count(*) FROM {_STAGING}").fetchone()[0]
        if before != after:
            raise RuntimeError(f"복사 행 수 불일치 {before}→{after}")
        con.execute(f"DROP TABLE {_TABLE}")            # 트리거·인덱스도 같이 사라진다(DROP 은 트리거를 안 태운다)
        con.execute(f"ALTER TABLE {_STAGING} RENAME TO {_TABLE}")
        con.execute("COMMIT")
        return True
    except Exception:
        con.execute("ROLLBACK")
        raise
    finally:
        con.isolation_level = saved


__all__ = ["needs_migration", "migrate_kind_check"]
