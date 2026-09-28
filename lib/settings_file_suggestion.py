#!/usr/bin/env python3
"""settings.json 의 fileSuggestion 을 넣고 걷는 규칙만 담당한다 — generate_settings_json.py 가 부른다.

fileSuggestion 은 `@` 파일 목록을 통째로 교체하는 한 칸짜리 설정이다(settings-reference "fileSuggestion").
사용자가 자기 스크립트를 넣어 두었으면 우리 것으로 덮지 않는다 — 덮으면 사용자의 파일 검색이 사라진다.
우리 것 = command 에 hermes_file_suggest 가 들어 있다. 프리셋이 빠지면 우리 것만 걷는다.
계획: docs/exec-plans/active/2026-09-28-hermes-chat.md 목표 6

공개: OURS_MARK · apply_file_suggestion
"""

OURS_MARK = "hermes_file_suggest"


def _is_ours(value) -> bool:
    return isinstance(value, dict) and OURS_MARK in str(value.get("command") or "")


def apply_file_suggestion(existing: dict, command) -> dict:
    """새 dict 를 돌려준다(입력은 고치지 않는다). command 가 비면 우리 것만 걷는다."""
    result = dict(existing)
    current = result.get("fileSuggestion")
    if command:
        if current is None or _is_ours(current):
            result["fileSuggestion"] = {"type": "command", "command": command}
    elif _is_ours(current):
        result.pop("fileSuggestion", None)
    return result
