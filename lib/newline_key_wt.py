#!/usr/bin/env python3
"""Responsibility: Windows Terminal settings.json 에 shift+enter → ESC CR 보내기가 없으면 더한다.

사용: newline_key_wt.py [--dry-run] <settings.json> [...]
파일마다 출력 한 줄: added | would-add | kept | skipped  (": 경로/이유" 가 붙는다)

왜: Windows Terminal 은 shift+enter 를 enter 와 같은 신호(CR)로 보내서, Claude Code
keybindings.json 만으로는 개행이 안 된다(2026-10-07 실측). 터미널이 다른 신호를 보내게 한다.
사용자가 shift+enter 를 이미 정해 두었으면 건드리지 않는다. 고치기 전에 백업을 뜬다.
주석이 든(JSONC) 파일은 다시 쓰면 주석이 사라지므로 건너뛴다.
"""
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

KEY = "shift+enter"
# ESC CR — Claude Code 2.1.292 프롬프트에 넣어 개행으로 들어가는 것을 쟀다(2026-10-07).
NEWLINE_INPUT = "\u001b\r"
ACTION_ID = "User.sendInput.ShiftEnterNewline"
COMMAND = {"action": "sendInput", "input": NEWLINE_INPUT}
BACKUP_INFIX = ".bak-newline-key-"
JSON_INDENT = 4  # Windows Terminal 이 스스로 저장할 때 쓰는 들여쓰기


def normalize(key):
    return "".join(str(key).lower().split())


def keys_of(entry):
    keys = entry.get("keys") if isinstance(entry, dict) else None
    return [keys] if isinstance(keys, str) else (keys if isinstance(keys, list) else [])


def has_key(data):
    entries = [*as_list(data.get("keybindings")), *as_list(data.get("actions"))]
    return any(normalize(k) == KEY for e in entries for k in keys_of(e))


def as_list(value):
    return value if isinstance(value, list) else []


def with_key(data):
    """keybindings 배열이 있으면 새 형식(id 로 연결), 없으면 옛 형식(액션에 keys)으로 더한다."""
    actions = as_list(data.get("actions"))
    if isinstance(data.get("keybindings"), list):
        return {
            **data,
            "actions": [*actions, {"command": COMMAND, "id": ACTION_ID}],
            "keybindings": [*data["keybindings"], {"id": ACTION_ID, "keys": KEY}],
        }
    return {**data, "actions": [*actions, {"command": COMMAND, "keys": KEY}]}


def apply(path, dry_run):
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as err:
        return f"skipped: {path} 를 JSON 으로 읽지 못했습니다 — 주석이 있으면 손으로 넣으십시오 ({err})"
    if not isinstance(data, dict):
        return f"skipped: {path} 의 최상위가 객체가 아닙니다"
    if has_key(data):
        return f"kept: {path} 에 {KEY} 가 이미 있습니다"
    if dry_run:
        return f"would-add: {path}"
    backup = f"{path}{BACKUP_INFIX}{datetime.now():%Y%m%d-%H%M%S}"
    shutil.copy2(path, backup)
    path.write_text(json.dumps(with_key(data), indent=JSON_INDENT) + "\n", encoding="utf-8")
    return f"added: {path} (백업 {Path(backup).name})"


def main(argv):
    dry_run = "--dry-run" in argv[1:]
    paths = [Path(a) for a in argv[1:] if a != "--dry-run"]
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    for path in paths:
        print(apply(path, dry_run))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
