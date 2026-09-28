#!/usr/bin/env python3
"""전역 상태줄을 헤르메스 감싸개로 보장하는 것만 담당한다 — hermes 설치(_hermes_setup)가 컴퓨터마다 부른다.

사용자 요구(2026-09-28): "전파가 되면 어느 컴퓨터이든 상태줄에 붙어야 하는 기능이지 않아?"
  - 설정 폴더: $CLAUDE_CONFIG_DIR, 없으면 ~/.claude
  - statusLine 이 command 면 원래 명령을 hermes-statusline.orig 에 두고 명령을 감싸개로 바꾼다(이미 감싸개면 그대로).
    없으면 감싸개만 건다. command 가 아닌 다른 종류면 손대지 않는다.
  - refreshInterval 이 없을 때만 4(초) — 메인이 서브에이전트를 기다리는 동안에도 "일하는 중" 이 그려지게.
    4 = 2026-09-28 에 잰 가장 짧은 @ 호출(약 8초)의 절반.
  - 처음 고칠 때만 settings.json.bak-hermes 백업. 바뀐 것이 없으면 쓰지 않는다(멱등).
  - 2026-09-28 한 컴퓨터에 손으로 붙인 11줄 블록이 원래 상태줄 스크립트에 있으면 걷어낸다(두 번 찍히지 않게).
  - HERMES_STATUSLINE=0 이면 아무것도 하지 않는다.
계획: docs/exec-plans/active/2026-09-28-agent-room-view.md 목표 6

공개: ensure_statusline · main
"""

import json
import os
import shlex
import shutil
import sys

WRAPPER = "hermes-statusline.sh"
ORIG = "hermes-statusline.orig"
REFRESH_SECONDS = 4
_HAND_BLOCK = """
# 헤르메스 방 구성원(둘째 줄) — 이 방(세션)에서 불린 에이전트. 헤르메스가 깔린 프로젝트에서만, 실패하면 아무것도 안 찍는다.
if command -v jq >/dev/null 2>&1; then
    session_id=$(echo "$input" | jq -r '.session_id // empty')
else
    session_id=$(echo "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p')
fi
if [ -n "$project_dir" ] && [ -n "$session_id" ] && [ -f "$project_dir/scripts/hermes-agent.py" ] && [ -f "$project_dir/.hermes/agents.json" ]; then
    room=$(timeout 1 python3 "$project_dir/scripts/hermes-agent.py" --project "$project_dir" room --session "$session_id" --line 2>/dev/null)
    [ -n "$room" ] && printf "\\n%s" "$room"
fi
"""


def _write_if_changed(path: str, text: str) -> bool:
    if os.path.isfile(path) and open(path, encoding="utf-8").read() == text:
        return False
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return True


def _strip_hand_block(command: str) -> bool:
    """원래 명령이 가리키는 스크립트 파일에서 손 11줄을 걷어낸다. 정확히 같은 글자일 때만."""
    try:
        target = next((t for t in reversed(shlex.split(command)) if os.path.isfile(os.path.expanduser(t))), None)
    except ValueError:
        return False
    if not target:
        return False
    text = open(os.path.expanduser(target), encoding="utf-8").read()
    return _HAND_BLOCK in text and _write_if_changed(os.path.expanduser(target), text.replace(_HAND_BLOCK, "", 1))


def _load(path: str) -> dict:
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _retarget(line: dict, cfg_dir: str, wrapper: str) -> list:
    """statusLine 명령을 감싸개로 — 원래 명령은 .orig 에(이미 감싸개면 그대로)."""
    command = f'bash "{wrapper}"'
    if line.get("command") == command:
        return []
    original = line.get("command") or ""
    _write_if_changed(os.path.join(cfg_dir, ORIG), original)
    line["command"] = command
    return ["손으로 붙인 방 줄 블록 걷어냄"] if original and _strip_hand_block(original) else []


def _save(settings_path: str, settings: dict) -> None:
    if os.path.isfile(settings_path) and not os.path.isfile(settings_path + ".bak-hermes"):
        shutil.copy2(settings_path, settings_path + ".bak-hermes")    # 처음 고칠 때만
    _write_if_changed(settings_path, json.dumps(settings, ensure_ascii=False, indent=2) + "\n")


def ensure_statusline(cfg_dir: str, wrapper_src: str) -> list:
    """한 일 목록(글자). 끄기 스위치면 빈 목록."""
    if os.environ.get("HERMES_STATUSLINE") == "0":
        return []
    os.makedirs(cfg_dir, exist_ok=True)
    wrapper = os.path.join(cfg_dir, WRAPPER)
    done = []
    if _write_if_changed(wrapper, open(wrapper_src, encoding="utf-8").read()):
        os.chmod(wrapper, 0o755)
        done.append("감싸개 갱신")
    settings_path = os.path.join(cfg_dir, "settings.json")
    settings = _load(settings_path)
    before = json.dumps(settings, sort_keys=True)
    line = dict(settings.get("statusLine") or {"type": "command"})
    if line.get("type") != "command":
        return done + ["statusLine 이 command 가 아니라 건너뜀"]
    done += _retarget(line, cfg_dir, wrapper)
    line.setdefault("refreshInterval", REFRESH_SECONDS)
    settings["statusLine"] = line
    if json.dumps(settings, sort_keys=True) != before:
        _save(settings_path, settings)
        done.append("statusLine → 감싸개")
    return done


def main() -> int:
    cfg_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    src = os.path.join(os.path.dirname(os.path.abspath(__file__)), WRAPPER)
    try:
        done = ensure_statusline(cfg_dir, src)
    except (OSError, ValueError) as exc:   # 전역 설정이 깨져 있어도 설치 전체를 세우지 않는다
        print(f"상태줄 감싸개 건너뜀: {exc}", file=sys.stderr)
        return 0
    if os.environ.get("HERMES_STATUSLINE") == "0":
        print("상태줄 감싸개 끔(HERMES_STATUSLINE=0)")
    else:
        print("상태줄 → " + (" · ".join(done) if done else "이미 감싸개(변경 없음)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
