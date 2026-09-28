#!/usr/bin/env python3
"""한 에이전트가 나와 나눈 대화 요약(session_summary.agent_id = 그 에이전트)을 출근 본문 구획으로 만드는 것만 담당한다(C-29).

최근 순으로, 바이트 상한 안에 드는 만큼 — 상한은 SOUL.md·MEMORY.md 와 같은 4,096 B(R-out 실측값, 새 숫자를 만들지 않는다).
개수로 자르지 않는다(회상은 LIMIT 1 이라 맞출 개수가 없다 — 계획 리뷰). 다른 에이전트·공통 요약은 넣지 않는다.
DB·칸이 없으면 빈 문자열(오류 아님) — 출근이 이 때문에 서면 안 된다.
계획: docs/exec-plans/completed/2026-09-28-agent-conversation-memory.md 목표 4

공개: SECTION_HEADER · render_agent_summaries
"""

import json
import os
import sqlite3

SECTION_HEADER = "--- 나와 나눈 최근 대화 ---"
_CAP = 4096
_LABELS = (("decisions", "결정"), ("facts", "사실"), ("open", "남은 일"), ("next", "다음"))


def _rows(project: str, agent_id: str) -> list:
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute("SELECT session_id, slots_json, updated_at FROM session_summary "
                           "WHERE agent_id = ? ORDER BY updated_at DESC", (agent_id,)).fetchall()
        con.close()
    except sqlite3.Error:
        return []                          # 칸·표 없음 — 아직 C-29 이전 DB
    return rows


def _block(session_id: str, raw: str, updated_at: str) -> str:
    try:
        slots = json.loads(raw) if raw else {}
    except ValueError:
        slots = {}
    where = "@ 호출" if str(session_id).startswith("sub:") else "방"
    lines = [f"■ {str(updated_at or '')[:10]} · {where}"]
    for key, label in _LABELS:
        items = [str(x) for x in (slots.get(key) or []) if str(x).strip()]
        if items:
            lines.append(f"  {label}: " + " / ".join(items))
    return "\n".join(lines) if len(lines) > 1 else ""


def _fit(text: str, room: int) -> str:
    data = text.encode("utf-8")[:room]
    return data.decode("utf-8", errors="ignore").rstrip() + " …"


def render_agent_summaries(project: str, agent_id: str, cap: int = _CAP) -> str:
    """구획 문자열(앞에 빈 줄). 요약이 없으면 빈 문자열."""
    head = f"\n{SECTION_HEADER}\n(방·@ 호출에서 이 에이전트와 나눈 대화의 요약, 최근 순 — 다른 사람과의 대화는 들어 있지 않다)"
    used = len(head.encode("utf-8"))
    blocks, skipped = [], 0
    for session_id, raw, updated_at in _rows(project, agent_id):
        block = _block(session_id, raw, updated_at)
        if not block:
            continue
        size = len(block.encode("utf-8")) + 1
        if used + size > cap:
            if not blocks:                     # 가장 최근 한 건도 안 들어가면 잘라서라도 넣는다
                blocks.append(_fit(block, cap - used - 8))
                used = cap
            else:
                skipped += 1
            continue
        blocks.append(block)
        used += size
    if not blocks:
        return ""
    tail = [f"(더 오래된 대화 {skipped}건은 상한 {cap} B 로 생략)"] if skipped else []
    return "\n".join([head, *blocks, *tail]) + "\n"
