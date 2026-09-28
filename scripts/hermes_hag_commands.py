#!/usr/bin/env python3
"""보낸 글의 `@hag-on/off/add/rm` 을 알아보고 상태·방 함수를 불러 안내 한 줄을 돌려주는 것만 담당한다.

훅(claude-userpromptsubmit-hag.sh)이 stdin 으로 훅 입력을 주고, 명령이면 안내를 stdout 에 내고 exit 2 — 훅이 그 줄을
stderr 로 옮겨 프롬프트를 막는다(모델 답 없음, Step 1 실측). 명령이 아니면 아무것도 내지 않고 exit 0.
모양: `@hag-on` · `@hag-off` · `@hag-add`(맨몸=초대할 사람 안내 · 이름 · 목록에서 고른 `hag-add:<slug>`) ·
      `@hag-rm`(맨몸=열린 방 안내 · 목록에서 고른 `hag-rm:<id>`). 백틱 안은 말하는 것이라 무시.
명령은 **메시지 맨 앞**에 있을 때만 — 문장 속 언급("그냥 @hag-on 치면 켜져요?")은 논의다(코드 리뷰 HIGH, 2026-09-28).
뒤에 붙는 말: on/off/rm 은 없어야, add 는 이름 한 단어까지. 그보다 길면 논의로 보고 통과시킨다.
계획: docs/exec-plans/active/2026-09-28-hag-rooms-ui.md 목표 2 · 3 · 5

공개: handle · main
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_hag_rooms import RoomsError, list_rooms, open_room, refresh_cache, stop_room  # noqa: E402
from hermes_hag_state import StateError, set_on  # noqa: E402
from hermes_roster_pick import match, pickable, room_name  # noqa: E402

_CMD = re.compile(r"(?:@\"[^\"]*|(?<![\w.])@)hag-(on|off|add|rm)(?::([A-Za-z0-9-]{1,40}))?(?![\w-])", re.I)
_STATUS = {"idle": "대기", "busy": "일하는 중"}


def _status(room: dict) -> str:
    return _STATUS.get(room.get("status") or "", room.get("status") or "?")


def _chosen(people: list, picked: str, rest: str) -> list:
    """목록에서 고른 slug 가 먼저, 없으면 이름 한 단어로 거른 사람."""
    if picked:
        return [a for a in people if a["slug"] == picked]
    return match(people, rest) if rest else []


def _add(project: str, picked: str, rest: str) -> str:
    taken = {r["slug"] for r in list_rooms(project)}
    people = pickable(project)
    free = [a for a in people if a["slug"] not in taken]
    chosen = _chosen(people, picked, rest)
    if not chosen:
        names = ", ".join(a["name"] for a in free) or "없음(모두 방이 있음)"
        return f"[hag] 초대할 수 있는 에이전트: {names} — `@hag-add` 를 치고 화살표로 골라 엔터"
    agent = chosen[0]
    if agent["slug"] in taken:
        return f"[hag] {agent['name']} 방은 이미 있습니다 — ← 두 번으로 들어가십시오"
    open_room(project, agent)
    refresh_cache(project)
    return f"[hag] {room_name(agent)} 을 열었습니다 — ← 두 번으로 들어가 직접 대화"


def _rm(project: str, picked: str) -> str:
    rooms = list_rooms(project)
    target = [r for r in rooms if r["id"] == picked] if picked else []
    if not target:
        opened = ", ".join(f"{r['agent']}({_status(r)})" for r in rooms) or "없음"
        return f"[hag] 열린 방: {opened} — `@hag-rm` 을 치고 화살표로 골라 엔터"
    stop_room(project, target[0]["id"])
    refresh_cache(project)
    return f"[hag] {target[0]['agent']} 방을 닫았습니다(대화는 남음 — claude --resume {target[0]['name']} 으로 다시)"


def _parse(prompt: str):
    """(명령, 고른 값, 뒤 말) — 명령이 아니면 None. 백틱 안은 말하는 것, 명령은 맨 앞만."""
    text = re.sub(r"`[^`]*`", " ", prompt or "").strip()
    found = _CMD.match(text)
    if not found:
        return None
    cmd, picked = found.group(1).lower(), (found.group(2) or "")
    words = text[found.end():].lstrip('"').split()
    if not picked and len(words) > (1 if cmd == "add" else 0):
        return None                                # 말이 붙어 있으면 명령이 아니라 논의
    return cmd, picked, " ".join(words)


def _run(project: str, session: str, cmd: str, picked: str, rest: str) -> str:
    if cmd in ("on", "off"):
        set_on(project, session, cmd == "on")
        return "[hag] 켰습니다 — 상태줄에 방 줄이 보입니다" if cmd == "on" else "[hag] 껐습니다"
    return _add(project, picked, rest) if cmd == "add" else _rm(project, picked)


def handle(project: str, session: str, prompt: str):
    """명령이면 안내 한 줄, 아니면 None."""
    parsed = _parse(prompt)
    if parsed is None:
        return None
    try:
        return _run(project, session, *parsed)
    except RoomsError as exc:
        return f"[hag] 방 목록을 못 읽었습니다: {exc} — claude agents 를 직접 확인하십시오"
    except StateError as exc:
        return f"[hag] 이 세션 상태를 못 적었습니다: {exc}"


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return 0
    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    message = handle(project, str(data.get("session_id") or ""), str(data.get("prompt") or ""))
    if message is None:
        return 0
    print(message)
    return 2


if __name__ == "__main__":
    sys.exit(main())
