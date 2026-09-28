#!/usr/bin/env python3
"""이 컴퓨터에서 일하는 사람의 이름표(git `user.name`)를 한 곳에서 돌려주는 것만 담당한다.

이름표일 뿐 신원 증명이 아니다(`user.name` 은 누구나 바꾼다) — "누구와의 대화인지" 를 가르는 데만 쓴다.
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 1

공개: UNKNOWN · person
"""

import subprocess

UNKNOWN = "unknown"


def person(project: str) -> str:
    """git user.name. 없거나 git 을 못 부르면 UNKNOWN."""
    try:
        name = subprocess.run(["git", "-C", project, "config", "user.name"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return name or UNKNOWN
