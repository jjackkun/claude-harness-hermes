#!/usr/bin/env python3
"""이 프로젝트의 에이전트 방(백그라운드 세션)을 찾고·열고·닫고, 상태줄용 방 목록 캐시를 두는 것만 담당한다.

방 = `claude agents --json` 중 cwd 가 프로젝트 루트와 같거나 그 아래이고, 방 주인 기록(journal task.assigned
`match=owner`, room-owner 훅)이 있는 세션. 에이전트는 이름이 아니라 sessionId → 주인 기록의 slug 로 안다.
여는 자식에는 환경변수 허용목록만 넘긴다 — 부모의 HERMES_AGENT_ID 가 새면 새 방이 부모 정체성으로 출근한다.
`claude` 위치는 HERMES_CLAUDE_BIN(시험용), 없으면 PATH 의 claude.
계획: docs/exec-plans/active/2026-09-28-hag-rooms-ui.md 목표 3 · 4 · 5

공개: CLI_TIMEOUT · RoomsError · list_rooms · open_room · stop_room · refresh_cache · read_cache · refreshing_path
"""

import json
import os
import re
import sqlite3
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_roster_pick import pickable, room_name  # noqa: E402

# 구독 토큰(CLAUDE_CODE_OAUTH_TOKEN)은 넘긴다 — 토큰으로 로그인한 사람의 방이 인증을 잃지 않게.
# ANTHROPIC_API_KEY 는 넘기지 않는다(R3 — 구독 경로만).
_KEEP_ENV = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "TERM", "TMPDIR", "CLAUDE_CONFIG_DIR",
             "CLAUDE_CODE_OAUTH_TOKEN")
_KEEP_PREFIX = ("LC_", "XDG_")
CLI_TIMEOUT = 30           # --bg 는 즉시 돌아온다(실측) — 멈춘 CLI 가 훅을 붙잡지 않게 넉넉한 상한만
_ROOM_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")   # '-' 로 시작하면 CLI 가 옵션으로 읽는다(리뷰 LOW)


class RoomsError(RuntimeError):
    pass


def _claude() -> str:
    return os.environ.get("HERMES_CLAUDE_BIN") or "claude"


def _child_env() -> dict:
    return {k: v for k, v in os.environ.items() if k in _KEEP_ENV or k.startswith(_KEEP_PREFIX)}


def _run(project: str, args: list) -> str:
    try:
        res = subprocess.run([_claude(), *args], cwd=project, env=_child_env(),
                             capture_output=True, text=True, timeout=CLI_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RoomsError(str(exc)) from exc
    if res.returncode != 0:
        lines = (res.stderr or res.stdout or "").strip().splitlines()
        raise RoomsError(lines[0] if lines else f"exit {res.returncode}")
    return res.stdout


def _owners(project: str) -> dict:
    """세션 id → 방 주인 slug (방 주인 기록에서)."""
    db = os.path.join(project, ".hermes", "state.db")
    if not os.path.isfile(db):
        return {}
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        rows = con.execute("SELECT session_id, decision FROM journal_events WHERE kind='task.assigned' "
                           "AND decision LIKE 'match=owner %'").fetchall()
        con.close()
    except sqlite3.Error:
        return {}
    return {sid: w[5:] for sid, d in rows for w in (d or "").split() if w.startswith("slug=")}


def _inside(cwd: str, project: str) -> bool:
    root = os.path.realpath(project)
    here = os.path.realpath(cwd or "/")
    return here == root or here.startswith(root + os.sep)


def list_rooms(project: str) -> list:
    """[{id, slug, agent, name, status}] — 이 프로젝트의 에이전트 방만(agent = 명부 이름, name = 세션 이름). 못 읽으면 RoomsError."""
    try:
        sessions = json.loads(_run(project, ["agents", "--json"]) or "[]")
    except ValueError as exc:
        raise RoomsError(f"목록 형식: {exc}") from exc
    owners = _owners(project)
    names = {a["slug"]: a["name"] for a in pickable(project)}
    rooms = []
    for s in sessions:
        slug = owners.get(s.get("sessionId")) if isinstance(s, dict) else None
        if slug and _inside(s.get("cwd"), project):
            rooms.append({"id": s.get("id"), "slug": slug, "agent": names.get(slug, slug),
                          "name": s.get("name"), "status": s.get("status")})
    return rooms


def open_room(project: str, agent: dict) -> str:
    """방을 연다. 돌아온 첫 줄(예: backgrounded · <id> · <방>)."""
    out = _run(project, ["--bg", "--agent", agent["slug"], "--name", room_name(agent)])
    return (out.strip().splitlines() or [""])[0]


def stop_room(project: str, room_id: str) -> str:
    if not _ROOM_ID.match(room_id or ""):
        raise RoomsError(f"방 id 꼴이 아니다: {str(room_id)[:20]!r}")
    return _run(project, ["stop", room_id]).strip()


def _cache_path(project: str) -> str:
    return os.path.join(project, ".hermes", "hag", "rooms.json")


def refreshing_path(project: str) -> str:
    """갱신 중 표시 — 상태줄이 갱신을 겹쳐 던지지 않게(리뷰 MEDIUM). 갱신이 끝나면 지운다."""
    return os.path.join(project, ".hermes", "hag", "rooms.refreshing")


def refresh_cache(project: str) -> dict:
    """목록을 새로 받아 캐시에 쓴다. 실패도 캐시에 적는다(상태줄이 "못 읽음" 을 그리게)."""
    try:
        data = {"ts": time.time(), "rooms": list_rooms(project), "error": ""}
    except RoomsError as exc:
        data = {"ts": time.time(), "rooms": [], "error": str(exc)}
    path = _cache_path(project)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False)
    os.replace(path + ".tmp", path)
    try:
        os.remove(refreshing_path(project))
    except OSError:
        pass
    return data


def read_cache(project: str):
    """(캐시 dict 또는 None, 나이 초)."""
    try:
        with open(_cache_path(project), encoding="utf-8") as fh:
            data = json.load(fh)
        return data, time.time() - float(data.get("ts") or 0)
    except (OSError, ValueError):
        return None, float("inf")


if __name__ == "__main__":        # 상태줄이 백그라운드로 던지는 갱신: python3 hermes_hag_rooms.py refresh <project>
    if len(sys.argv) == 3 and sys.argv[1] == "refresh":
        refresh_cache(sys.argv[2])
