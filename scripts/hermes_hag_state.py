#!/usr/bin/env python3
"""세션별 `@hag` 켜짐/꺼짐 상태를 읽고 쓰는 것만 담당한다 — `.hermes/hag/<session>.json`.

켜져 있으면 상태줄에 방 줄("방: …")이 붙는다. 방 목록은 여기 적지 않는다(hermes_hag_rooms 가 매번 만든다).
계획: docs/exec-plans/active/2026-09-28-hag-rooms-ui.md 목표 2

공개: StateError · is_on · set_on
"""

import json
import os
import re

_SESSION = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,63}$")   # 세션 id — 경로 탈출(../) 을 막는다


class StateError(ValueError):
    pass


def _path(project: str, session: str) -> str:
    if not _SESSION.match(session or ""):
        raise StateError(f"세션 id 꼴이 아니다: {str(session)[:40]!r}")
    return os.path.join(project, ".hermes", "hag", f"{session}.json")


def is_on(project: str, session: str) -> bool:
    try:
        with open(_path(project, session), encoding="utf-8") as fh:
            return bool(json.load(fh).get("on"))
    except (OSError, ValueError, StateError):
        return False


def set_on(project: str, session: str, on: bool) -> None:
    path = _path(project, session)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"on": bool(on)}, fh)
    os.replace(tmp, path)
