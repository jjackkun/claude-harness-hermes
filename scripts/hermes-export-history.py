#!/usr/bin/env python3
"""대화 원본(session_history)을 git 텍스트로 빼내는 스크립트.

Stop 훅에서 매 턴 호출된다. SQLite 에 갇힌 핑퐁을 .hermes/history/*.jsonl 로
전량 재작성해 다른 컴퓨터로 이식 가능하게 만든다.

사용법:
  python3 hermes-export-history.py --db PATH --project PATH [--session ID]
  (--session 미지정 시 DB 의 모든 세션을 export — 초기 백필용)
"""

import argparse
import glob
import json
import os
import sqlite3
import sys

UNKNOWN_DATE = "unknown-date"


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1).

    (hermes 스크립트들은 독립 배포되므로 각 파일에 동일 함수를 복제한다)
    """
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _date_prefix(timestamp: str) -> str:
    """timestamp 앞 10자(YYYY-MM-DD). 형식이 다르면 unknown-date."""
    ts = timestamp or ""
    if len(ts) >= 10 and ts[4] == "-" and ts[7] == "-":
        return ts[:10]
    return UNKNOWN_DATE


def export_session(con: sqlite3.Connection, hist_dir: str, session_id: str) -> int:
    """한 세션을 JSONL 로 전량 재작성한다. 반환값은 기록한 라인 수."""
    # ORDER BY 없음 — FTS5 에는 순서 복원용 안정 키가 없으므로
    # 삽입 순서(=원본 대화 순서)인 SELECT 결과 순서에 seq 를 부여한다.
    rows = con.execute(
        "SELECT content, role, timestamp, project_id FROM session_history "
        "WHERE session_id = ?",
        (session_id,),
    ).fetchall()
    if not rows:
        return 0

    # 세션이 자정을 넘기면 날짜 접두가 바뀌므로, 같은 세션의 기존 파일을
    # 모두 지운 뒤 새로 쓴다 — 세션당 파일 정확히 1개 보장.
    for old in glob.glob(os.path.join(hist_dir, "*-%s.jsonl" % session_id)):
        os.remove(old)

    path = os.path.join(hist_dir, "%s-%s.jsonl" % (_date_prefix(rows[0][2]), session_id))
    with open(path, "w", encoding="utf-8") as f:
        for seq, (content, role, timestamp, project_id) in enumerate(rows):
            f.write(json.dumps({
                "seq": seq,
                "session_id": session_id,
                "project_id": project_id,
                "role": role,
                "timestamp": timestamp,
                "content": content,
            }, ensure_ascii=False) + "\n")
    return len(rows)


def export_history(db_path: str, project_dir: str, session_id: str = None) -> int:
    if not os.path.isfile(db_path):
        print(f"[hermes] DB not found: {db_path}", file=sys.stderr)
        return 0

    hist_dir = os.path.join(project_dir, ".hermes", "history")
    os.makedirs(hist_dir, exist_ok=True)

    con = connect_db(db_path)
    try:
        if session_id:
            targets = [session_id]
        else:
            targets = [
                r[0] for r in con.execute(
                    "SELECT DISTINCT session_id FROM session_history"
                ) if r[0]
            ]
        exported = sum(export_session(con, hist_dir, sid) for sid in targets)
    finally:
        con.close()

    print(f"[hermes] history exported: {exported} messages / {len(targets)} sessions → {hist_dir}")
    return exported


def main():
    parser = argparse.ArgumentParser(description="헤르메스 대화 원본 텍스트 export")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--project", required=True, help="프로젝트 루트 경로")
    parser.add_argument("--session", help="세션 ID (미지정 시 전 세션)")
    args = parser.parse_args()

    # 훅 파이프라인을 막지 않도록 예외는 stderr 로만 알리고 항상 exit 0.
    try:
        export_history(args.db, args.project, args.session)
    except Exception as e:
        print(f"[hermes] history export 실패: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
