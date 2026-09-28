#!/usr/bin/env python3
"""명부 전원 표와 방 구성원을 사람이 읽는 글자(표 · 상태줄 한 줄)로 그리는 것만 담당한다. 계산은 hermes_room.py.

계획: docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 1·2

공개: render_roster · render_room · render_room_line · local_when
"""

import unicodedata
from datetime import datetime

_STATUS_ORDER = {"active": 0, "probation": 1, "retired": 2}
_STATUS_KO = {"active": "재직", "probation": "수습", "retired": "은퇴"}


def _width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def _pad(text: str, width: int) -> str:
    return text + " " * max(0, width - _width(text))


def local_when(ts: str) -> str:
    """ISO(UTC, 이력 저장 형식) → 이 컴퓨터 현지 시각 'YYYY-MM-DD HH:MM'. 없으면 '-', 못 읽으면 원문 앞 16자."""
    if not ts:
        return "-"
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return ts[:16].replace("T", " ")


def _table(rows: list, headers: list) -> list:
    widths = [max(_width(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]
    line = lambda r: "  ".join(_pad(str(v), w) for v, w in zip(r, widths)).rstrip()
    return [line(headers), "─" * _width(line(headers))] + [line(r) for r in rows]


def render_roster(roster: dict, seen: dict) -> str:
    agents = [a for a in roster.get("agents") or [] if a.get("name") != "main"]
    agents.sort(key=lambda a: (_STATUS_ORDER.get(a.get("status"), 9), a.get("name", "")))
    rows = []
    for a in agents:
        org = a.get("org") or {}
        rows.append([a["name"], f"@agent-{a['slug']}" if a.get("slug") else "-",
                     _STATUS_KO.get(a.get("status"), a.get("status") or "?"),
                     "/".join(org.get(k) or "-" for k in ("discipline", "rank", "unit")),
                     local_when(seen.get(a["agent_id"], ""))])
    if not rows:
        return "명부에 에이전트가 없습니다 (입사: hermes-agent.py hire)"
    body = _table(rows, ["이름", "호출", "상태", "분야/직급/조직", "최근 불린 때"])
    return "\n".join(body + [f"({len(rows)}명 · 은퇴자는 맨 아래 · 부르기: @<호출명 앞부분> 또는 한글 이름)"])


def _now_text(room: dict) -> str:
    return ", ".join(f"{n} 일하는 중" for n in room.get("working") or []) or "없음"


def render_room(room: dict, session_id: str) -> str:
    out = [f"방 주인: {room['owner']}"] if room.get("owner") else []
    out += [f"지금 일하는 중: {_now_text(room)}", "", f"이 방(세션 {session_id[:8]}…)에서 불린 에이전트 — 횟수는 끝난 호출 + 일하는 중"]
    if room["members"]:
        rows = [[m["name"], f"@agent-{m['slug']}" if m.get("slug") else "-", f"{m['count']}회", local_when(m["last"])]
                for m in room["members"]]
        out += _table(rows, ["명부 에이전트", "호출", "횟수", "마지막"])
    else:
        out.append("명부 에이전트: 없음")
    if room["tools"]:
        out.append("명부 밖 에이전트(끝난 호출): " + " · ".join(f"{k} {v}회" for k, v in sorted(room["tools"].items())))
    out.append(f"내부 보조 호출: {room['internal']}건 (Claude Code 가 안에서 띄운 것 — 사용자가 부르지 않았고 이름이 없다)")
    return "\n".join(out)


def render_room_line(room: dict) -> str:
    """상태줄 한 줄 — '지금: 없음 · 이 방에서 불림: 백로그 관리자 2회'. 명부 밖·내부 보조는 /hermes-room 상세 보기에만.
    상태줄에 떠 있으면 '지금 누가 있나' 로 읽히므로 지금(일하는 중)과 누적(불림)을 글자로 가른다(사용자 지적 2026-09-28)."""
    called = ", ".join(f"{m['name']} {m['count']}회" for m in room["members"])
    owner = f"주인: {room['owner']} · " if room.get("owner") else ""      # --agent 방(hermes-chat) — 주인이 곧 대화 상대
    return owner + f"지금: {_now_text(room)} · " + (f"이 방에서 불림: {called}" if called else "이 방에서 불린 명부 에이전트 없음")
