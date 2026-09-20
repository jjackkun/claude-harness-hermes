#!/usr/bin/env python3
"""세션 시작 주입에 넣을 기억을 고른다 (계획 2026-09-18-agent-teaching 목표 10).

MEMORY.md 파일은 전체를 담지만 주입은 선별한다 — 파일이 커지면 4,096 B 캡에서 뒤가 조용히 잘리기 때문이다.
순서: 핀(사람이 `pin` 한 것, 전부) → 이번 과제(HERMES_TASK_HINT)의 낱말·about 과 겹치는 것 상위 N → 최근 M.
cumora(핀 > 관련 > 최근)와 ECC(상위 6) 의 값을 따랐다: N=6, M=4. 모델 호출 없음(R3) — 낱말 겹침으로만 잰다.
공개 함수 2개: select_memories · render_selection
"""
import re
import sqlite3

from hermes_memory_conflicts import current_memories

TOP_RELATED = 6
TOP_RECENT = 4
_WORD = re.compile(r"[A-Za-z0-9_./-]{2,}|[가-힣]{2,}")


def _tokens(text: str) -> set:
    return {t.lower() for t in _WORD.findall(text or "")}


def _pinned_ids(con, agent_id: str) -> set:
    try:
        return {r[0] for r in con.execute("SELECT memory_id FROM memory_pins WHERE agent_id=?", (agent_id,))}
    except sqlite3.OperationalError:
        return set()


def _score(mem: dict, hint_tokens: set) -> int:
    """과제 낱말과 겹치는 수. about 의 slug 낱말은 2배 — 주제 일치가 본문 우연 일치보다 값지다."""
    about_tokens = _tokens((mem.get("about") or "").replace("/", " "))
    body_tokens = _tokens(mem.get("body") or "")
    return 2 * len(about_tokens & hint_tokens) + len(body_tokens & hint_tokens)


def _related(memories: list, taken: set, hint: str, top: int) -> list:
    hint_tokens = _tokens(hint)
    if not hint_tokens:
        return []
    scored = sorted(((_score(m, hint_tokens), m) for m in memories if m["memory_id"] not in taken),
                    key=lambda x: (-x[0], x[1].get("ts") or ""))
    return [m for score, m in scored if score > 0][:top]


def _recent(memories: list, taken: set, top: int) -> list:
    return sorted((m for m in memories if m["memory_id"] not in taken),
                  key=lambda m: m.get("ts") or "", reverse=True)[:top]


def select_memories(con, agent_id: str, hint: str = "", top_related: int = TOP_RELATED,
                    top_recent: int = TOP_RECENT) -> dict:
    """{'pinned': [...], 'related': [...], 'recent': [...], 'total': n} — 각 목록은 기억 dict. 겹치지 않는다."""
    memories = current_memories(con, agent_id)
    pinned_ids = _pinned_ids(con, agent_id)
    pinned = [m for m in memories if m["memory_id"] in pinned_ids]
    taken = {m["memory_id"] for m in pinned}
    related = _related(memories, taken, hint, top_related)
    taken |= {m["memory_id"] for m in related}
    recent = _recent(memories, taken, top_recent)
    return {"pinned": pinned, "related": related, "recent": recent, "total": len(memories)}


def render_selection(sel: dict, agent_name: str) -> str:
    """주입용 본문. 전체 수와 고른 수를 머리에 적어 '더 있다' 를 보이게 한다."""
    shown = len(sel["pinned"]) + len(sel["related"]) + len(sel["recent"])
    lines = [f"# {agent_name} — 기억 (선별 {shown}/{sel['total']} · 전체는 MEMORY.md)"]
    for label, items in (("핀", sel["pinned"]), ("이번 과제 관련", sel["related"]), ("최근", sel["recent"])):
        if not items:
            continue
        lines.append(f"\n## {label}")
        for m in items:
            about = f"**{m['about']}**: " if m.get("about") else ""
            tag = "  _[전에 철회됨]_" if m.get("previously_retracted") else ""
            lines.append(f"- {about}{m.get('body') or '(본문 없음)'}{tag}")
    if shown == 0:
        lines.append("(아직 기억 없음)")
    return "\n".join(lines) + "\n"
