#!/usr/bin/env python3
"""작업 이력 CLI — 훅·러너·사람이 부르는 진입점.

  emit      이벤트 한 건 기록
  thread    한 작업의 이벤트를 시간순으로
  graph     작업 사이 간선
  mismatch  주장 성공 · 기계 실패
  gap-check 끝나지 않은 작업에 누락 이벤트를 붙인다
  rollback  트리거가 쓰기를 막을 때 테이블 이름만 바꿔 기록을 멈춘다(보존)
계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 9·6·12·13
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_journal import JournalRejected, emit  # noqa: E402
from hermes_journal_schema import ensure_schema, schema_disabled  # noqa: E402
from hermes_journal_views import gaps, graph, mismatch, thread  # noqa: E402

_DEFAULT_STALE_MIN = None  # 실측 전까지 heartbeat 판정은 꺼 둔다(계획 §6, 목표 13)


def _db(args) -> str:
    return args.db or os.path.join(args.project, ".hermes", "state.db")


def _connect(args):
    con = sqlite3.connect(_db(args))
    if not schema_disabled(con):
        ensure_schema(con)
    return con


def _out(value) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def _stale_minutes(project: str):
    """`.hermes/journal.json` 의 heartbeat_minutes. 없으면 판정하지 않는다."""
    path = os.path.join(project, ".hermes", "journal.json")
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh).get("heartbeat_minutes")
    except (OSError, json.JSONDecodeError):
        return _DEFAULT_STALE_MIN
    try:
        return int(value)
    except (TypeError, ValueError):
        return _DEFAULT_STALE_MIN


def _cmd_emit(args) -> int:
    event = json.loads(args.json) if args.json else {}
    try:
        event_id = emit(_db(args), args.project, event)
    except JournalRejected as exc:
        print(f"[hermes-journal] 거부: {exc}", file=sys.stderr)
        return 2
    if not event_id:
        print("[hermes-journal] 이력이 꺼져 있어 건너뜀 (rollback 상태)", file=sys.stderr)
        return 0
    print(event_id)
    return 0


def _cmd_gap_check(args) -> int:
    con = _connect(args)
    if schema_disabled(con):
        return 0
    stale = args.stale_minutes if args.stale_minutes is not None else _stale_minutes(args.project)
    reason = "heartbeat-timeout" if stale is not None else "session-end"
    found = gaps(con, stale_minutes=stale)
    con.close()
    for gap in found:
        emit(_db(args), args.project, {
            "kind": "task.finished", "task_id": gap["task_id"],
            "actor": "system:claude-stop-journal-gap", "claimed": "abandoned",
            "evidence": {"reason": reason},
            "intent": f"끝나지 않은 작업 — 마지막 기록 {gap['last_ts']}",
        })
    print(len(found))
    return 0


def _cmd_rollback(args) -> int:
    if not args.confirm:
        print("[hermes-journal] --confirm 이 필요합니다 (기록은 지워지지 않고 보존됩니다)",
              file=sys.stderr)
        return 2
    con = sqlite3.connect(_db(args))
    if schema_disabled(con):
        print("이미 꺼져 있음")
        return 0
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    con.executescript(
        "DROP TRIGGER IF EXISTS journal_no_update;"
        "DROP TRIGGER IF EXISTS journal_no_delete;"
        f"ALTER TABLE journal_events RENAME TO journal_events_disabled_{stamp};"
    )
    con.commit()
    con.close()
    print(f"journal_events_disabled_{stamp}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 작업 이력")
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--db")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("emit"); p.add_argument("--json", required=True)
    for name in ("thread", "graph"):
        q = sub.add_parser(name); q.add_argument("task_id", nargs="?" if name == "graph" else None)
    sub.add_parser("mismatch")
    g = sub.add_parser("gap-check"); g.add_argument("--stale-minutes", type=int)
    r = sub.add_parser("rollback"); r.add_argument("--confirm", action="store_true")
    args = ap.parse_args()

    if args.cmd == "emit":
        return _cmd_emit(args)
    if args.cmd == "gap-check":
        return _cmd_gap_check(args)
    if args.cmd == "rollback":
        return _cmd_rollback(args)
    con = _connect(args)
    if schema_disabled(con):
        _out([])
        return 0
    _out({"thread": lambda: thread(con, args.task_id),
          "graph": lambda: graph(con, args.task_id),
          "mismatch": lambda: mismatch(con)}[args.cmd]())
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
