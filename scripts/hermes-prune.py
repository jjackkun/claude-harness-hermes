#!/usr/bin/env python3
"""헤르메스 스킬 정리 — 측정 신호 기반 강등·톰브스톤.

active → demoted: noop_count >= NOOP_DEMOTE AND helpful_count = 0
demoted → tombstoned: last_helpful_at 없음 AND (now - demoted_at) > TOMBSTONE_DAYS

파일은 절대 삭제하지 않는다(되돌림 가능). 멱등 — 반복 실행해도 부작용 없음.
비차단 — 항상 exit 0.

임계값 근거:
  NOOP_DEMOTE=5      일회성 노이즈와 지속 무용을 가르는 최소 표본 수.
  TOMBSTONE_DAYS=14  한 스프린트(2주) 동안 한 번도 도움 안 됐으면 휴면 간주.
env HERMES_NOOP_DEMOTE / HERMES_TOMBSTONE_DAYS 로 오버라이드.

사용법:
  python3 hermes-prune.py --db PATH
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timezone

NOOP_DEMOTE = int(os.environ.get("HERMES_NOOP_DEMOTE", "5"))
TOMBSTONE_DAYS = int(os.environ.get("HERMES_TOMBSTONE_DAYS", "14"))


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    print(f"[hermes-prune] {msg}", file=sys.stderr)


def prune(db_path: str) -> None:
    if not os.path.isfile(db_path):
        return
    now = datetime.now(timezone.utc).isoformat()
    try:
        con = connect_db(db_path)
        # 1) active → demoted
        con.execute(
            "UPDATE skill_index SET state='demoted', demoted_at=? "
            "WHERE COALESCE(state,'active')='active' "
            "AND noop_count >= ? AND helpful_count = 0",
            (now, NOOP_DEMOTE),
        )
        # 2) demoted → tombstoned (last_helpful_at 없음 + 강등 후 N일 경과)
        con.execute(
            "UPDATE skill_index SET state='tombstoned' "
            "WHERE state='demoted' AND last_helpful_at IS NULL "
            "AND demoted_at IS NOT NULL "
            "AND julianday(?) - julianday(demoted_at) > ?",
            (now, TOMBSTONE_DAYS),
        )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"정리 실패: {e}")


def main():
    parser = argparse.ArgumentParser(description="헤르메스 스킬 정리")
    parser.add_argument("--db", required=True)
    args = parser.parse_args()
    prune(args.db)


if __name__ == "__main__":
    main()
