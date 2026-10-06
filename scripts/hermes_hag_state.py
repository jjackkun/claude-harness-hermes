#!/usr/bin/env python3
"""프로젝트별 `@hag` 켜짐/꺼짐 상태를 읽고 쓰는 것만 담당한다 — `.hermes/hag/on.json`.

세션 id 를 열쇠로 쓰지 않는다 — 방에 들어갔다 `←` 로 돌아오면 세션 id 가 바뀌어(2026-10-06 실측) 세션별 상태가 사라졌다.
방 목록(rooms.json)도 프로젝트 단위라 켜짐도 프로젝트 단위로 맞췄다.

켜져 있으면 상태줄에 방 줄("방: …")이 붙는다. 방 목록은 여기 적지 않는다(hermes_hag_rooms 가 매번 만든다).
계획: docs/exec-plans/completed/2026-09-28-hag-rooms-ui.md 목표 2

공개: is_on · set_on
"""

import json
import os


def _path(project: str) -> str:
    return os.path.join(project, ".hermes", "hag", "on.json")


def is_on(project: str) -> bool:
    try:
        with open(_path(project), encoding="utf-8") as fh:
            return bool(json.load(fh).get("on"))
    except (OSError, ValueError):
        return False


def set_on(project: str, on: bool) -> None:
    path = _path(project)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"on": bool(on)}, fh)
    os.replace(tmp, path)
