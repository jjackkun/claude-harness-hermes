#!/usr/bin/env python3
"""사람이 고를 수 있는 명부 에이전트를 찾는 것만 담당한다 — hermes-chat 번호 목록과 `@hag` 입력 목록이 같이 쓴다.

고를 수 있음 = slug 가 있고(부를 이름이 있다) 은퇴하지 않았다. 명부 순서 그대로.
계획: docs/exec-plans/completed/2026-09-28-hermes-chat.md 목표 6 · 7

공개: find_project · pickable · org_label · match · room_name
"""

import json
import os
import re


def find_project(start: str) -> str:
    """start 부터 위로 올라가 .hermes/agents.json 이 있는 폴더. 없으면 빈 문자열."""
    cur = os.path.abspath(start or ".")
    while True:
        if os.path.isfile(os.path.join(cur, ".hermes", "agents.json")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return ""
        cur = parent


def pickable(project: str) -> list:
    """slug 가 있고 은퇴하지 않은 명부 에이전트. 명부를 못 읽으면 빈 목록."""
    try:
        with open(os.path.join(project, ".hermes", "agents.json"), encoding="utf-8") as fh:
            roster = json.load(fh)
    except (OSError, ValueError):
        return []
    return [a for a in roster.get("agents") or []
            if isinstance(a, dict) and a.get("slug") and a.get("status") != "retired"]


def org_label(agent: dict) -> str:
    org = agent.get("org") or {}
    return "/".join(org.get(k) or "-" for k in ("discipline", "rank", "unit"))


def match(people: list, query: str) -> list:
    """이름(공백 무시) 일부 또는 slug 앞부분이 맞는 사람."""
    q = query.replace(" ", "").lower()
    return [a for a in people
            if q in a["name"].replace(" ", "").lower() or a["slug"].startswith(q)]


def room_name(agent: dict) -> str:
    """방 이름 — 사람이 `claude --resume` 뒤에 따옴표 없이 칠 이름이라 글자·숫자만 + "방"."""
    return re.sub(r"[^\w]", "", agent["name"]) + "방"
