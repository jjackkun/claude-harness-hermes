#!/usr/bin/env python3
"""헤르메스 SQLite DB 초기화 스크립트.

사용법:
  python3 hermes-init.py --global        # ~/.hermes/global.db 초기화
  python3 hermes-init.py --project PATH  # [PATH]/.hermes/state.db 초기화
  python3 hermes-init.py --both PATH     # 둘 다
"""

import argparse
import os
import sqlite3
import sys


GLOBAL_DB_DIR = os.path.expanduser("~/.hermes")
GLOBAL_DB_PATH = os.path.join(GLOBAL_DB_DIR, "global.db")


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def init_global_db():
    os.makedirs(GLOBAL_DB_DIR, exist_ok=True)
    os.makedirs(os.path.join(GLOBAL_DB_DIR, "skills"), exist_ok=True)
    os.makedirs(os.path.join(GLOBAL_DB_DIR, "mesh", "skills"), exist_ok=True)
    con = connect_db(GLOBAL_DB_PATH)
    _apply_schema(con, scope="global")
    con.close()
    print(f"[hermes] global DB initialized: {GLOBAL_DB_PATH}")


def init_project_db(project_path: str):
    db_dir = os.path.join(project_path, ".hermes")
    db_path = os.path.join(db_dir, "state.db")
    os.makedirs(db_dir, exist_ok=True)
    os.makedirs(os.path.join(db_dir, "skills"), exist_ok=True)
    con = connect_db(db_path)
    _apply_schema(con, scope="project")
    con.close()
    print(f"[hermes] project DB initialized: {db_path}")


def _apply_schema(con: sqlite3.Connection, scope: str):
    cur = con.cursor()

    # session_history — FTS5 전문 검색 (1층 세션 기억)
    cur.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS session_history USING fts5(
            content,
            role,
            timestamp UNINDEXED,
            project_id UNINDEXED,
            session_id UNINDEXED
        )
    """)

    # harness_rules — 결정화된 규칙 (2층 영구 기억)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS harness_rules (
            rule_id           INTEGER PRIMARY KEY AUTOINCREMENT,
            trigger_keywords  TEXT    NOT NULL,
            instruction       TEXT    NOT NULL,
            source_session_id TEXT,
            scope             TEXT    DEFAULT 'local',
            version           INTEGER DEFAULT 1,
            created_at        DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at        DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # skill_index — 스킬 파일 메타데이터 (3층 스킬 기억)
    # last_evolved_at: 진화 쿨다운 기준 시각 (H3)
    # helpful_count/noop_count: 재활용 측정 카운터 (U5)
    # state: 스킬 상태 (active/demoted), demoted_at: 강등 시각 (U5)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS skill_index (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            skill_path      TEXT    NOT NULL UNIQUE,
            keywords        TEXT    NOT NULL,
            scope           TEXT    DEFAULT 'local',
            version         INTEGER DEFAULT 1,
            created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
            used_count      INTEGER DEFAULT 0,
            last_evolved_at TEXT,
            helpful_count   INTEGER DEFAULT 0,
            noop_count      INTEGER DEFAULT 0,
            last_helpful_at TEXT,
            state           TEXT    DEFAULT 'active',
            demoted_at      TEXT
        )
    """)
    # 구버전 DB 마이그레이션 — 신규 컬럼 멱등 보강
    cols = [r[1] for r in cur.execute("PRAGMA table_info(skill_index)")]
    for col, ddl in (
        ("last_evolved_at", "ALTER TABLE skill_index ADD COLUMN last_evolved_at TEXT"),
        ("helpful_count",   "ALTER TABLE skill_index ADD COLUMN helpful_count INTEGER DEFAULT 0"),
        ("noop_count",      "ALTER TABLE skill_index ADD COLUMN noop_count INTEGER DEFAULT 0"),
        ("last_helpful_at", "ALTER TABLE skill_index ADD COLUMN last_helpful_at TEXT"),
        ("state",           "ALTER TABLE skill_index ADD COLUMN state TEXT DEFAULT 'active'"),
        ("demoted_at",      "ALTER TABLE skill_index ADD COLUMN demoted_at TEXT"),
    ):
        if col not in cols:
            cur.execute(ddl)

    # skill_injection — 주입 원장 (어떤 스킬을 어느 세션에 주입했나)
    # source: 어느 트리거로 주입됐나 — 'prompt'(UserPromptSubmit) | 'assist'(PostToolUse 실패 신호).
    # 경로별 효용을 분리 측정하기 위함 (C1 설계 §4.7).
    cur.execute("""
        CREATE TABLE IF NOT EXISTS skill_injection (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id  TEXT    NOT NULL,
            skill_path  TEXT    NOT NULL,
            injected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            correlated  INTEGER DEFAULT 0,
            source      TEXT    DEFAULT 'prompt'
        )
    """)
    # 구버전 DB 마이그레이션 — 기존 행은 SQLite 가 DEFAULT 로 채운다.
    inj_cols = [r[1] for r in cur.execute("PRAGMA table_info(skill_injection)")]
    if "source" not in inj_cols:
        cur.execute("ALTER TABLE skill_injection ADD COLUMN source TEXT DEFAULT 'prompt'")

    # messages — 에이전트 간 메시지 버스
    cur.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            from_agent  TEXT    NOT NULL,
            to_agent    TEXT    NOT NULL,
            content     TEXT    NOT NULL,
            status      TEXT    DEFAULT 'unread',
            created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # pattern_count — 반복 패턴 집계 (결정화 트리거용)
    # crystallized: 0=미결정화, 1=결정화 완료, -1=junk 거부 (재시도 안 함)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS pattern_count (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            pattern_key TEXT    NOT NULL UNIQUE,
            count       INTEGER DEFAULT 1,
            last_seen   DATETIME DEFAULT CURRENT_TIMESTAMP,
            crystallized INTEGER DEFAULT 0
        )
    """)

    # pattern_session — (패턴, 세션) 집계 기록: 같은 세션 재저장 시 중복 증가 방지 (C2)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS pattern_session (
            pattern_key TEXT NOT NULL,
            session_id  TEXT NOT NULL,
            PRIMARY KEY (pattern_key, session_id)
        )
    """)

    # session_summary — 핑퐁마다 갱신되는 5슬롯 롤링 요약 (세션당 1행)
    # last_msg_count: 델타 추적 — 지금까지 요약에 반영한 transcript 메시지 개수
    cur.execute("""
        CREATE TABLE IF NOT EXISTS session_summary (
            session_id     TEXT PRIMARY KEY,
            project_id     TEXT,
            slots_json     TEXT,
            last_msg_count INTEGER DEFAULT 0,
            turn_count     INTEGER DEFAULT 0,
            updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # recall_marker — 세션당 회상 자동주입 1회만 보장
    cur.execute("""
        CREATE TABLE IF NOT EXISTS recall_marker (
            session_id  TEXT PRIMARY KEY,
            injected_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # session_reuse — 세션 재활용 추적 (생애주기 린트 ② 미사용 신호, Part D)
    # session_id='__epoch__' 예약 행은 tracking_epoch 마커(추적 도입 원년) —
    # hermes_reuse.ensure_reuse_table 이 최초 1회 찍는다. 정본 DDL 은 여기.
    cur.execute("""
        CREATE TABLE IF NOT EXISTS session_reuse (
            session_id     TEXT PRIMARY KEY,
            last_reused_at TEXT,
            reuse_count    INTEGER DEFAULT 0
        )
    """)

    # compaction_log — 생애주기 압축 감사 기록 (무엇을·언제·왜 압축했는지, Part D)
    # hermes_lifecycle_apply 가 동일 DDL 로 자가수리한다. 정본은 여기.
    cur.execute("""
        CREATE TABLE IF NOT EXISTS compaction_log (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            run_at        DATETIME DEFAULT CURRENT_TIMESTAMP,
            cluster_topic TEXT,
            session_ids   TEXT,
            lines_before  INTEGER,
            lines_after   INTEGER,
            report_path   TEXT,
            reason        TEXT
        )
    """)

    # dream_log — 드리밍 실행 기록 (last_dream_at = MAX(run_at))
    cur.execute("""
        CREATE TABLE IF NOT EXISTS dream_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            run_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
            summary_count   INTEGER,
            crystallized    INTEGER,
            evolved         INTEGER,
            delete_proposed INTEGER,
            report_path     TEXT
        )
    """)

    # loops / loop_steps — 목표 기반 자율 루프 (hermes_loop 과 단일 DDL 공유, G13)
    try:
        from hermes_loop import LOOP_SCHEMA_STATEMENTS
        for ddl in LOOP_SCHEMA_STATEMENTS:
            cur.execute(ddl)
    except ImportError:
        print("[hermes] hermes_loop.py 없음 — loops 테이블 생성 건너뜀",
              file=sys.stderr)

    con.commit()


def main():
    parser = argparse.ArgumentParser(description="헤르메스 DB 초기화")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--global", dest="init_global", action="store_true",
                       help="~/.hermes/global.db 초기화")
    group.add_argument("--project", metavar="PATH",
                       help="[PATH]/.hermes/state.db 초기화")
    group.add_argument("--both", metavar="PATH",
                       help="global + project 둘 다 초기화")
    args = parser.parse_args()

    if args.init_global:
        init_global_db()
    elif args.project:
        init_project_db(os.path.abspath(args.project))
    elif args.both:
        init_global_db()
        init_project_db(os.path.abspath(args.both))


if __name__ == "__main__":
    main()
