#!/usr/bin/env python3
"""상태줄의 방 줄만 담당한다 — 켜진 프로젝트면 `방: 게이트QA 대기 · 백로그 관리자 일하는 중 · ← 로 이동`.

상태줄은 `claude` 를 직접 부르지 않는다(기존 `timeout 1` 예산에 CLI 기동이 얹히면 넘친다, 계획 리뷰).
캐시(hermes_hag_rooms.refresh_cache)만 읽고, 캐시가 상태줄 갱신 간격보다 오래됐으면 백그라운드 갱신을 던진 뒤 옛 값을 그린다.
갱신 간격 = hermes_statusline_setup.REFRESH_SECONDS(4초, 실측 2.6·4.0초 간격) — 새 숫자를 만들지 않는다.
계획: docs/exec-plans/completed/2026-09-28-hag-rooms-ui.md 목표 4

공개: hag_line
"""

import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_hag_rooms import CLI_TIMEOUT, read_cache, refreshing_path  # noqa: E402
from hermes_hag_state import is_on  # noqa: E402
from hermes_statusline_setup import REFRESH_SECONDS  # noqa: E402

_STATUS = {"idle": "대기", "busy": "일하는 중"}


def _refresh_in_background(project: str) -> None:
    """갱신 중 표시가 CLI_TIMEOUT 안이면 던지지 않는다 — 느린 `claude agents` 가 겹쳐 쌓이지 않게(리뷰 MEDIUM)."""
    mark = refreshing_path(project)
    try:
        if time.time() - os.path.getmtime(mark) < CLI_TIMEOUT:
            return
    except OSError:
        pass                          # 표시 없음 — 던진다
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hermes_hag_rooms.py")
    try:
        os.makedirs(os.path.dirname(mark), exist_ok=True)
        open(mark, "w").close()
        subprocess.Popen([sys.executable, script, "refresh", project], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass                          # 갱신을 못 던져도 상태줄은 옛 값으로 그린다


def hag_line(project: str) -> str:
    """앞에 줄바꿈을 붙인 방 줄. 꺼진 프로젝트면 빈 문자열."""
    if not is_on(project):
        return ""
    cache, age = read_cache(project)
    if cache is None or age > REFRESH_SECONDS:
        _refresh_in_background(project)
    if cache is None:
        return "\n방: 불러오는 중"
    if cache.get("error"):
        return "\n방: 목록을 못 읽었습니다"
    rooms = " · ".join(f"{r.get('agent') or r.get('slug')} {_STATUS.get(r.get('status'), r.get('status') or '?')}"
                       for r in cache.get("rooms") or [])
    return f"\n방: {rooms or '없음'} · ← 로 이동"
