#!/usr/bin/env python3
"""헤르메스 스킬 파일 공유 헬퍼.

index/search 가 공통으로 쓰는 (1) 스킬 파일 순회 (2) 키워드 추출 을 단일화한다.
폴더형 <name>/SKILL.md 와 헤르메스 자동 생성 평면 <name>.md 를 모두 다룬다 (M4).
"""

import os
import re
import sys


def iter_skill_files(skills_dir: str):
    """스킬 디렉토리에서 (이름, SKILL.md 경로) 쌍을 순회한다."""
    try:
        entries = list(os.scandir(skills_dir))
    except OSError as e:
        print(f"[hermes] 스킬 디렉토리 열기 실패({skills_dir}): {e}", file=sys.stderr)
        return
    for entry in entries:
        if entry.is_dir():
            skill_md = os.path.join(entry.path, "SKILL.md")
            if os.path.isfile(skill_md):
                yield entry.name, skill_md
        elif entry.is_file() and entry.name.endswith(".md"):
            yield entry.name[:-3], entry.path


def extract_keywords(skill_path: str) -> set:
    """제목·트리거 섹션·인라인 코드에서 길이≥2 토큰 집합을 뽑는다."""
    try:
        with open(skill_path, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        print(f"[hermes] 스킬 읽기 실패({skill_path}): {e}", file=sys.stderr)
        return set()

    keywords = set()
    title = re.search(r"^#\s+(.+)$", content, re.MULTILINE)
    if title:
        keywords.update(
            w for w in re.findall(r"[a-z0-9가-힣_\-]+", title.group(1).lower()) if len(w) >= 2
        )
    trig = re.search(r"## 트리거\s*\n(.+?)(?=\n##|\Z)", content, re.DOTALL)
    if trig:
        keywords.update(
            w for w in re.findall(r"[a-z0-9가-힣_\-]+", trig.group(1).lower()) if len(w) >= 2
        )
    # 헤르메스 자동생성 스킬은 제목이 영문 슬러그·트리거 섹션이 없고 한글이
    # 문제 상황·규칙 섹션에 있다 — 한글 질의 검색을 위해 이 섹션도 색인한다.
    for header in ("문제 상황", "규칙"):
        sec = re.search(rf"##\s+{header}\s*\n(.+?)(?=\n##|\Z)", content, re.DOTALL)
        if sec:
            keywords.update(
                w for w in re.findall(r"[a-z0-9가-힣_\-]+", sec.group(1).lower()) if len(w) >= 2
            )
    for code in re.findall(r"`([^`]+)`", content):
        keywords.update(
            w for w in re.findall(r"[a-z0-9가-힣_\-]+", code.lower()) if len(w) >= 2
        )
    return keywords
