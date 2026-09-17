#!/usr/bin/env python3
"""스킬을 주입용 텍스트로 렌더링만 담당한다 — 헤드라인·스니펫·형식 분기(RV-12, 목표 4).

주입은 스킬 전체가 아니라 요약만 보여 준다: `description` 머리말이 있으면 `이름 — 설명` 한 줄,
없으면 본문 앞부분 스니펫(현행 10줄). 층 신원(hermes_skill_layers)과 분리해 둔다 — 이쪽은
파일을 읽어 문자열을 만들 뿐 층·소유를 모른다.
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 4

공개 함수 3개: skill_headline · read_skill_snippet · inject_text
"""

import re
import sys

_DESC = re.compile(r"^description:\s*(.+)$", re.MULTILINE)


def _log(msg: str) -> None:
    print(f"[hermes-render] {msg}", file=sys.stderr)


def skill_headline(skill_path: str):
    """스킬 파일 머리말의 `description` 한 줄. 없으면 None(구 스킬은 스니펫으로 주입)."""
    try:
        with open(skill_path, encoding="utf-8") as fh:
            head = fh.read(4000)
    except OSError:
        return None
    m = _DESC.search(head)
    if not m:
        return None
    desc = m.group(1).strip().strip("\"'").strip()
    return desc or None


def read_skill_snippet(skill_path: str, max_lines: int = 10) -> str:
    """스킬 파일에서 핵심 내용만 추출한다(주석·빈 줄 제외, 최대 max_lines 줄)."""
    try:
        with open(skill_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except OSError as e:
        _log(f"스킬 스니펫 읽기 실패({skill_path}): {e}")
        return ""
    snippet = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("<!--") or not stripped:
            continue
        snippet.append(stripped)
        if len(snippet) >= max_lines:
            break
    return "\n".join(snippet)


def inject_text(name: str, path: str, prefix: str = "헤르메스 규칙"):
    """주입 한 조각. description 있으면 `[prefix — 이름] 설명` 한 줄, 없으면 스니펫. 둘 다 없으면 None."""
    desc = skill_headline(path)
    if desc:
        return f"[{prefix} — {name}] {desc}"
    snippet = read_skill_snippet(path)
    if not snippet:
        return None
    return f"[{prefix} — {name}]\n{snippet}"
