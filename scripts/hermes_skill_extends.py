#!/usr/bin/env python3
"""`extends:` 머리말 파싱과 기준 버전 대조만 담당한다 — 설치기와 검색기가 공유한다(RV-13).

확장 파일은 아래 층에 두고 머리말에 `extends: <skill_id>@<version>` 을 적는다. `<version>` 은
그 확장을 쓸 때의 **공장 커밋**(`factory.json.installed_version`)이다. `update-all` 로 위 층이
바뀌면(공장 커밋이 달라지면) 설치기가 기준이 어긋난 확장을 찾아 `[extends WARN]` 을 낸다 —
적지 않으면 위 층 수정이 아래로 전달된다는 전제가 조용히 깨진다(설계 skill-layers.md 2절).
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 6

공개 함수 6개: parse_extends · find_extensions · current_version · stale_extensions · warn_stale · resolve_base_path
"""

import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skill_layers import all_layer_dirs  # noqa: E402
from hermes_skills import iter_skill_files  # noqa: E402

_EXTENDS = re.compile(r"^extends:\s*([0-9a-fA-F][0-9a-fA-F-]+)@(\S+)\s*$", re.MULTILINE)


def parse_extends(skill_path: str):
    """머리말 `extends: <skill_id>@<version>` 를 (skill_id, version) 로. 없으면 None."""
    try:
        with open(skill_path, encoding="utf-8") as fh:
            head = fh.read(4000)
    except OSError:
        return None
    m = _EXTENDS.search(head)
    return (m.group(1), m.group(2)) if m else None


def find_extensions(project: str) -> list:
    """네 층을 훑어 `extends:` 를 가진 파일을 모은다. [{path, skill_id, version}]."""
    out = []
    for _layer, skills_dir, _u, _a in all_layer_dirs(project):
        if not os.path.isdir(skills_dir):
            continue
        for _name, skill_md in iter_skill_files(skills_dir):
            ext = parse_extends(skill_md)
            if ext:
                out.append({"path": skill_md, "skill_id": ext[0], "version": ext[1]})
    return out


def current_version(project: str) -> str:
    """지금 설치된 공장 커밋(`factory.json.installed_version`). 없으면 빈 문자열."""
    try:
        with open(os.path.join(project, ".hermes", "factory.json"), encoding="utf-8") as fh:
            return json.load(fh).get("installed_version") or ""
    except (OSError, ValueError):
        return ""


def stale_extensions(project: str, version: str = None) -> list:
    """기준(version)이 현재 공장 커밋과 다른 확장. version 을 안 주면 factory.json 에서 읽는다."""
    cur = version if version is not None else current_version(project)
    if not cur:
        return []                       # 공장 커밋을 모르면 판단하지 않는다(경고 남발 금지)
    return [e for e in find_extensions(project) if e["version"] != cur]


def warn_stale(project: str) -> int:
    """기준이 어긋난 확장마다 `[extends WARN]` 을 stderr 로 낸다. 그 수를 돌려준다."""
    stale = stale_extensions(project)
    for e in stale:
        rel = os.path.relpath(e["path"], project)
        print(f"[extends WARN] {rel}: 기준 {e['version'][:7]} 이 현재 공장과 다름 — "
              "위 층이 바뀌었을 수 있으니 확장을 다시 확인하십시오", file=sys.stderr)
    return len(stale)


def resolve_base_path(db_path: str, skill_id: str) -> str:
    """확장이 가리키는 위 층 원본(skill_id) 의 파일 경로. skill_index 에서 찾는다. 없으면 ''."""
    if not (skill_id and os.path.isfile(db_path)):
        return ""
    try:
        con = sqlite3.connect(db_path)
        row = con.execute(
            "SELECT skill_path FROM skill_index WHERE skill_id=? LIMIT 1", (skill_id,)).fetchone()
        con.close()
    except sqlite3.Error:
        return ""
    return row[0] if row and os.path.isfile(row[0]) else ""
