#!/usr/bin/env python3
"""명부 전원 표와 방 구성원을 사람이 읽는 글자(표 · 상태줄 한 줄)로 그리는 것만 담당한다. 계산은 hermes_room.py.

계획: docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 1·2

공개: render_roster · render_room · render_room_line
"""

import unicodedata
from datetime import datetime

_STATUS_ORDER = {"active": 0, "probation": 1, "retired": 2}
_STATUS_KO = {"active": "재직", "probation": "수습", "retired": "은퇴"}


def _width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def _pad(text: str, width: int) -> str:
    return text + " " * max(0, width - _width(text))


def _when(ts: str) -> str:
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
                     _when(seen.get(a["agent_id"], ""))])
    if not rows:
        return "명부에 에이전트가 없습니다 (입사: hermes-agent.py hire)"
    body = _table(rows, ["이름", "호출", "상태", "분야/직급/조직", "최근 불린 때"])
    return "\n".join(body + [f"({len(rows)}명 · 은퇴자는 맨 아래 · 부르기: @<호출명 앞부분> 또는 한글 이름)"])


def render_room(room: dict, session_id: str) -> str:
    out = [f"이 방(세션 {session_id[:8]}…)에서 불린 에이전트"]
    if room["members"]:
        rows = [[m["name"], f"@agent-{m['slug']}" if m.get("slug") else "-", f"{m['count']}회", _when(m["last"])]
                for m in room["members"]]
        out += _table(rows, ["명부 에이전트", "호출", "횟수", "마지막"])
    else:
        out.append("명부 에이전트: 없음")
    if room["tools"]:
        out.append("명부 밖 에이전트: " + " · ".join(f"{k} {v}" for k, v in sorted(room["tools"].items())))
    out.append(f"내부 보조 호출: {room['internal']}건 (Claude Code 가 안에서 띄운 것 — 이름 없이 셈)")
    return "\n".join(out)


def render_room_line(room: dict) -> str:
    """상태줄 한 줄 — '방: 백로그 관리자(2) · 도구 2 · 보조 40'."""
    names = ", ".join(f"{m['name']}({m['count']})" for m in room["members"]) or "명부 에이전트 없음"
    return f"방: {names} · 도구 {sum(room['tools'].values())} · 보조 {room['internal']}"
