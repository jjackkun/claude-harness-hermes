#!/usr/bin/env python3
"""기존 하네스 스킬을 헤르메스 skill_index에 등록하는 스크립트.

setup.sh / project-claude.sh 실행 시 호출.
.claude/skills/ 아래 SKILL.md 파일들을 읽어 DB에 인덱싱한다.

사용법:
  python3 hermes-index-skills.py --db PATH --skills-dir PATH
"""

import argparse
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_skills import iter_skill_files, extract_keywords


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def index_skills(db_path: str, skills_dir: str, scope: str = "harness"):
    if not os.path.isfile(db_path):
        print(f"[hermes] DB not found: {db_path}")
        return 0

    if not os.path.isdir(skills_dir):
        return 0

    con = connect_db(db_path)
    indexed = 0

    # 공유 헬퍼로 평면 .md 및 폴더형 SKILL.md 를 함께 순회한다 (M4).
    for name, skill_md in iter_skill_files(skills_dir):
        kws = extract_keywords(skill_md)
        keywords = ",".join(sorted(kws)) if kws else name

        # M3 — INSERT OR REPLACE 는 used_count/version/created_at 을 리셋하므로
        # ON CONFLICT ... DO UPDATE 로 키워드·스코프만 갱신해 사용 통계를 보존한다.
        con.execute(
            "INSERT INTO skill_index (skill_path, keywords, scope) "
            "VALUES (?, ?, ?) "
            "ON CONFLICT(skill_path) DO UPDATE SET "
            "keywords = excluded.keywords, scope = excluded.scope",
            (skill_md, keywords, scope),
        )
        indexed += 1

    con.commit()
    con.close()
    print(f"[hermes] indexed {indexed} skills from {skills_dir}")
    return indexed


def main():
    parser = argparse.ArgumentParser(description="헤르메스 스킬 인덱싱")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--skills-dir", required=True, help=".claude/skills 경로")
    parser.add_argument("--scope", default="harness", help="스킬 범위 (harness/local)")
    args = parser.parse_args()

    index_skills(args.db, args.skills_dir, args.scope)


if __name__ == "__main__":
    main()
