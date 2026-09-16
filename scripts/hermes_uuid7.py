#!/usr/bin/env python3
"""UUIDv7 생성 (RFC 9562 §5.7).

Python 3.10(WSL 시스템)·3.12(pyenv) 어느 쪽에도 `uuid.uuid7` 이 없어 직접 만든다.
표준에 들어오면 이 함수 하나만 교체한다.
근거: docs/exec-plans/active/2026-09-15-universe-id-journal.md §6.

시간 48비트가 앞에 오므로 문자열 정렬이 곧 시간순 정렬이다 — 작업 이력의 PK 로 쓴다.
"""

import os
import time
import uuid


def uuid7() -> uuid.UUID:
    """시간순으로 정렬되는 UUID 하나."""
    ms = int(time.time() * 1000) & 0xFFFFFFFFFFFF  # 48비트 밀리초
    rand = os.urandom(10)
    b = bytearray(ms.to_bytes(6, "big") + rand)
    b[6] = (b[6] & 0x0F) | 0x70  # version 7
    b[8] = (b[8] & 0x3F) | 0x80  # variant 10
    return uuid.UUID(bytes=bytes(b))


def uuid7_str() -> str:
    """uuid7() 의 문자열 표기."""
    return str(uuid7())
