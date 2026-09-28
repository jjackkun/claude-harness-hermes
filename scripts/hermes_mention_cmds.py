#!/usr/bin/env python3
"""hermes-agent.py 의 @ 멘션 명령 본체만 담당한다 — set-slug · sync-mention-files · 명부를 바꾼 뒤 파일 맞추기 보고.

CLI 파일(hermes-agent.py)이 400줄 경고선에 닿아 명령 본체를 여기로 뺐다. 파서·디스패치는 CLI 에 남는다.
계획: docs/exec-plans/active/2026-09-28-agent-mention-bridge.md 목표 1·2

공개: sync_and_report · set_slug · sync_only
"""

from hermes_agent_slug import assign_slug
from hermes_mention_file import sync_mention_files
from hermes_roster import RosterError, find_agent, load_roster, save_roster


def sync_and_report(project: str, roster: dict) -> None:
    """명부를 바꾼 명령 뒤에 부른다 — 파일을 맞추고 한 줄로 알린다."""
    r = sync_mention_files(project, roster)
    print(f"에이전트 파일: 바꿈 {len(r['written'])} · 지움 {len(r['removed'])}"
          + (f" · 사람 파일이라 건너뜀 {', '.join(r['skipped'])}" if r["skipped"] else ""))


def set_slug(project: str, human: str, name: str, slug: str) -> int:
    if not human.startswith("human:"):
        raise RosterError("slug 는 사람(human:)만 붙인다")
    roster = load_roster(project)
    agent = find_agent(roster, name)
    if agent is None:
        raise RosterError(f"명부에 없다: {name}")
    assign_slug(roster, agent, slug, project)
    save_roster(project, roster)
    print(f"set-slug: {agent['name']} → @agent-{agent['slug']}")
    sync_and_report(project, roster)
    return 0


def sync_only(project: str) -> int:
    sync_and_report(project, load_roster(project))
    return 0
