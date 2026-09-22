#!/usr/bin/env python3
"""대화 기록에서 **사람의 말만** 줄 위치 워터마크로 증분 추출한다.

이 모듈의 책임은 읽기 하나다. DB 도 LLM 도 건드리지 않는다.

왜 entrypoint 로 거르는가:
  `~/.claude/projects/*/*.jsonl` 5,006개 중 `entrypoint=sdk-cli` 4,895개는 헤르메스가
  띄운 한 턴짜리 `claude -p` 기계 프롬프트다(요약기 3,771 · 결정화 881 · 드리밍 69 …).
  사람 대화는 `entrypoint=cli` 108개뿐이다(2026-09-22 실측). 기계 프롬프트를 성향으로
  읽으면 "5슬롯 JSON 을 갱신해 출력하라" 가 사용자 지시가 된다.
  근거: docs/exec-plans/completed/2026-09-22-user-persona-distill-plan.md §7
"""

import json

HUMAN_ENTRYPOINT = "cli"

# 대화형 세션 안에서도 사람이 친 말이 아닌 것 — 하네스·Claude Code 가 user 역할로 넣는다.
MACHINE_PREFIXES = (
    "<command-name>",
    "<command-message>",
    "<local-command",
    "<task-notification",
    "<system-reminder",
    "<bash-",
    "Another Claude session",
    "[SYSTEM NOTIFICATION",
    "Caveat:",
    # 대화 압축 뒤 이어지는 세션의 첫 user 행 — Claude Code 가 쓴 요약문이다(실측 77건).
    "This session is being continued from a previous conversation",
)


def _human_text(record: dict):
    """사람이 친 발화면 그 문자열, 아니면 None."""
    if record.get("type") != "user" or record.get("isMeta"):
        return None
    if record.get("entrypoint") != HUMAN_ENTRYPOINT:
        return None
    content = (record.get("message") or {}).get("content")
    # 목록 content 는 tool_result 등 도구 왕복이다 — 사람이 친 글은 문자열로 온다.
    if not isinstance(content, str):
        return None
    text = content.strip()
    if not text or text.startswith(MACHINE_PREFIXES):
        return None
    return text


def read_new_utterances(path: str, start_line: int):
    """start_line 뒤의 사람 발화 목록과 새 끝줄을 돌려준다.

    파일이 워터마크보다 짧아졌으면(다시 쓰였으면) 처음부터 읽는다.
    깨진 줄은 건너뛴다 — 한 줄 때문에 파일 전체를 잃지 않는다.
    """
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    if start_line > len(lines):
        start_line = 0
    utterances = []
    for offset, line in enumerate(lines[start_line:], start=start_line + 1):
        try:
            record = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(record, dict):
            continue
        text = _human_text(record)
        if text is None:
            continue
        utterances.append({
            "line": offset,
            "session_id": record.get("sessionId"),
            "timestamp": record.get("timestamp"),
            "text": text,
        })
    return utterances, len(lines)
