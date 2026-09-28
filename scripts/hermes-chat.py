#!/usr/bin/env python3
"""명부에서 대화 상대를 골라 그 에이전트의 방을 연다 — `claude --agent <slug> --name <이름>방`.

왜(2026-09-28): `claude --agent` 는 에이전트 이름을 알아야만 열린다(이름 없이 → "argument missing", 실측).
사람은 명부 이름을 모른다 — 번호로 고르게 한다. 소환 러너가 아니다: 사람이 자기 터미널에서 대화형으로
여는 방이고, SOUL·기억은 SessionStart 훅이 agent_type 으로 넣는다(계획 2026-09-28-hermes-chat 목표 1 · 7, C-28).

쓰는 법: hermes-chat [이름 일부] [--project P] [--dry-run]
  - 이름 일부가 한 명에게만 맞으면 번호 없이 바로 연다.
  - --dry-run 은 실행할 명령만 찍는다(시험용).
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_roster_pick import find_project, match, org_label, pickable, room_name  # noqa: E402


def choose(people: list) -> dict:
    """번호 목록을 보이고 한 줄을 읽는다. 틀리면 None."""
    print("누구와 대화할까요?")
    for i, a in enumerate(people, 1):
        print(f"  {i}) {a['name']}   {org_label(a)}")
    print("번호: ", end="", flush=True)
    line = sys.stdin.readline().strip()
    if not line.isdigit() or not 1 <= int(line) <= len(people):
        print(f"\n번호가 아닙니다: {line or '(빈 입력)'} — 1~{len(people)} 중에서 고르십시오.", file=sys.stderr)
        return None
    return people[int(line) - 1]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="hermes-chat", description="명부 에이전트와 대화하는 방을 연다")
    ap.add_argument("query", nargs="?", default="", help="이름 일부 — 한 명에게만 맞으면 바로 연다")
    ap.add_argument("--project", default="", help="헤르메스 프로젝트 폴더(기본: 지금 폴더에서 위로 찾음)")
    ap.add_argument("--dry-run", action="store_true", help="실행하지 않고 명령만 찍는다")
    args = ap.parse_args(argv)

    project = find_project(args.project or os.getcwd())
    if not project:
        print("헤르메스 프로젝트가 아닙니다 — .hermes/agents.json 이 있는 폴더(또는 그 아래)에서 실행하십시오.", file=sys.stderr)
        return 1
    people = pickable(project)
    if not people:
        print("방을 열 명부 에이전트가 없습니다 — 먼저 입사시키십시오: python3 scripts/hermes-agent.py hire", file=sys.stderr)
        return 1
    hits = match(people, args.query) if args.query else []
    agent = hits[0] if len(hits) == 1 else choose(hits or people)
    if agent is None:
        return 1

    room = room_name(agent)
    cmd = ["claude", "--agent", agent["slug"], "--name", room]
    print(f"→ {agent['name']} 방을 엽니다 · 나중에 돌아오기: claude --resume {room}", file=sys.stderr)
    if args.dry_run:
        print(" ".join(cmd))    # 방 이름은 글자·숫자뿐이고 slug 는 [a-z0-9-] — 따옴표가 필요 없다
        return 0
    os.chdir(project)            # 프로젝트 훅·에이전트 파일이 실리려면 그 폴더에서 열어야 한다
    os.execvp(cmd[0], cmd)
    return 1                     # execvp 는 돌아오지 않는다


if __name__ == "__main__":
    sys.exit(main())
