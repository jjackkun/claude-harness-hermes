#!/usr/bin/env python3
"""에이전트 지식 파일(기억 · 대화 요약 · 작업 이력)의 세션 끝 내보내기와 세션 시작 들이기를 순서대로 부른다.

  export  — 아직 판정 안 한 문장(요약 항목 · 기억 · 이력 교훈·결정 · 스킬 본문)을 한 번에 판정한 뒤, 통과한 것만 파일로 쓴다
  import  — git 으로 받은 파일에서 DB 에 없는 것을 들이고, 기억이 들어온 에이전트의 MEMORY.md 를 다시 만든다

파일이 원본이다 — 컴퓨터를 옮기면 git pull 만으로 따라간다(운반이 꺼진 공개 저장소에서도).
계획: docs/exec-plans/active/2026-09-28-carry-agent-knowledge.md 목표 2 · 4 · 5 · 6
"""

import argparse
import glob
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_conversation_file as conversations  # noqa: E402
import hermes_journal_file as journal  # noqa: E402
import hermes_memory_file as memory  # noqa: E402
from hermes_privacy_judge import judge_and_mark  # noqa: E402
from hermes_privacy_pending import pending_rows  # noqa: E402

SKILL_GLOBS = (os.path.join(".hermes", "skills", "**", "*.md"),
               os.path.join(".hermes", "agents", "*", "skills", "**", "*.md"))


def skill_items(project: str) -> list:
    """커밋될 스킬 파일 본문 [(kind, ref, text)] — 스킬도 사람의 대화에서 굳은 것이라 같은 판정을 거친다."""
    items = []
    for pattern in SKILL_GLOBS:
        for path in sorted(glob.glob(os.path.join(project, pattern), recursive=True)):
            try:
                with open(path, encoding="utf-8") as fh:
                    items.append(("skill", os.path.relpath(path, project), fh.read()))
            except OSError:
                continue
    return items


def _connect(project: str):
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return None
    con = sqlite3.connect(db, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    return con


def cmd_export(project: str) -> int:
    con = _connect(project)
    if con is None:
        return 0
    items = (conversations.judge_items(con) + memory.judge_items(con)
             + journal.judge_items(con, project) + skill_items(project))
    judged = judge_and_mark(con, items)
    m, c, j = memory.export(con, project), conversations.export(con, project), journal.export(con, project)
    held = len(pending_rows(con))
    con.close()
    print(f"[hermes-knowledge] 판정 {judged} · 기억 +{m}줄 · 대화 요약 {c}파일 · 이력 +{j}줄 · 확인 대기 {held}")
    if held:
        print("[hermes-knowledge] 올리기 전 확인: python3 scripts/hermes-privacy-review.py")
    return 0


def cmd_import(project: str) -> int:
    con = _connect(project)
    if con is None:
        return 0
    touched = memory.import_(con, project)
    c, j = conversations.import_(con, project), journal.import_(con, project)
    if touched:
        from hermes_memory_view import write_memory_md
        from hermes_roster import load_roster
        names = {a.get("agent_id"): a.get("name") for a in load_roster(project).get("agents", [])}
        for aid in sorted(touched):
            write_memory_md(con, project, aid, names.get(aid))
    con.close()
    print(f"[hermes-knowledge] 들임 · 기억 {len(touched)}명 · 대화 요약 {c} · 이력 {j}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="에이전트 지식 파일 내보내기·들이기")
    ap.add_argument("cmd", choices=("export", "import"))
    ap.add_argument("--project", default=os.getcwd())
    args = ap.parse_args()
    return cmd_export(args.project) if args.cmd == "export" else cmd_import(args.project)


if __name__ == "__main__":
    sys.exit(main())
