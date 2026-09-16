#!/usr/bin/env python3
"""하네스·헤르메스 스킬을 skill_index 에 등록한다 — 네 층(universe·common·unit·agent) 모두.

setup.sh / project-claude.sh 실행 시 호출. `--project` 모드는 `all_layer_dirs` 의 네 자리를 훑어
층·소유(unit_id·agent_id)·소우주 키·skill_id 를 채운다. `--skills-dir` 모드는 하위호환(한 폴더만).

skill_id 는 층을 옮겨도 불변이라 처음 볼 때만 부여하고 이후 보존한다(COALESCE).
계획: docs/exec-plans/active/2026-09-15-skill-layers-delivery.md 목표 1·2

사용법:
  python3 hermes-index-skills.py --db PATH --project PATH        # 네 층 전부
  python3 hermes-index-skills.py --db PATH --skills-dir PATH [--scope …]   # 한 폴더(하위호환)
"""

import argparse
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skills import iter_skill_files, extract_keywords
from hermes_skill_layers import (
    all_layer_dirs, ensure_layer_columns, layer_of_path, new_skill_id)
from hermes_universe import read_universe_id


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _scope_of(layer: str) -> str:
    """기존 읽는 코드 호환용 scope 값 — 우주만 'harness', 나머지 'local'."""
    return "harness" if layer == "universe" else "local"


def _upsert(con, skill_md, layer, unit_id, agent_id, universe_id) -> None:
    """스킬 한 줄을 넣거나 갱신한다. skill_id 는 처음만 부여하고 이후 보존한다(신원 불변)."""
    kws = extract_keywords(skill_md)
    name = os.path.basename(os.path.dirname(skill_md)) if skill_md.endswith("SKILL.md") \
        else os.path.basename(skill_md)[:-3]
    keywords = ",".join(sorted(kws)) if kws else name
    # M3 — 사용 통계(used_count/version/created_at)를 보존하려 ON CONFLICT DO UPDATE 를 쓴다.
    con.execute(
        "INSERT INTO skill_index "
        "(skill_path, keywords, scope, layer, unit_id, agent_id, universe_id, skill_id) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(skill_path) DO UPDATE SET "
        "keywords=excluded.keywords, scope=excluded.scope, layer=excluded.layer, "
        "unit_id=excluded.unit_id, agent_id=excluded.agent_id, universe_id=excluded.universe_id, "
        "skill_id=COALESCE(skill_index.skill_id, excluded.skill_id)",
        (skill_md, keywords, _scope_of(layer), layer, unit_id, agent_id,
         universe_id, new_skill_id()),
    )


def index_project(db_path: str, project: str) -> int:
    """네 층 폴더를 모두 훑어 색인한다. 붙인 스킬 수를 돌려준다."""
    if not os.path.isfile(db_path):
        print(f"[hermes] DB not found: {db_path}")
        return 0
    universe_id = read_universe_id(project)
    con = connect_db(db_path)
    ensure_layer_columns(con, universe_id)
    indexed = 0
    for layer, skills_dir, unit_id, agent_id in all_layer_dirs(project):
        if not os.path.isdir(skills_dir):
            continue
        for _name, skill_md in iter_skill_files(skills_dir):
            _upsert(con, skill_md, layer, unit_id, agent_id, universe_id)
            indexed += 1
    con.commit()
    con.close()
    print(f"[hermes] indexed {indexed} skills across layers in {project}")
    return indexed


def index_skills(db_path: str, skills_dir: str, scope: str = "harness") -> int:
    """한 폴더만 색인한다(하위호환). 층은 경로로 되짚는다.

    ⚠️ project 루트를 `skills_dir` 의 2단 상위로 추정하므로 `.claude/skills` · `.hermes/skills`
    같은 **2단 중첩 경로에서만 정확하다**. 단위·개인(3단 중첩)은 `index_project`(`--project`)를 쓴다.
    """
    if not os.path.isfile(db_path):
        print(f"[hermes] DB not found: {db_path}")
        return 0
    if not os.path.isdir(skills_dir):
        return 0
    project = os.path.dirname(os.path.dirname(os.path.abspath(skills_dir)))
    universe_id = read_universe_id(project)
    con = connect_db(db_path)
    ensure_layer_columns(con, universe_id)
    indexed = 0
    for _name, skill_md in iter_skill_files(skills_dir):
        layer, unit_id, agent_id = layer_of_path(project, skill_md)
        _upsert(con, skill_md, layer, unit_id, agent_id, universe_id)
        indexed += 1
    con.commit()
    con.close()
    print(f"[hermes] indexed {indexed} skills from {skills_dir}")
    return indexed


def main():
    parser = argparse.ArgumentParser(description="헤르메스 스킬 인덱싱")
    parser.add_argument("--db", required=True, help="state.db 경로")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--project", help="소우주 루트 — 네 층 전부 색인")
    group.add_argument("--skills-dir", help=".claude/skills 경로(한 폴더, 하위호환)")
    parser.add_argument("--scope", default="harness", help="스킬 범위(하위호환, 미사용)")
    args = parser.parse_args()

    if args.project:
        index_project(args.db, os.path.abspath(args.project))
    else:
        index_skills(args.db, args.skills_dir, args.scope)


if __name__ == "__main__":
    main()
