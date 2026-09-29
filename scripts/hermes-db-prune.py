#!/usr/bin/env python3
"""할 일 없어진 DB 표를 걷는다 — 기본은 미리보기, --apply 일 때만 백업 뒤 지우고 용량을 돌려받는다.

걷는 표: session_history(지운 원문의 검색 색인 — 행은 0 인데 조각이 DB 의 대부분을 차지한다) · harness_rules ·
compaction_log · session_reuse. 프로젝트 DB 는 넷 모두, 전역 DB(--global)는 harness_rules 만 남긴다 —
전역의 harness_rules 는 옛 행이 있고 /hermes-status 의 "전역 패턴" 줄이 읽는다.
다시 돌려도 안전하다(이미 없는 표는 건너뛴다).

사용: python3 scripts/hermes-db-prune.py [--project 경로 | --global] [--apply]
계획: docs/exec-plans/completed/2026-09-29-drop-dead-tables.md 목표 3
"""

import argparse
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_db_backup import backup_db  # noqa: E402

PROJECT_DEAD = ("session_history", "harness_rules", "compaction_log", "session_reuse")
GLOBAL_DEAD = ("session_history", "compaction_log", "session_reuse")   # harness_rules 는 옛 행 보존
GLOBAL_DB = os.path.join("~", ".hermes", "global.db")
BUSY_MS = int(os.environ.get("HERMES_PRUNE_BUSY_MS", "5000"))   # 훅이 DB 를 쥐고 있어도 기다리는 시간(기본은 다른 명령들의 busy_timeout 과 같다, 시험은 짧게)


def existing(con, names) -> list:
    have = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    return [n for n in names if n in have]


def row_count(con, name):
    try:
        return con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]     # name 은 위 상수 목록의 값뿐이다
    except sqlite3.OperationalError:
        return None                                                           # FTS5 모듈이 없는 빌드


def drop_all(con, names) -> list:
    """표를 지운다. 못 지운 표 [(이름, 이유)] 를 돌려준다(가상 표 모듈이 없으면 그 표만 건너뛴다)."""
    failed = []
    for name in names:
        try:
            con.execute(f"DROP TABLE IF EXISTS {name}")
        except sqlite3.OperationalError as exc:
            if "locked" in str(exc).lower():
                raise                                                         # 잠금은 표 하나의 사정이 아니라 전체 중단 사유다
            failed.append((name, str(exc)))                                   # 가상 표 모듈이 없는 빌드 등 — 그 표만 건너뛴다
    con.commit()
    return failed


def kb(path: str) -> int:
    return os.path.getsize(path) // 1024


def apply_prune(con, db: str, found: list) -> int:
    """백업 → 표 삭제 → 용량 회수. 잠겨 있으면 알리고 1, 표를 못 지운 것이 있으면 1."""
    before = kb(db)
    try:
        backup = backup_db(con, db)
        failed = drop_all(con, found)
    except sqlite3.OperationalError as exc:
        print(f"DB 가 다른 프로세스에 잠겨 있어 지우지 못했습니다({exc}) — 세션이 끝난 뒤 다시 돌리십시오.", file=sys.stderr)
        return 1
    for name, why in failed:
        print(f"  건너뜀: {name} — {why}", file=sys.stderr)
    if len(failed) == len(found):
        return 1                                                              # 지운 것이 없으면 용량 회수도 하지 않는다
    note = ""
    try:
        con.execute("VACUUM")                                                 # 표를 지워도 파일 크기는 줄지 않는다 — 여기서 돌려준다
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")                        # WAL 에 남은 분량까지 파일에 반영해 크기를 정확히 본다
    except sqlite3.OperationalError as exc:
        note = f" · 표는 지웠으나 용량 회수(VACUUM)는 실패: {exc} — 세션이 끝난 뒤 다시 돌리면 됩니다"
    print(f"지운 표 {len(found) - len(failed)}개 · {before} KB → {kb(db)} KB · 백업 {backup}{note}")
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="죽은 DB 표 정리")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--project", default=os.getcwd())
    group.add_argument("--global", dest="use_global", action="store_true", help="~/.hermes/global.db (harness_rules 는 남긴다)")
    ap.add_argument("--apply", action="store_true", help="실제로 지운다(기본은 미리보기)")
    args = ap.parse_args()
    db = os.path.expanduser(GLOBAL_DB) if args.use_global else os.path.join(os.path.abspath(args.project), ".hermes", "state.db")
    if not os.path.isfile(db):
        print(f"DB 없음: {db}", file=sys.stderr)
        return 2
    con = sqlite3.connect(db, timeout=BUSY_MS / 1000)
    found = existing(con, GLOBAL_DEAD if args.use_global else PROJECT_DEAD)
    if not found:
        print("지울 표가 없습니다.")
        return 0
    print(f"{db} ({kb(db)} KB)")
    for name in found:
        count = row_count(con, name)
        print(f"  {name}: {'?' if count is None else count}행")
    if not args.apply:
        print("미리보기입니다. 지우려면 --apply 를 붙이십시오. (DB 는 바뀌지 않았습니다)")
        return 0
    return apply_prune(con, db, found)


if __name__ == "__main__":
    sys.exit(main())
