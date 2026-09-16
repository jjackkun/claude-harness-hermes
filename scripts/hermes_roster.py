#!/usr/bin/env python3
"""명부 `.hermes/agents.json` 의 스키마 검증·조회·상태 전이 규칙만 담당한다.

명부가 있어야 이름 오타와 남의 id 사칭이 막힌다(A-03, 리뷰 R-5).
  agent_id   UUIDv7, 불변, 재사용 없음
  name       소우주 안 유일. **은퇴한 이름도 재사용 금지**(복직 자리를 지킨다, RV-17)
  status     probation → active → retired → (rehire) active
  org        {discipline, rank, unit} — 값은 organization.yaml 에 있는 것만
  template   <직무>@factory (선택)
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 1·2·15

공개 함수 6개: RosterError · load_roster · save_roster · find_agent · add_agent · transition
"""

import json
import os
import uuid
from datetime import datetime, timezone

from hermes_org import HUMAN_RANK
from hermes_uuid7 import uuid7_str

STATUSES = ("probation", "active", "retired")
_TRANSITIONS = {              # 명령 → (허용 출발 상태, 도착 상태)
    "promote": (("probation",), "active"),
    "retire": (("probation", "active"), "retired"),
    "rehire": (("retired",), "active"),
}
_ROSTER = ".hermes/agents.json"
_FIELDS = ("agent_id", "name", "status", "org", "template", "created_at", "created_by", "approved_by")


class RosterError(ValueError):
    """명부 규칙 위반 — 무엇이 왜 안 되는지 함께 알린다."""


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_roster(project: str) -> dict:
    """명부를 읽고 검증한다. 없으면 빈 명부."""
    path = os.path.join(project, _ROSTER)
    if not os.path.isfile(path):
        return {"agents": []}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    agents = data.get("agents") if isinstance(data, dict) else None
    if not isinstance(agents, list):
        raise RosterError(f"{_ROSTER}: agents 목록이 없다")
    seen = set()
    for agent in agents:
        _validate_agent(agent)
        if agent["name"] in seen:
            raise RosterError(f"이름이 겹친다: {agent['name']}")
        seen.add(agent["name"])
    return {"agents": agents}


def _validate_agent(agent: dict) -> None:
    unknown = sorted(set(agent) - set(_FIELDS))
    if unknown:
        raise RosterError(f"모르는 칸: {', '.join(unknown)}")
    try:
        if uuid.UUID(agent.get("agent_id", "")).version != 7:
            raise ValueError
    except ValueError as exc:
        raise RosterError(f"agent_id 는 UUIDv7 이어야 한다: {agent.get('agent_id')}") from exc
    if not agent.get("name") or not isinstance(agent["name"], str):
        raise RosterError("name 이 비었다")
    if agent.get("status") not in STATUSES:
        raise RosterError(f"모르는 status: {agent.get('status')} (허용: {', '.join(STATUSES)})")


def save_roster(project: str, roster: dict) -> str:
    path = os.path.join(project, _ROSTER)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(roster, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    return path


def find_agent(roster: dict, name_or_id: str) -> dict:
    """이름 또는 id 로 찾는다. 없으면 None."""
    for agent in roster["agents"]:
        if agent["name"] == name_or_id or agent["agent_id"] == name_or_id:
            return agent
    return None


def _check_org(org: dict, organization: dict) -> dict:
    """org 값이 organization.yaml 에 있는지. rank 의 human 은 에이전트에게 줄 수 없다."""
    org = {k: v for k, v in (org or {}).items() if v}
    unknown = sorted(set(org) - {"discipline", "rank", "unit"})
    if unknown:
        raise RosterError(f"org 에 모르는 축: {', '.join(unknown)}")
    if org.get("rank") == HUMAN_RANK:
        raise RosterError(f"rank '{HUMAN_RANK}' 은 사람만 — 에이전트에게 줄 수 없다")
    for axis in ("discipline", "rank"):
        if org.get(axis) and org[axis] not in organization.get(axis, []):
            raise RosterError(f"{axis} '{org[axis]}' 은 organization.yaml 에 없다")
    if org.get("unit") and org["unit"] not in organization.get("unit", {}):
        raise RosterError(f"unit '{org['unit']}' 은 organization.yaml 에 없다")
    return org


def add_agent(roster: dict, name: str, org: dict, organization: dict,
              created_by: str, template: str = None, status: str = "probation") -> dict:
    """입사. 이름은 은퇴자 포함 전체에서 유일해야 한다. 사람만 부른다(created_by 는 human:)."""
    if not created_by.startswith(("human:", "system:")):
        raise RosterError("입사는 사람(human:) 또는 설치기(system:)만 시킬 수 있다")
    if find_agent(roster, name):
        raise RosterError(f"이름 '{name}' 은 이미 명부에 있다(은퇴자 포함 — 재사용 금지)")
    if status not in STATUSES:
        raise RosterError(f"모르는 status: {status}")
    agent = {
        "agent_id": uuid7_str(), "name": name, "status": status,
        "org": _check_org(org, organization),
        "template": template, "created_at": _now(),
        "created_by": created_by, "approved_by": created_by,
    }
    roster["agents"].append(agent)
    return agent


def transition(roster: dict, name: str, command: str, by: str) -> dict:
    """promote · retire · rehire. 허용된 출발 상태에서만 옮긴다."""
    if command not in _TRANSITIONS:
        raise RosterError(f"모르는 전이: {command}")
    if not by.startswith("human:"):
        raise RosterError("상태 전이는 사람(human:)만 한다")
    agent = find_agent(roster, name)
    if agent is None:
        raise RosterError(f"명부에 없다: {name}")
    allowed, target = _TRANSITIONS[command]
    if agent["status"] not in allowed:
        raise RosterError(f"{command} 는 {'/'.join(allowed)} 상태에서만 — 지금 {agent['status']}")
    agent["status"] = target
    agent["approved_by"] = by
    return agent
