#!/usr/bin/env python3
"""기계가 이미 아는 실제 사람 이름을 마스킹 정답지로 모은다 (T-20 ③, 계획 2026-09-20-transport-plain 목표 4).

사람이 목록을 적지 않는다 — 열쇠처럼 강제가 되면 켜지지 않는다(2026-09-20 논의). 컴퓨터가 이미 아는 것만 쓴다:
  · `git config user.name`  · 최근 커밋 작성자(200건)  · OS 사용자명
명부의 에이전트 이름은 넣지 않는다 — 사람이 아니라 기계 식별자이고, 작업 이력의 결정 칸(chosen=…)에 데이터로 들어간다(2026-09-20 실측 과마스킹).
값은 절대 stdout/stderr 로 내지 않는다 — 가리려던 값을 로그로 흘리면 방어가 무의미하다.
너무 짧거나 일반어인 값(예: main, 두 글자 미만, ASCII 4자 미만)은 뺀다 — 산문을 망가뜨리는 과마스킹을 막는다.
공개 함수 1개: load_known_names
"""
import getpass
import os
import subprocess
from functools import lru_cache

_SKIP = {"main", "root", "user", "admin", "test", "tester", "bot", "system", "installer"}


def _git_names(project_dir: str) -> set:
    names = set()
    try:
        out = subprocess.run(["git", "-C", project_dir, "config", "user.name"],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        if out:
            names.add(out)
        out = subprocess.run(["git", "-C", project_dir, "log", "-200", "--format=%an"],
                             capture_output=True, text=True, timeout=3).stdout
        names.update(line.strip() for line in out.splitlines() if line.strip())
    except (OSError, subprocess.SubprocessError):
        pass
    return names


def _keep(value: str) -> bool:
    v = (value or "").strip()
    if len(v) < 2 or v.lower() in _SKIP:
        return False
    if v.isascii() and len(v) < 4:
        return False
    return True


@lru_cache(maxsize=8)
def load_known_names(project_dir: str = None) -> tuple:
    """마스킹할 이름들의 튜플(긴 것부터). 실패는 빈 튜플 — 마스킹 상위 겹이 계속 돈다."""
    project_dir = project_dir or os.getcwd()
    names = set()
    names |= _git_names(project_dir)
    try:
        names.add(getpass.getuser())
    except Exception:  # noqa: BLE001 — 사용자명을 못 얻는 환경
        pass
    return tuple(sorted((n for n in names if _keep(n)), key=len, reverse=True))
