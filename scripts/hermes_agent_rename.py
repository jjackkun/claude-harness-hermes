#!/usr/bin/env python3
"""명부 에이전트의 이름을 바꾸는 것만 담당한다 — id 는 그대로, 이름·SOUL 머리·@ 파일만 바뀐다.

사람이 입사 뒤에 이름을 지을 수 있어야 한다(2026-09-29 사용자: "입사자의 이름을 지을 수 있어야 해").
이름은 명부에서 유일해야 한다(은퇴자 포함 — 입사와 같은 규칙). 사람(human:)만 부른다.
SOUL.md 는 머리의 `name:` 줄과 첫 `# <이름>` 제목만 바꾼다 — 본문은 사람 승인 영역이라 건드리지 않는다.
이름 바꿈은 이력에 decision 으로 남는다(누가 언제 무엇에서 무엇으로).

공개: rename_agent
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_mention_cmds import sync_and_report  # noqa: E402
from hermes_roster import RosterError, find_agent, load_roster, save_roster  # noqa: E402


def _soul_retitle(project: str, agent_id: str, old: str, new: str) -> None:
    path = os.path.join(project, ".hermes", "agents", agent_id, "SOUL.md")
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    text = re.sub(r"^name: .*$", f"name: {new}", text, count=1, flags=re.M)
    text = re.sub(r"^# " + re.escape(old) + r"\s*$", f"# {new}", text, count=1, flags=re.M)
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(path + ".tmp", path)


def _record(project: str, human: str, agent_id: str, old: str, new: str) -> None:
    try:
        from hermes_journal import emit
        emit(os.path.join(project, ".hermes", "state.db"), project,
             {"kind": "decision", "task_id": agent_id, "actor": human, "decision": f"rename {old} → {new}"})
    except Exception as exc:  # noqa: BLE001 — 이력은 부수 기록, 이름 바꿈을 되돌리지 않는다
        print(f"[hermes-agent WARN] 이름 바꿈을 이력에 못 남김: {exc}", file=sys.stderr)


def rename_agent(project: str, human: str, name: str, new_name: str) -> int:
    if not human.startswith("human:"):
        raise RosterError("이름은 사람(human:)만 바꾼다")
    new_name = str(new_name or "").strip()
    if not new_name:
        raise RosterError("새 이름이 비어 있다")
    roster = load_roster(project)
    agent = find_agent(roster, name)
    if agent is None:
        raise RosterError(f"명부에 없다: {name}")
    if any(a is not agent and a.get("name") == new_name for a in roster.get("agents") or []):
        raise RosterError(f"이름 '{new_name}' 은 이미 명부에 있다(은퇴자 포함)")
    old = agent["name"]
    agent["name"] = new_name
    save_roster(project, roster)
    sync_and_report(project, roster)
    _soul_retitle(project, agent["agent_id"], old, new_name)
    _record(project, human, agent["agent_id"], old, new_name)
    print(f"rename: {old} → {new_name} ({agent['agent_id']})")
    return 0
