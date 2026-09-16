#!/usr/bin/env python3
"""소우주 키(universe_id) 하나만 담당한다.

프로젝트 id 가 폴더 이름(basename)이던 것을 `.hermes/universe.id`(UUID v4 한 줄)로 바꾼다.
같은 이름의 폴더가 둘이면 키가 겹치고, 폴더 이름을 바꾸면 과거 기록과 끊기기 때문이다.
설계: docs/hermes-universe/design/world/universe-isolation.md (D-05·D-06)
계획: docs/exec-plans/active/2026-09-15-universe-id-journal.md 목표 1·2

모든 스크립트는 `universe_id(project_path)` 하나로 소우주 키를 얻는다.
"""

import sys
import uuid
from pathlib import Path

_FILE = ".hermes/universe.id"


def universe_id_path(project_path) -> Path:
    """그 소우주의 universe.id 파일 경로."""
    return Path(project_path) / _FILE


def read_universe_id(project_path):
    """저장된 키를 읽는다. 없거나 형식이 아니면 None."""
    p = universe_id_path(project_path)
    try:
        value = p.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    try:
        uuid.UUID(value)
    except ValueError:
        return None
    return value


def ensure_universe_id(project_path) -> str:
    """없으면 만들고, 있으면 그대로 돌려준다. 재설치해도 값이 바뀌지 않는다."""
    existing = read_universe_id(project_path)
    if existing:
        return existing
    p = universe_id_path(project_path)
    p.parent.mkdir(parents=True, exist_ok=True)
    value = str(uuid.uuid4())
    tmp = p.with_suffix(".id.tmp")
    tmp.write_text(value + "\n", encoding="utf-8")
    tmp.replace(p)  # 원자적 — 도중에 죽어도 반쯤 쓰인 키가 남지 않는다
    return value


def universe_id(project_path) -> str:
    """소우주 키. 없으면 폴더 이름으로 폴백하고 경고한다(만들지는 않는다 —
    키 생성은 설치기의 일이고, 읽는 쪽이 만들면 저장소마다 달라진다)."""
    value = read_universe_id(project_path)
    if value:
        return value
    name = Path(project_path).resolve().name
    print(
        f"[hermes] universe.id 없음 — 폴더 이름('{name}')을 키로 씁니다. "
        f"재설치하면 {_FILE} 가 생깁니다.",
        file=sys.stderr,
    )
    return name
