#!/usr/bin/env python3
"""열린 문서 판정 — 아직 끝나지 않은 계획서·기획서를 고른다. git 을 부르지 않는 순수 함수다.

worktree 마무리(finish.sh)가 이 판정으로 "계획이 끝나기 전에 worktree 를 지우는 일" 을 막는다(멈춤 24).
입력은 (저장소 기준 경로, 작업 트리 본문 또는 None) 목록이다. None 은 작업 트리에 없는 경로다(지움 · 옛 이름).

- 계획서: `docs/exec-plans/{active,completed}/YYYY-MM-DD-*.md` — §2 안에 `[ ]` 가 남았거나 §2 절이 없으면 열림
- 기획서: `docs/product-specs/*/prd.md` — `status:` 첫 낱말이 `approved` 가 아니면 열림(줄 없음 · 모르는 값 포함)
- 못 읽는 경우는 모두 열림이다 — 지우지 않으면 되돌릴 수 있고, 지우면 되돌릴 수 없다.

계획: docs/exec-plans/completed/2026-11-25-worktree-finish-open-docs-plan.md (G1 · 규칙표 P1~P7 · D1~D2 · F1)
"""

from __future__ import annotations

import re

_ACTIVE = "docs/exec-plans/active/"
_COMPLETED = "docs/exec-plans/completed/"
_PLAN_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[^/]*\.md$")
_PRD_PATH = re.compile(r"^docs/product-specs/[^/]+/prd\.md$")

_SECTION_START = re.compile(r"^## 2\.")  # P1 — `## 2-bis` 는 시작이 아니다
_SECTION_END = re.compile(r"^## ")  # P2 — 해시 정확히 둘. `### G1` 에서는 끊지 않는다
_OPEN_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[ \]")  # P3 — 줄 맨 앞 고정, 번호 목록 포함. P4: [x]·[X] 는 걸리지 않는다
_DONE_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[[xX]\]")
# P5 — 여는 펜스: 같은 글자(` 또는 ~) 3개 이상. 백틱 펜스의 뒷말에 백틱이 있으면 펜스가 아니다(```x``` 한 줄 코드).
_FENCE_OPEN = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
_STATUS = re.compile(r"^\s*[-*]?\s*status:\s*(.*)$", re.IGNORECASE)  # D1


class UnclosedFence(ValueError):
    """코드 펜스가 파일 끝까지 닫히지 않았다 — 뒤의 줄을 읽을 수 없으므로 열린 문서로 본다."""


def _opens(line: str) -> str | None:
    m = _FENCE_OPEN.match(line)
    if not m or (m.group(1)[0] == "`" and "`" in m.group(2)):
        return None
    return m.group(1)


def _closes(line: str, fence: str) -> bool:
    """닫는 펜스: 들여쓰기 3칸 이하, 여는 글자만으로 여는 길이 이상."""
    stripped = line.strip()
    indent = len(line) - len(line.lstrip(" "))
    return indent <= 3 and len(stripped) >= len(fence) and set(stripped) == {fence[0]}


def _outside_fences(body: str) -> list[str]:
    """코드 펜스 안의 줄을 뺀 줄 목록(P5). 닫는 줄은 여는 줄과 같은 글자로 길이 이상이어야 한다."""
    lines, fence = [], None
    for line in body.splitlines():
        if fence is None:
            fence = _opens(line)
            if fence is None:
                lines.append(line)
        elif _closes(line, fence):
            fence = None
    if fence is not None:
        raise UnclosedFence(fence)
    return lines


def _section(body: str) -> list[str] | None:
    """§2 의 줄들(P1 · P2). 절이 없으면 None(P6)."""
    lines, inside = [], False
    for line in _outside_fences(body):
        if inside and _SECTION_END.match(line):
            break
        if not inside and _SECTION_START.match(line):
            inside = True
            continue
        if inside:
            lines.append(line)
    return lines if inside else None


def open_items(body: str) -> int | None:
    """§2 안의 열린 항목 수. §2 절이 없으면 None(P6)."""
    section = _section(body)
    return None if section is None else sum(1 for line in section if _OPEN_ITEM.match(line))


def prd_status(body: str) -> str | None:
    """기획서 상태 줄의 첫 낱말(소문자, 따옴표 벗김). 줄이 없으면 None."""
    for line in _outside_fences(body):
        m = _STATUS.match(line)
        if m:
            words = m.group(1).split()
            return words[0].strip("'\"").lower() if words else ""
    return None


def _plan_reason(path: str, body: str) -> str | None:
    section = _section(body)
    if section is None:
        return "§2 절 없음"
    n = sum(1 for line in section if _OPEN_ITEM.match(line))
    if n == 0:
        # P9 — 체크 항목이 하나도 없는 §2 는 끝났는지 읽을 수 없다
        return None if any(_DONE_ITEM.match(line) for line in section) else "§2 항목 없음"
    return f"completed 인데 §2 미완료 {n}개" if path.startswith(_COMPLETED) else f"§2 미완료 {n}개"


def _prd_reason(body: str) -> str | None:
    status = prd_status(body)
    if status == "approved":
        return None
    return "status 줄 없음" if status is None else f"status: {status or '(빈 값)'}"


def _is_plan(path: str) -> bool:
    for prefix in (_ACTIVE, _COMPLETED):
        if path.startswith(prefix) and _PLAN_NAME.match(path[len(prefix):]):
            return True
    return False


def open_docs(docs: list[tuple[str, str | None]]) -> list[tuple[str, str]]:
    """(경로, 이유) — 열린 문서만, 경로 순. 작업 트리에 없는 경로와 대상이 아닌 파일은 건너뛴다(F1)."""
    found = []
    for path, body in sorted(docs):
        if body is None:
            continue
        if not (_is_plan(path) or _PRD_PATH.match(path)):
            continue
        try:
            reason = _plan_reason(path, body) if _is_plan(path) else _prd_reason(body)
        except UnclosedFence:
            reason = "코드 펜스가 닫히지 않음"  # P8
        if reason:
            found.append((path, reason))
    return found
