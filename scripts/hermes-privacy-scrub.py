#!/usr/bin/env python3
"""옛 판정 표·지식 파일을 지금 규칙으로 정리한다 — 기본은 미리보기, --apply 일 때만 바꾼다.

  db     판정 표(privacy_review)에서 대기가 아닌 행의 원문을 비운다. 적용 직전에 DB 를 백업한다.
  files  지식 파일(스킬·기억·이력·대화 요약)을 지금 마스킹 규칙으로 다시 가린다. 추적 안 되는/바뀐 파일은 백업한다.

사용: python3 scripts/hermes-privacy-scrub.py db|files [--project 경로] [--apply]
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 4
"""

import argparse
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_db_backup import backup_db  # noqa: E402
from hermes_privacy_scrub_files import apply as apply_files, plan  # noqa: E402

LIST_MAX = 20   # 미리보기에 보이는 파일 수 — 나머지는 개수로만 알린다
LEFTOVER = "SELECT COUNT(*) FROM privacy_review WHERE status != 'pending' AND text != ''"


def cmd_db(project: str, apply: bool) -> int:
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        print(f"DB 없음: {db}", file=sys.stderr)
        return 2
    con = sqlite3.connect(db)
    try:
        left = con.execute(LEFTOVER).fetchone()[0]
    except sqlite3.OperationalError:
        left = 0                                    # 판정 표가 아직 없다 — 비울 것도 없다
    print(f"판정 표에서 원문이 남은 비대기 행 {left}개")
    if not apply or not left:
        print("미리보기입니다. 비우려면 --apply 를 붙이십시오. (DB 는 바뀌지 않았습니다)" if not apply else "비울 것이 없습니다.")
        return 0
    backup = backup_db(con, db)
    con.execute("UPDATE privacy_review SET text = '' WHERE status != 'pending'")
    con.commit()
    print(f"원문을 비웠습니다 · 백업 {backup} (되돌리려면 이 파일로 state.db 를 바꾸십시오)")
    return 0


def cmd_files(project: str, apply: bool) -> int:
    entries = plan(project)
    print(f"지금 규칙으로 다시 가리면 달라지는 파일 {len(entries)}개")
    for rel, _, stable in entries[:LIST_MAX]:
        print("  " + rel + ("" if stable else "   ← 마스킹이 멱등이 아니라 쓰지 못합니다"))
    if not apply:
        print("미리보기입니다. 다시 가리려면 --apply 를 붙이십시오. (파일은 바뀌지 않았습니다)")
        return 0
    written, failed, backup = apply_files(project, entries)
    print(f"다시 가린 파일 {len(written)}개 · 백업 폴더 {backup} (추적 안 되던/바뀐 파일의 원본, 확인 뒤 지워도 됩니다)")
    for rel in failed:
        print(f"  실패: {rel} — 다시 가려도 또 달라집니다(마스킹 규칙 결함). 보고해 주십시오.", file=sys.stderr)
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="옛 판정 표·지식 파일 정리")
    ap.add_argument("cmd", choices=("db", "files"))
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--apply", action="store_true", help="실제로 바꾼다(기본은 미리보기)")
    args = ap.parse_args()
    run = cmd_db if args.cmd == "db" else cmd_files
    return run(os.path.abspath(args.project), args.apply)


if __name__ == "__main__":
    sys.exit(main())
