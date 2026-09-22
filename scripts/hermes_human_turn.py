"""대화 기록 한 줄이 사람이 직접 친 메시지인지 판정한다.

Claude Code 대화 기록에서 role 이 user 인 줄은 사람 입력만이 아니다 — 스킬 본문(isMeta),
서브에이전트 반환(origin.kind == "peer"), 작업 알림(origin.kind == "task-notification"),
압축 요약(isCompactSummary), 도구 결과도 모두 user 로 들어온다. 이것을 사람 말로 읽으면
진화 힌트가 엉뚱한 글에서 나온다(2026-09-21 소우주 3곳 재현 48번 전부).

판정 순서: 기록이 붙인 표시를 먼저 믿고, 표시가 없는 옛 기록만 내용 규칙으로 대신한다.
근거: docs/exec-plans/completed/2026-09-22-evolve-hint-false-positive.md §2-bis

공개 함수 2개: is_human_entry · is_human_message
"""

# load_transcript 가 메시지 사본에 붙이는 판정 결과 칸.
HUMAN_MARK = "hermes_human"

_NON_HUMAN_FLAGS = ("isMeta", "isCompactSummary", "isVisibleInTranscriptOnly")


def _text_of(content) -> str:
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict))
    return str(content or "")


def _looks_typed(message: dict) -> bool:
    """표시가 없는 옛 기록용 대체 규칙 — 도구 결과와 `<` 로 시작하는 주입 글은 사람 입력이 아니다."""
    content = message.get("content")
    if isinstance(content, list) and any(
        isinstance(b, dict) and b.get("type") == "tool_result" for b in content
    ):
        return False
    text = _text_of(content).lstrip()
    return bool(text) and not text.startswith("<")


def is_human_entry(entry: dict) -> bool:
    """JSONL 한 줄(바깥 표시 포함)이 사람이 친 메시지인가."""
    if not isinstance(entry, dict) or entry.get("type") != "user":
        return False
    if any(entry.get(flag) for flag in _NON_HUMAN_FLAGS):
        return False
    origin = entry.get("origin")
    if isinstance(origin, dict) and origin.get("kind"):
        return origin["kind"] == "human"
    return _looks_typed(entry.get("message") or {})


def is_human_message(message: dict) -> bool:
    """로드된 메시지가 사람 입력인가. 로더가 붙인 판정이 있으면 그것을, 없으면 대체 규칙을 쓴다."""
    if not isinstance(message, dict) or message.get("role") != "user":
        return False
    if HUMAN_MARK in message:
        return bool(message[HUMAN_MARK])
    return _looks_typed(message)
