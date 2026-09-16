#!/usr/bin/env python3
"""에이전트 명부 CLI — 사람이 부르는 진입점. 입사·전환은 사람만 한다(C-03).

  hire <이름> --org <discipline,rank,unit> [--template <직무>]   입사 → probation
  promote <이름>     정식 전환 (probation → active)
  retire <이름>      은퇴(소프트) — 이름은 남고 재사용 금지
  rehire <이름>      복직 (retired → active)
  list               명부
  whoami             현재 세션의 행위자 (HERMES_AGENT_ID 없으면 main)
  match --discipline … --unit …   담당 매칭(C-11) — 없으면 ask

계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 2·4·13
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_org import OrgError, ensure_unit_ids, load_org, match_agents  # noqa: E402
from hermes_roster import (  # noqa: E402
    RosterError, add_agent, find_agent, load_roster, save_roster, transition)

_SOUL_TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates", "agent", "SOUL.md")
_SOUL_FACTORY = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                             "assets", "templates", "agent", "SOUL.md")


def _human(project: str) -> str:
    try:
        name = subprocess.run(["git", "-C", project, "config", "user.name"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return f"human:{name}" if name else "human:unknown"


def _parse_org(text: str) -> dict:
    """'프론트엔드,담당,users' → {discipline, rank, unit}. 빈 칸은 생략 가능('프론트엔드,,users')."""
    parts = [p.strip() for p in (text or "").split(",")]
    parts += [""] * (3 - len(parts))
    return {k: v for k, v in zip(("discipline", "rank", "unit"), parts[:3]) if v}


def _agent_dir(project: str, agent_id: str) -> str:
    return os.path.join(project, ".hermes", "agents", agent_id)


def _write_identity(project: str, agent: dict) -> str:
    """정체성 폴더 .hermes/agents/<id>/{SOUL.md, MEMORY.md, skills/}. SOUL 은 공장 틀에서."""
    folder = _agent_dir(project, agent["agent_id"])
    os.makedirs(os.path.join(folder, "skills"), exist_ok=True)
    template = _SOUL_TEMPLATE if os.path.isfile(_SOUL_TEMPLATE) else _SOUL_FACTORY
    with open(template, encoding="utf-8") as fh:
        soul = fh.read()
    fill = {
        "AGENT_ID": agent["agent_id"], "NAME": agent["name"], "STATUS": agent["status"],
        "ORG": json.dumps(agent.get("org") or {}, ensure_ascii=False),
        "TEMPLATE": agent.get("template") or "(없음)",
        "CREATED_AT": agent["created_at"], "CREATED_BY": agent["created_by"],
    }
    for key, value in fill.items():
        soul = soul.replace("{{" + key + "}}", value)
    soul_path = os.path.join(folder, "SOUL.md")
    if not os.path.exists(soul_path):          # 사람이 고친 SOUL 을 덮지 않는다
        with open(soul_path, "w", encoding="utf-8") as fh:
            fh.write(soul)
    memory = os.path.join(folder, "MEMORY.md")
    if not os.path.exists(memory):
        with open(memory, "w", encoding="utf-8") as fh:
            fh.write(f"# {agent['name']} — 기억(파생)\n\n(기억 이벤트에서 기계가 계산한다. 손으로 고치지 않는다.)\n")
    return folder


def cmd_hire(args) -> int:
    project = args.project
    ensure_unit_ids(project)
    org = load_org(project)
    roster = load_roster(project)
    agent = add_agent(roster, args.name, _parse_org(args.org), org, _human(project),
                      template=(f"{args.template}@factory" if args.template else None))
    save_roster(project, roster)
    folder = _write_identity(project, agent)
    print(f"입사: {agent['name']} ({agent['agent_id']}) status={agent['status']} org={agent['org']}")
    print(f"정체성: {os.path.relpath(folder, project)}/  — SOUL.md 를 채우십시오(사람 승인으로만 수정)")
    return 0


def cmd_transition(args) -> int:
    roster = load_roster(args.project)
    agent = transition(roster, args.name, args.cmd, _human(args.project))
    save_roster(args.project, roster)
    print(f"{args.cmd}: {agent['name']} → {agent['status']}")
    return 0


def cmd_list(args) -> int:
    roster = load_roster(args.project)
    for a in roster["agents"]:
        org = a.get("org") or {}
        print(f"{a['status']:<10} {a['name']:<16} {a['agent_id']}  "
              f"{org.get('discipline', '-')}/{org.get('rank', '-')}/{org.get('unit', '-')}"
              f"{'  ' + a['template'] if a.get('template') else ''}")
    if not roster["agents"]:
        print("(명부 비어 있음)")
    return 0


def cmd_whoami(args) -> int:
    roster = load_roster(args.project)
    wanted = os.environ.get("HERMES_AGENT_ID")
    agent = find_agent(roster, wanted) if wanted else find_agent(roster, "main")
    if agent is None:
        print("agent:main (명부에 없음 — 설치기가 main 을 만들어야 한다)")
        return 1
    print(f"agent:{agent['agent_id']} ({agent['name']}, {agent['status']})")
    return 0


def cmd_match(args) -> int:
    roster = load_roster(args.project)
    want = {"discipline": args.discipline, "rank": args.rank, "unit": args.unit}
    result = match_agents(roster["agents"], want)
    if result["ask"]:
        print("ask: 맞는 담당이 없습니다 — 사람에게 문의하십시오 (hermes-agent.py hire …)")
        return 3
    for a in result["agents"]:
        print(f"{a['name']} ({a['agent_id']}) org={a.get('org')}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 에이전트 명부")
    ap.add_argument("--project", default=os.getcwd())
    sub = ap.add_subparsers(dest="cmd", required=True)
    h = sub.add_parser("hire"); h.add_argument("name"); h.add_argument("--org", default="")
    h.add_argument("--template")
    for name in ("promote", "retire", "rehire"):
        sub.add_parser(name).add_argument("name")
    sub.add_parser("list"); sub.add_parser("whoami")
    m = sub.add_parser("match")
    m.add_argument("--discipline"); m.add_argument("--rank"); m.add_argument("--unit")
    args = ap.parse_args()
    try:
        if args.cmd == "hire":
            return cmd_hire(args)
        if args.cmd in ("promote", "retire", "rehire"):
            return cmd_transition(args)
        return {"list": cmd_list, "whoami": cmd_whoami, "match": cmd_match}[args.cmd](args)
    except (RosterError, OrgError) as exc:
        print(f"[hermes-agent] 거부: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
