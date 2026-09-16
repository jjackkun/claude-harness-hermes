#!/usr/bin/env python3
"""기억 이벤트와 충돌 표시에서 `MEMORY.md` 보기를 계산해 쓴다(파생, 사람이 고치지 않는다).

MEMORY.md 는 원본이 아니라 이벤트에서 만든 보기다. 어느 컴퓨터든 이벤트만 있으면 다시 만든다.
그래서 git 추적하지 않는다(identity.md 6절). 최신 자동 승리가 없으므로 충돌은 **둘 다 보여 준다**.
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 8·9

공개 함수 2개: render · write_memory_md
"""

import os

from hermes_memory_conflicts import (
    current_memories, find_conflicts, rule_conflicts, single_source)


def render(con, agent_id: str, agent_name: str = None, rule_keys=None) -> str:
    """MEMORY.md 본문을 만든다. 규칙 충돌·단일 사례·내용 충돌을 표시로 단다."""
    name = agent_name or agent_id
    memories = current_memories(con, agent_id)
    conflicts = find_conflicts(con, agent_id)
    rule_hits = {c["memory_id"]: c for c in rule_conflicts(con, rule_keys, agent_id)}
    singles = {c["about"] for c in single_source(con, agent_id)}
    conflict_ids = {mid for c in conflicts for mid in c["memory_ids"]}

    lines = [f"# {name} — 기억 (파생, 손으로 고치지 않는다)", ""]
    if rule_hits:
        lines += ["> ⚠️ **규칙 충돌**: 아래 기억은 규칙과 어긋납니다 — 규칙을 먼저 따르십시오.", ""]
    if not memories:
        lines += ["(아직 기억 없음)", ""]
    for e in memories:
        lines.append(_memory_line(e, rule_hits, conflict_ids, singles))
    if conflicts:
        lines += ["", "## 충돌 (둘 다 남긴다 — 최신이 자동으로 이기지 않는다)"]
        lines += [_conflict_line(c) for c in conflicts]
    return "\n".join(lines) + "\n"


def _memory_line(e: dict, rule_hits: dict, conflict_ids: set, singles: set) -> str:
    tags = []
    if e["memory_id"] in rule_hits:
        tags.append("규칙 충돌")
    if e["memory_id"] in conflict_ids:
        tags.append("충돌")
    if e["about"] in singles:
        tags.append("단일 사례")
    tag = f"  _[{' · '.join(tags)}]_" if tags else ""
    about = f"**{e['about']}**: " if e["about"] else ""
    return f"- {about}{e['body'] or '(본문 없음)'}{tag}"


def _conflict_line(c: dict) -> str:
    key = c.get("about") or c.get("revises") or c.get("content_hash", "")
    return f"- {c['type']}({c['reason']}) — {key}: {', '.join(m[:8] for m in c['memory_ids'])}"


def write_memory_md(con, project: str, agent_id: str, agent_name: str = None, rule_keys=None) -> str:
    """.hermes/agents/<id>/MEMORY.md 를 다시 쓴다(원자적). 경로를 돌려준다."""
    folder = os.path.join(project, ".hermes", "agents", agent_id)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "MEMORY.md")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(render(con, agent_id, agent_name, rule_keys))
    os.replace(tmp, path)
    return path
