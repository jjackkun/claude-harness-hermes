#!/usr/bin/env python3
"""세션별 서브에이전트 dispatch 수를 하나 올리고 새 값을 돌려준다 (R-cost G3).

근거: docs/exec-plans/active/2026-10-21-cost-guard-plan.md 목표 G3
      (사고 세션: 사람이 시킨 정상 작업 6개 → 평가로 31개)

단일 책임: `.harness/agent-count/<session>.json` 의 수 더하기와 오래된 파일 정리.
몇 번째에 물을지는 진입 훅이 정한다.

- session_id 는 파일 이름이 되므로 [A-Za-z0-9_-] 만 남긴다. 남는 게 없으면 세지 않는다(None).
- 병렬 dispatch 가 같은 파일을 고치므로 잠금 아래에서 읽고, 임시 파일에 쓴 뒤 rename 한다.
- 쓸 때마다 7일 지난 파일을 지운다 — 세션 끝 훅에 기대지 않는다.
"""

import json
import os
import re
import time

try:
    import fcntl
except ImportError:  # 잠금이 없는 플랫폼 — 병렬 시 수가 덜 셀 수 있다(묻는 시점이 늦어질 뿐)
    fcntl = None

_DIR = os.path.join(".harness", "agent-count")
_KEEP_SECONDS = 7 * 24 * 3600  # 계획 G3 — 한 주 넘은 세션은 다시 열리지 않는다고 본다
_UNSAFE = re.compile(r"[^A-Za-z0-9_-]")


def _prune(folder, now):
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        try:
            # .tmp 는 쓰다 죽은 프로세스가 남긴 것 — 같이 치운다(리뷰 지적)
            if name.endswith((".json", ".tmp")) and now - os.path.getmtime(path) > _KEEP_SECONDS:
                os.remove(path)
        except OSError:
            pass


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return int(json.load(f).get("count", 0))
    except (OSError, ValueError, TypeError, AttributeError):
        return 0


def bump(session_id, root):
    """수를 1 올려 새 값을 돌려준다. 셀 수 없으면 None."""
    safe = _UNSAFE.sub("", str(session_id or ""))
    if not safe:
        return None
    folder = os.path.join(root, _DIR)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, safe + ".json")
    with open(os.path.join(folder, ".lock"), "a") as lock:
        if fcntl:
            fcntl.flock(lock, fcntl.LOCK_EX)
        count = _read(path) + 1
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"count": count, "updated": int(time.time())}, f)
        os.replace(tmp, path)
        _prune(folder, time.time())
    return count
