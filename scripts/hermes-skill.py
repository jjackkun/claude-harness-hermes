#!/usr/bin/env python3
"""진행적 공개의 본문 읽기 진입점 — `read <이름>` · `layers` · `where <이름>`.

주입은 스킬을 한 줄(헤드라인) 또는 스니펫으로만 보여 준다(RV-12). 에이전트가 그 스킬을 실제로
쓰기로 하면 이 CLI 로 **그 턴에** 본문을 끌어온다(설계 S-05, 진행적 공개). `read` 는 `skill_injection`
에 `source='read'` 를 남겨, 어느 스킬이 스니펫을 넘어 본문까지 불렸는지 효용 측정에 쓴다.
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 5

공개 함수 4개: find_skill · read_body · record_read · main
"""

import argparse
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skill_layers import all_layer_dirs, layer_of_path  # noqa: E402
from hermes_skills import iter_skill_files  # noqa: E402


def _name_of(skill_md: str) -> str:
    if skill_md.endswith("SKILL.md"):
        return os.path.basename(os.path.dirname(skill_md))
    return os.path.basename(skill_md)[:-3] if skill_md.endswith(".md") else os.path.basename(skill_md)


def find_skill(db_path: str, project: str, name: str) -> str:
    """이름으로 스킬 파일 경로를 찾는다. skill_index 우선, 없으면 네 층 폴더 스캔. 못 찾으면 ''."""
    if os.path.isfile(db_path):
        try:
            con = sqlite3.connect(db_path)
            rows = [r[0] for r in con.execute("SELECT skill_path FROM skill_index")]
            con.close()
            for path in rows:
                if _name_of(path) == name and os.path.isfile(path):
                    return path
        except sqlite3.Error:
            pass
    for _layer, skills_dir, _u, _a in all_layer_dirs(project):
        if not os.path.isdir(skills_dir):
            continue
        for nm, skill_md in iter_skill_files(skills_dir):
            if nm == name:
                return skill_md
    return ""


def read_body(path: str) -> str:
    """스킬 파일 본문 전체."""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def record_read(db_path: str, session_id: str, path: str) -> None:
    """`read` 를 skill_injection 에 source='read' 로 남긴다(효용 측정). 실패해도 본문 출력은 막지 않는다."""
    if not (os.path.isfile(db_path) and session_id):
        return
    try:
        con = sqlite3.connect(db_path)
        cols = [r[1] for r in con.execute("PRAGMA table_info(skill_injection)")]
        if "source" not in cols:
            con.execute("ALTER TABLE skill_injection ADD COLUMN source TEXT DEFAULT 'prompt'")
        con.execute("INSERT INTO skill_injection (session_id, skill_path, source) VALUES (?,?,?)",
                    (session_id, path, "read"))
        con.commit()
        con.close()
    except sqlite3.Error as exc:
        print(f"[hermes-skill] 읽기 기록 실패(계속): {exc}", file=sys.stderr)


def _cmd_read(args) -> int:
    path = find_skill(args.db, args.project, args.name)
    if not path:
        print(f"[hermes-skill] 스킬 없음: {args.name}", file=sys.stderr)
        return 1
    sys.stdout.write(read_body(path))
    record_read(args.db, args.session_id, path)
    return 0


def _cmd_where(args) -> int:
    path = find_skill(args.db, args.project, args.name)
    if not path:
        print(f"[hermes-skill] 스킬 없음: {args.name}", file=sys.stderr)
        return 1
    layer, unit_id, agent_id = layer_of_path(args.project, path)
    print(f"{args.name}\t{layer}\tunit={unit_id or '-'}\tagent={agent_id or '-'}\t{path}")
    return 0


def _cmd_layers(args) -> int:
    for layer, skills_dir, unit_id, agent_id in all_layer_dirs(args.project):
        n = sum(1 for _ in iter_skill_files(skills_dir)) if os.path.isdir(skills_dir) else 0
        owner = unit_id or agent_id or "-"
        print(f"{layer}\t{owner}\t{n}\t{skills_dir}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 스킬 본문·층 조회")
    ap.add_argument("--db", default=os.path.join(os.getcwd(), ".hermes", "state.db"))
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--session-id", default=os.environ.get("HERMES_SESSION_ID", ""))
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("read"); r.add_argument("name")
    w = sub.add_parser("where"); w.add_argument("name")
    sub.add_parser("layers")
    args = ap.parse_args()
    return {"read": _cmd_read, "where": _cmd_where, "layers": _cmd_layers}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
