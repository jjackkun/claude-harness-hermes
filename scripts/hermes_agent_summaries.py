#!/usr/bin/env python3
"""한 에이전트가 나와 나눈 대화 요약(session_summary.agent_id = 그 에이전트)을 출근 본문 구획으로 만드는 것만 담당한다(C-29).

최근 순으로, 바이트 상한 안에 드는 만큼 — 상한은 SOUL.md·MEMORY.md 와 같은 4,096 B(R-out 실측값, 새 숫자를 만들지 않는다).
개수로 자르지 않는다(회상은 LIMIT 1 이라 맞출 개수가 없다 — 계획 리뷰). 다른 에이전트·공통 요약은 넣지 않는다.
**부른 사람(git user.name)과 나눈 대화만** 넣는다 — 팀원이 같은 에이전트와 나눈 대화는 섞지 않는다(계획 carry-agent-knowledge 목표 1).
사람 칸이 비어 있는 요약(칸이 생기기 전, 이 컴퓨터에서 쌓인 것)은 넣는다.
DB·칸이 없으면 빈 문자열(오류 아님) — 출근이 이 때문에 서면 안 된다.
계획: docs/exec-plans/completed/2026-09-28-agent-conversation-memory.md 목표 4

공개: SECTION_HEADER · render_agent_summaries · agent_summary_rows · summary_block
"""

import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_person import person  # noqa: E402  (부른 사람 이름표)

SECTION_HEADER = "--- 나와 나눈 최근 대화 ---"
_CAP = 4096
_LABELS = (("decisions", "결정"), ("facts", "사실"), ("open", "남은 일"), ("next", "다음"))


def agent_summary_rows(project: str, agent_id: str, who: str) -> list:
    """(session_id, slots_json, updated_at) 최근 순 — 이 에이전트가 `who` 와 나눈 대화. 주입과 검색이 같이 쓴다.

    저장소 파일이 없으면 빈 목록. **읽기 실패(잠김 등)는 sqlite3.Error 로 올린다** — 주입(`_rows`)은 세션이 서야 하므로
    삼키지만, 검색(recall)은 "읽지 못함" 과 "없음" 을 구분해야 거짓 "찾지 못했습니다" 가 안 나온다."""
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return []
    queries = (("WHERE agent_id = ? AND (person = ? OR person IS NULL)", (agent_id, who)),
               ("WHERE agent_id = ?", (agent_id,)))       # person 칸 이전 DB(읽기 전용이라 칸을 못 더함) — 전부 이 컴퓨터 것
    for where, params in queries:
        try:
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            try:
                return con.execute("SELECT session_id, slots_json, updated_at FROM session_summary "
                                   f"{where} ORDER BY updated_at DESC", params).fetchall()
            finally:
                con.close()
        except sqlite3.OperationalError as exc:
            if "no such table" in str(exc):
                return []                              # 표 없음 — 아직 요약이 없는 DB
            if "no such column" not in str(exc):
                raise                                  # 잠김 등 — 진짜 읽기 실패
    return []                                          # 칸 없음 — 아직 C-29 이전 DB


def _rows(project: str, agent_id: str, who: str) -> list:
    """주입용 — 읽기 실패도 빈 목록(출근이 이 때문에 서면 안 된다)."""
    try:
        return agent_summary_rows(project, agent_id, who)
    except sqlite3.Error:
        return []


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


summary_block = _block          # 검색(recall)이 같은 글자 모양을 쓴다


def _fit(text: str, room: int) -> str:
    data = text.encode("utf-8")[:room]
    return data.decode("utf-8", errors="ignore").rstrip() + " …"


def render_agent_summaries(project: str, agent_id: str, cap: int = _CAP, who: str = None) -> str:
    """구획 문자열(앞에 빈 줄). 요약이 없으면 빈 문자열. who 가 없으면 이 컴퓨터의 사람 이름표."""
    head = f"\n{SECTION_HEADER}\n(방·@ 호출에서 이 에이전트와 나눈 대화의 요약, 최근 순 — 다른 사람과의 대화는 들어 있지 않다)"
    used = len(head.encode("utf-8"))
    blocks, skipped = [], 0
    for session_id, raw, updated_at in _rows(project, agent_id, who or person(project)):
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
