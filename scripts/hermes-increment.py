#!/usr/bin/env python3
"""헤르메스 패턴 카운트 즉시 증가 스크립트.

UserPromptSubmit hook 에서 실수 감지 시 호출.
pattern_count 테이블에 key 를 즉시 +1 기록한다.

crystallized != 0 (이미 결정화/거부) 패턴은 증가·재출력하지 않는다 (M5) —
hermes-save-session.py 의 `WHERE crystallized=0` 가드와 일치.

사용법:
  python3 hermes-increment.py --db PATH --key KEY [--description DESC]
"""

import argparse
import sqlite3
import sys
from datetime import datetime, timezone


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def increment(db_path: str, key: str):
    """카운트 증가. (count, crystallized) 반환 — crystallized != 0 이면 증가 안 함."""
    conn = connect_db(db_path)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO pattern_count (pattern_key, count, last_seen)
        VALUES (?, 1, ?)
        ON CONFLICT(pattern_key) DO UPDATE SET
            count = count + 1,
            last_seen = excluded.last_seen
        WHERE crystallized = 0
        """,
        (key, datetime.now(timezone.utc).isoformat(sep=" ", timespec="seconds")),
    )
    conn.commit()
    cur.execute(
        "SELECT count, crystallized FROM pattern_count WHERE pattern_key = ?", (key,)
    )
    row = cur.fetchone()
    conn.close()
    return (row[0], row[1]) if row else (1, 0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--description", default="")
    args = parser.parse_args()

    try:
        count, crystallized = increment(args.db, args.key)
        if crystallized != 0:
            state = "결정화됨" if crystallized == 1 else "거부됨"
            print(f"[hermes] pattern '{args.key}' 은 이미 {state} — 집계 제외", file=sys.stderr)
            return
        print(f"[hermes] pattern '{args.key}' count={count}", file=sys.stderr)
        if count >= 3:
            print(f"[hermes] CRYSTALLIZE:{args.key}", file=sys.stderr)
    except Exception as e:
        print(f"[hermes] increment error: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
