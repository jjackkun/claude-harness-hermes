#!/usr/bin/env python3
"""헤르메스 세션 재활용 추적 공유 헬퍼.

오래된 세션이 이후 recall 로 다시 참조되면 last_reused_at 을 기록한다 —
생애주기 린트(Part D) ② 미사용 신호의 세션 단위 근거를 공급한다.
recall·lint 등 여러 소비처가 import 해 공유한다 (hermes_skills.py 선례).

con 을 인자로 받는다 — 자체 DB 접속·import 부수효과 없음.
"""

import sqlite3
from datetime import datetime

# tracking_epoch 마커: session_reuse 를 처음 만든 순간이 "재활용을 관측하기
# 시작한 원년". 예약 session_id 로 저장해 일반 세션과 구분한다
# (mark_reused 에서 입력 제외). D1 데드락 방지 — epoch 는 T1(추적 도입 시점)이 찍는다.
EPOCH_MARKER = "__epoch__"


def _now_iso() -> str:
    # naive local — session_history ts 와 tz 정합
    return datetime.now().isoformat()


def ensure_reuse_table(con: sqlite3.Connection) -> None:
    """session_reuse 를 자가수리 생성하고, 최초 1회 tracking_epoch 마커를 찍는다.

    init.py 만 고치면 기존 DB 가 안 따라오므로(Part B 교훈) 소비처에서
    CREATE IF NOT EXISTS 로 자가수리한다. 멱등: 이미 __epoch__ 행이 있으면
    갱신하지 않는다.
    """
    con.execute("""
        CREATE TABLE IF NOT EXISTS session_reuse (
            session_id     TEXT PRIMARY KEY,
            last_reused_at TEXT,
            reuse_count    INTEGER DEFAULT 0
        )
    """)
    # tracking_epoch 마커 — 없을 때만 최초 1회 기록(INSERT OR IGNORE 로 멱등)
    con.execute(
        "INSERT OR IGNORE INTO session_reuse (session_id, last_reused_at, reuse_count) "
        "VALUES (?, ?, 0)",
        (EPOCH_MARKER, _now_iso()),
    )
    con.commit()


def mark_reused(con: sqlite3.Connection, session_ids) -> None:
    """각 session_id 를 UPSERT — last_reused_at=now, reuse_count+=1.

    __epoch__ 마커는 세션으로 취급하지 않으므로 입력에서 제외한다.
    자가수리 CREATE IF NOT EXISTS 를 선행한다.
    """
    ensure_reuse_table(con)
    now = _now_iso()
    for sid in session_ids:
        if not sid or sid == EPOCH_MARKER:
            continue
        con.execute(
            "INSERT INTO session_reuse (session_id, last_reused_at, reuse_count) "
            "VALUES (?, ?, 1) "
            "ON CONFLICT(session_id) DO UPDATE SET "
            "last_reused_at=excluded.last_reused_at, reuse_count=reuse_count+1",
            (sid, now),
        )
    con.commit()


def get_tracking_epoch(con: sqlite3.Connection):
    """tracking_epoch 마커 시각(str)을 반환한다. 없으면 None (→ 압축 후보 0)."""
    row = con.execute(
        "SELECT last_reused_at FROM session_reuse WHERE session_id=?",
        (EPOCH_MARKER,),
    ).fetchone()
    return row[0] if row else None
