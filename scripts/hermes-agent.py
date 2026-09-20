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
from hermes_memory_view import write_memory_md  # noqa: E402
from hermes_review_chain import TeachingError, record_teaching  # noqa: E402
from hermes_soul_draft import draft_soul, is_untouched_draft  # noqa: E402
from hermes_owner_memory import no_owner_since, record_no_owner  # noqa: E402
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
        soul = draft_soul(project, agent, fh.read())     # 기계 초안(조직 값) — 사람은 읽고 고쳐 승인한다(D-01)
    soul_path = os.path.join(folder, "SOUL.md")
    if not os.path.exists(soul_path):          # 사람이 고친 SOUL 을 덮지 않는다
        with open(soul_path, "w", encoding="utf-8") as fh:
            fh.write(soul)
    memory = os.path.join(folder, "MEMORY.md")
    if not os.path.exists(memory):
        with open(memory, "w", encoding="utf-8") as fh:
            fh.write(f"# {agent['name']} — 기억(파생)\n\n(기억 이벤트에서 기계가 계산한다. 손으로 고치지 않는다.)\n")
    return folder


def _record_created(project: str, agent: dict) -> None:
    """입사를 이력에 남긴다(agent.created, creation-and-organization.md §2). 이력이 꺼져 있거나
    DB 가 없으면 한 줄 알리고 넘어간다 — 명부·폴더는 이미 만들어졌고, 이력 실패로 입사를 되돌리지 않는다."""
    db = os.path.join(project, ".hermes", "state.db")
    try:
        from hermes_journal import emit
        org = agent.get("org") or {}
        emit(db, project, {
            "kind": "agent.created", "task_id": agent["agent_id"],
            "actor": agent.get("created_by") or _human(project),
            "intent": "hire %s %s/%s/%s" % (agent["name"], org.get("discipline", "-"),
                                           org.get("rank", "-"), org.get("unit", "-")),
        })
    except Exception as exc:  # noqa: BLE001 — 이력은 부수 기록, 입사 자체를 막지 않는다
        print(f"[hermes-agent WARN] agent.created 를 이력에 못 남김: {exc}", file=sys.stderr)


def cmd_hire(args) -> int:
    project = args.project
    ensure_unit_ids(project)
    org = load_org(project)
    roster = load_roster(project)
    agent = add_agent(roster, args.name, _parse_org(args.org), org, _human(project),
                      template=(f"{args.template}@factory" if args.template else None))
    save_roster(project, roster)
    folder = _write_identity(project, agent)
    _record_created(project, agent)
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
        since = no_owner_since(args.project, want)
        if since:   # 사람이 "이 영역은 담당을 두지 않는다" 고 정했다 — 다시 묻지 않는다(§5)
            print(f"no-owner: 이 영역은 담당을 두지 않기로 함({since[:10]}) — 바꾸려면 hire 로 입사시키십시오")
            return 4
        print("ask: 맞는 담당이 없습니다 — 사람에게 문의하십시오 (hermes-agent.py hire …)")
        return 3
    for a in result["agents"]:
        print(f"{a['name']} ({a['agent_id']}) org={a.get('org')}")
    return 0


def cmd_no_owner(args) -> int:
    """사람이 정한다: 이 영역(축 값)은 담당을 두지 않는다. 이후 match 는 ask 대신 이 기억을 보인다."""
    want = {"discipline": args.discipline, "rank": args.rank, "unit": args.unit}
    if not any(want.values()):
        print("no-owner 에는 축 값이 하나 이상 필요하다 (--discipline/--rank/--unit)", file=sys.stderr)
        return 2
    eid = record_no_owner(args.project, want, _human(args.project))
    print(f"no-owner 기록: {' '.join(f'{k}:{v}' for k, v in want.items() if v)} ({eid})")
    return 0


def cmd_refresh_memory(args) -> int:
    """기억 이벤트에서 MEMORY.md 를 다시 만든다(계획 agent-memory-roundtrip 목표 1).
    DB 나 memory_events 표가 없으면 아무것도 하지 않는다 — 훅이 부르므로 실패로 세션을 세우지 않는다."""
    import sqlite3
    project = args.project
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        print("[hermes-agent] refresh-memory: state.db 없음 — 건너뜀")
        return 0
    con = sqlite3.connect(db)
    try:
        has = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='memory_events'").fetchone()
        if not has:
            print("[hermes-agent] refresh-memory: memory_events 없음 — 건너뜀")
            return 0
        try:
            roster = load_roster(project)
        except RosterError:
            roster = {"agents": []}
        if args.name:
            agent = find_agent(roster, args.name) or {"agent_id": args.name, "name": None, "status": "active"}
            targets = [agent]
        else:
            targets = [a for a in roster["agents"] if a.get("status") != "retired"
                       and os.path.isdir(_agent_dir(project, a["agent_id"]))]
        for agent in targets:
            path = write_memory_md(con, project, agent["agent_id"], agent.get("name"))
            print(f"기억 보기 갱신: {os.path.relpath(path, project)}")
    finally:
        con.close()
    return 0


def cmd_soul_draft(args) -> int:
    """기존 에이전트의 SOUL 이 아직 초안(표시 줄·틀 괄호)이면 조직 값으로 다시 채운다. 사람이 고친 SOUL 은 건드리지 않는다."""
    project = args.project
    agent = find_agent(load_roster(project), args.name)
    if not agent:
        raise RosterError(f"명부에 없는 에이전트: {args.name}")
    soul_path = os.path.join(_agent_dir(project, agent["agent_id"]), "SOUL.md")
    if not is_untouched_draft(soul_path):
        print(f"그대로: {agent['name']} 의 SOUL 은 사람이 승인한 것 — 다시 채우지 않는다")
        return 0
    template = _SOUL_TEMPLATE if os.path.isfile(_SOUL_TEMPLATE) else _SOUL_FACTORY
    with open(template, encoding="utf-8") as fh:
        soul = draft_soul(project, agent, fh.read())
    os.makedirs(os.path.dirname(soul_path), exist_ok=True)
    with open(soul_path, "w", encoding="utf-8") as fh:
        fh.write(soul)
    print(f"초안 갱신: {os.path.relpath(soul_path, project)} — 읽고 고친 뒤 초안 표시 줄을 지우면 승인")
    return 0


def cmd_teach(args) -> int:
    """사람이 특정 에이전트에게 직접 가르친다(C-22): memory.added(source_event=teach:human:<이름>). about 필수."""
    project = args.project
    agent = find_agent(load_roster(project), args.name)
    if not agent:
        raise RosterError(f"명부에 없는 에이전트: {args.name}")
    mid = record_teaching(os.path.join(project, ".hermes", "state.db"), project, agent["agent_id"],
                          args.about, args.body, f"teach:{_human(project)}")
    print(f"가르침 기록: {agent['name']} about={args.about} memory={mid[:8]} — 되돌리기는 memory.retracted 로")
    return 0


def cmd_note(args) -> int:
    """소환된 에이전트가 스스로 배운 것 한 줄(cumora 식, 계획 agent-teaching 목표 9). HERMES_AGENT_ID 세션에서만."""
    agent_id = os.environ.get("HERMES_AGENT_ID", "")
    if not agent_id:
        raise RosterError("note 는 소환된 에이전트 세션(HERMES_AGENT_ID)에서만 — 사람은 teach 를 쓴다")
    nonce = os.environ.get("HERMES_SUMMON_NONCE", "session")
    mid = record_teaching(os.path.join(args.project, ".hermes", "state.db"), args.project, agent_id,
                          args.about, args.body, f"note:agent:{agent_id}:{nonce}")
    print(f"기억 기록: about={args.about} memory={mid[:8]}")
    return 0


def cmd_pin(args) -> int:
    """기억 하나를 핀 — 세션 시작 주입에 항상 들어간다(계획 agent-teaching 목표 10). 다시 부르면 푼다."""
    import sqlite3
    from datetime import datetime, timezone
    from hermes_memory_events import ensure_memory_schema
    project = args.project
    agent = find_agent(load_roster(project), args.name)
    if not agent:
        raise RosterError(f"명부에 없는 에이전트: {args.name}")
    con = sqlite3.connect(os.path.join(project, ".hermes", "state.db"))
    try:
        ensure_memory_schema(con)
        aid = agent["agent_id"]
        if not con.execute("SELECT 1 FROM memory_events WHERE agent_id=? AND memory_id=?", (aid, args.memory_id)).fetchone():
            raise RosterError(f"{agent['name']} 의 기억이 아니다: {args.memory_id}")
        if con.execute("SELECT 1 FROM memory_pins WHERE agent_id=? AND memory_id=?", (aid, args.memory_id)).fetchone():
            con.execute("DELETE FROM memory_pins WHERE agent_id=? AND memory_id=?", (aid, args.memory_id)); state = "핀 해제"
        else:
            con.execute("INSERT INTO memory_pins (agent_id, memory_id, pinned_at) VALUES (?,?,?)",
                        (aid, args.memory_id, datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))); state = "핀"
        con.commit()
    finally:
        con.close()
    print(f"{state}: {agent['name']} {args.memory_id[:8]}")
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
    n = sub.add_parser("no-owner", help="이 영역은 담당을 두지 않는다 — 기억해 두고 다시 묻지 않는다")
    n.add_argument("--discipline"); n.add_argument("--rank"); n.add_argument("--unit")
    r = sub.add_parser("refresh-memory", help="기억 이벤트에서 MEMORY.md 를 다시 만든다(이름/id 생략 시 은퇴자 제외 전원)")
    r.add_argument("name", nargs="?")
    t = sub.add_parser("teach", help="사람이 에이전트에게 한 줄 가르친다(C-22) — about 은 <domain>/<slug>")
    t.add_argument("name"); t.add_argument("body"); t.add_argument("--about", required=True)
    nt = sub.add_parser("note", help="소환된 에이전트가 배운 것 한 줄을 남긴다(HERMES_AGENT_ID 세션)")
    nt.add_argument("body"); nt.add_argument("--about", required=True)
    pn = sub.add_parser("pin", help="기억 하나를 핀/해제 — 주입에 항상 포함")
    pn.add_argument("name"); pn.add_argument("memory_id")
    sd = sub.add_parser("soul-draft", help="SOUL 초안을 조직 값으로 (다시) 채운다 — 사람이 승인한 SOUL 은 건드리지 않음")
    sd.add_argument("name")
    args = ap.parse_args()
    try:
        if args.cmd == "hire":
            return cmd_hire(args)
        if args.cmd in ("promote", "retire", "rehire"):
            return cmd_transition(args)
        return {"list": cmd_list, "whoami": cmd_whoami, "match": cmd_match, "no-owner": cmd_no_owner,
                "refresh-memory": cmd_refresh_memory, "teach": cmd_teach, "note": cmd_note,
                "pin": cmd_pin, "soul-draft": cmd_soul_draft}[args.cmd](args)
    except (RosterError, OrgError, TeachingError) as exc:
        print(f"[hermes-agent] 거부: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
