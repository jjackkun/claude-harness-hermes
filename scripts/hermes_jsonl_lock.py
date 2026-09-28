#!/usr/bin/env python3
"""추가만 하는 jsonl 파일에 새 줄을 잠근 채 붙이는 것만 담당한다.

두 세션(Stop 훅 두 개)이 같은 파일에 동시에 붙이면, 각자 읽어 둔 id 집합으로 판단해 같은 줄을 두 번 쓴다(리뷰 MEDIUM).
그래서 잠근 **뒤에** 파일을 다시 읽어 이미 있는 id 를 거른다. 잠금이 없는 곳(fcntl 없는 Windows 파이썬)은 잠그지 않고
같은 순서로 쓴다 — 들이는 쪽이 id 로 중복을 거르므로 DB 는 안전하고, 파일에 겹친 줄이 생길 수 있을 뿐이다.
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 4 · 6

공개: SAFE_ID · locked_append
"""

import json
import os
import re

try:
    import fcntl
except ImportError:                       # Windows 파이썬
    fcntl = None

SAFE_ID = re.compile(r"[A-Za-z0-9_-]+")   # 경로에 쓰는 id — 명부 id(uuid7)·slug 모양


def _ids(fh, key: str) -> set:
    fh.seek(0)
    ids = set()
    for line in fh:
        try:
            ids.add(json.loads(line)[key])
        except (ValueError, KeyError, TypeError):
            continue                      # 깨진 줄(병합 중 잘린 줄)은 건너뛴다
    return ids


def locked_append(path: str, key: str, rows: list) -> int:
    """rows(dict) 중 key 가 파일에 없는 것만 끝에 붙인다. 붙인 줄 수."""
    if not rows:
        return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a+", encoding="utf-8") as fh:
        if fcntl is not None:
            fcntl.flock(fh, fcntl.LOCK_EX)
        seen, written = _ids(fh, key), 0
        fh.seek(0, os.SEEK_END)
        for row in rows:
            if row.get(key) in seen:
                continue
            fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
            seen.add(row.get(key))
            written += 1
    if not written and os.path.getsize(path) == 0:
        os.remove(path)                   # 처음 만든 빈 파일을 남기지 않는다
    return written
