#!/usr/bin/env python3
"""회상 표시(recall_marker)에 쌓인 가짜 세션 ID 를 정리한다 — 기본은 미리보기, --apply 일 때만 지운다.

세션 ID 가 아니라 프롬프트 조각이 표시로 쌓인 것을 지운다(2026-09-29: 공장 203건 중 176건).
진짜 세션 ID 는 UUID 모양이므로 UUID 모양이 아닌 행만 대상이다. 진짜 ID 가 UUID 가 아닌 환경이면
진짜 행이 지워질 수 있으므로 미리보기가 표본을 보여 주고, --apply 는 지우기 직전에 DB 를 백업한다.

사용: python3 scripts/hermes-recall-repair.py [--db .hermes/state.db] [--apply]
"""

import argparse
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_db_backup import backup_db  # noqa: E402

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SAMPLE_COUNT = 5  # 미리보기에 보이는 가짜 행 표본 수 — 사람이 눈으로 확인하기에 충분한 최소한
SAMPLE_WIDTH = 60  # 표본 한 줄 표시 폭


def fake_ids(con) -> list:
    return [r[0] for r in con.execute("SELECT session_id FROM recall_marker") if not UUID_RE.match(r[0] or "")]


def show(ids: list) -> None:
    for sid in ids[:SAMPLE_COUNT]:
        print("  표본: " + repr(sid)[:SAMPLE_WIDTH])


def delete_fake(con, ids: list) -> int:
    con.executemany("DELETE FROM recall_marker WHERE session_id = ?", [(i,) for i in ids])
    con.commit()
    return len(ids)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=".hermes/state.db")
    ap.add_argument("--apply", action="store_true", help="실제로 지운다(기본은 미리보기)")
    args = ap.parse_args()
    if not os.path.isfile(args.db):
        print(f"DB 없음: {args.db}", file=sys.stderr)
        return 2
    con = sqlite3.connect(args.db)
    total = con.execute("SELECT COUNT(*) FROM recall_marker").fetchone()[0]
    ids = fake_ids(con)
    print(f"회상 표시 {total}건 중 세션 ID 가 아닌 것 {len(ids)}건")
    show(ids)
    if not args.apply:
        print("미리보기입니다. 지우려면 --apply 를 붙이십시오. (DB 는 바뀌지 않았습니다)")
        return 0
    if not ids:
        print("지울 것이 없습니다.")
        return 0
    backup = backup_db(con, args.db)
    print(f"지운 행 {delete_fake(con, ids)}건 · 백업 {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
