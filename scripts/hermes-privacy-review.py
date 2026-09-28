#!/usr/bin/env python3
"""올리기 전 확인 — 검토 대기 문장을 하나씩 보이고 사람의 "지움 / 둠" 을 받는다.

  list                       대기 문장을 해시와 함께 보인다(세션 안에서는 이것을 보고 선택지로 묻는다)
  decide <해시 앞 8자> keep|drop 하나를 정한다(번호는 쓰지 않는다 — 다른 프로세스가 대기를 더하면 순서가 바뀐다)
  (인자 없음, 터미널)          하나씩 물어 정한다

지움(drop): 파일·운반으로 나가지 않는다. 기억 문장이면 memory.retracted 이벤트를 더한다(추가만 규칙).
둠(keep): 다음 내보내기 때 나간다. 같은 문장은 다시 묻지 않는다.
계획: docs/exec-plans/active/2026-09-28-carry-agent-knowledge.md 목표 3
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_privacy_pending import decide, pending_rows  # noqa: E402
from hermes_memory_events import record  # noqa: E402
from hermes_uuid7 import uuid7_str  # noqa: E402

_KIND_LABEL = {"summary": "대화 요약", "memory": "기억", "journal": "작업 이력", "skill": "스킬"}


def _retract_memory(con, memory_id: str) -> None:
    row = con.execute("SELECT agent_id, universe_id, about FROM memory_events WHERE memory_id=?",
                      (memory_id,)).fetchone()
    if not row:
        return
    record(con, {"memory_id": uuid7_str(), "kind": "memory.retracted", "agent_id": row[0],
                 "universe_id": row[1], "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                 "about": row[2], "revises": memory_id, "source_event": "privacy-review"})


def _apply(con, row, choice: str) -> None:
    hash_, kind, ref, _ = row
    decide(con, hash_, choice)
    if choice == "drop" and kind == "memory" and ref:
        _retract_memory(con, ref)
    con.commit()


def _find(rows, key: str):
    """해시 앞부분으로 찾는다. 둘 이상 맞으면 None(모호함)."""
    hits = [r for r in rows if len(key) >= 4 and r[0].startswith(key)]
    return hits[0] if len(hits) == 1 else None


def _show(rows) -> None:
    if not rows:
        print("검토 대기 없음 — 올려도 됩니다.")
        return
    print(f"올리기 전 확인할 문장 {len(rows)}개 (개인적이거나 업무와 무관해 보임):")
    for hash_, kind, ref, text in rows:
        print(f"  {hash_[:8]}  [{_KIND_LABEL.get(kind, kind)} {str(ref or '')[:12]}] {text}")
    print("정하기: python3 scripts/hermes-privacy-review.py decide <해시 앞 8자> keep|drop   (keep=둠, drop=지움)")


def _interactive(con) -> int:
    for row in pending_rows(con):
        print(f"\n[{_KIND_LABEL.get(row[1], row[1])}] {row[3]}")
        answer = input("올릴까요? 둠(k) / 지움(d) / 건너뜀(엔터): ").strip().lower()
        if answer in ("k", "keep", "둠"):
            _apply(con, row, "keep")
        elif answer in ("d", "drop", "지움"):
            _apply(con, row, "drop")
    _show(pending_rows(con))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="올리기 전 확인")
    ap.add_argument("--project", default=os.getcwd())
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("list")
    d = sub.add_parser("decide")
    d.add_argument("key")
    d.add_argument("choice", choices=("keep", "drop"))
    args = ap.parse_args()
    con = sqlite3.connect(os.path.join(args.project, ".hermes", "state.db"), timeout=5.0)
    rows = pending_rows(con)
    if args.cmd == "decide":
        row = _find(rows, args.key)
        if row is None:
            print(f"대기 문장에 없음: {args.key}", file=sys.stderr)
            return 1
        _apply(con, row, args.choice)
        print(f"{'둠' if args.choice == 'keep' else '지움'}: {row[3]}")
        return 0
    if args.cmd is None and sys.stdin.isatty():
        return _interactive(con)
    _show(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
