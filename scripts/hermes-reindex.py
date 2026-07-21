#!/usr/bin/env python3
"""JSONL 대화 원본 → SQLite 재색인 스크립트.

다른 컴퓨터에서 pull 한 .hermes/history/*.jsonl 텍스트를 읽어
session_history(FTS5)를 세션 단위로 재색인한다. 검색·드리밍·회상을
즉시 되살리는 것이 목적이다.

★데이터 안전이 이 스크립트의 존재 이유다. "DELETE 후 재삽입" 과
  "깨진 라인 스킵" 을 그대로 결합하면 손상된 JSONL 이 멀쩡한 DB 를 지운다.
  → 2중 가드:
    1) 파싱 실패가 1건이라도 있는 세션은 통째로 건너뛴다(DELETE 조차 안 함).
    2) 파싱된 라인 수 < 기존 DB 행 수 이면 --force 없이는 교체를 거부한다.
  텍스트에 없는 세션의 DB 행은 애초에 손대지 않는다.

사용법:
  python3 hermes-reindex.py --db PATH --project PATH [--backfill] [--force]
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


def collect_sessions(hist_dir: str) -> dict:
    """.hermes/history/*.jsonl 을 세션 단위로 수집한다.

    파일명이 아니라 각 라인의 session_id 필드로 그룹핑한다(파일명 변조에 견고).
    파일에 파싱 실패 라인이 하나라도 있으면 그 파일이 기여한 모든 세션을
    tainted 로 표시해 이후 재색인에서 통째로 건너뛴다(안전 가드 1).

    반환: {session_id: {"records": [obj, ...], "tainted": bool}}
    """
    sessions = {}
    for path in sorted(glob.glob(os.path.join(hist_dir, "*.jsonl"))):
        file_records = []
        had_parse_error = False
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        had_parse_error = True
                        continue
                    sid = obj.get("session_id")
                    if not sid:
                        # session_id 없는 라인도 손상으로 간주(귀속 불가)
                        had_parse_error = True
                        continue
                    file_records.append(obj)
        except OSError as e:
            print(f"[hermes] history 파일 읽기 실패: {path}: {e}", file=sys.stderr)
            continue

        # 이 파일이 기여한 세션들. 파싱 실패가 있으면 해당 세션 전부 tainted.
        sids_in_file = {r["session_id"] for r in file_records}
        for sid in sids_in_file:
            s = sessions.setdefault(sid, {"records": [], "tainted": False})
            s["records"].extend(r for r in file_records if r["session_id"] == sid)
            if had_parse_error:
                s["tainted"] = True
        # 남은 좋은 라인이 전혀 없으면(전부 손상) 귀속할 세션이 없어 무동작 — 안전.
    return sessions


def _reindex_session(con: sqlite3.Connection, session_id: str,
                     records: list, force: bool) -> int:
    """가드를 통과한 한 세션을 DELETE + seq 순 INSERT 로 교체한다.

    반환값: 삽입한 행 수. 가드에 걸려 건너뛰면 -1.
    """
    records = sorted(records, key=lambda r: r.get("seq", 0))
    existing = con.execute(
        "SELECT COUNT(*) FROM session_history WHERE session_id = ?",
        (session_id,),
    ).fetchone()[0]

    # 안전 가드 2 — 행 수 감소 방어. 손상·구버전 텍스트가 최신 DB 를 지우는 것을 막는다.
    if len(records) < existing and not force:
        print(
            f"[hermes] 재색인 거부(행 수 감소): {session_id} "
            f"텍스트 {len(records)}행 < DB {existing}행 — --force 필요",
            file=sys.stderr,
        )
        return -1

    cur = con.cursor()
    cur.execute("BEGIN IMMEDIATE")
    try:
        cur.execute("DELETE FROM session_history WHERE session_id = ?", (session_id,))
        for r in records:
            cur.execute(
                "INSERT INTO session_history "
                "(content, role, timestamp, project_id, session_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (
                    r.get("content", ""),
                    r.get("role", ""),
                    r.get("timestamp", ""),
                    r.get("project_id", ""),
                    session_id,
                ),
            )
        cur.execute("COMMIT")
    except Exception:
        try:
            cur.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        raise
    return len(records)


def _export_db_session(con: sqlite3.Connection, hist_dir: str, session_id: str) -> int:
    """DB 에만 있는 세션을 JSONL 로 역-export 한다(hermes-export-history.py 로직 복제, D5)."""
    rows = con.execute(
        "SELECT content, role, timestamp, project_id FROM session_history "
        "WHERE session_id = ?",
        (session_id,),
    ).fetchall()
    if not rows:
        return 0
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


def reindex(db_path: str, project_dir: str, backfill: bool = False,
            force: bool = False) -> int:
    if not os.path.isfile(db_path):
        print(f"[hermes] DB not found: {db_path}", file=sys.stderr)
        return 0

    hist_dir = os.path.join(project_dir, ".hermes", "history")
    os.makedirs(hist_dir, exist_ok=True)

    sessions = collect_sessions(hist_dir)
    con = connect_db(db_path)
    con.isolation_level = None  # 명시적 트랜잭션 제어
    reindexed = 0
    try:
        for sid, data in sessions.items():
            if data["tainted"]:
                # 안전 가드 1 — 파싱 실패 세션은 통째로 건너뛴다(DELETE 조차 안 함).
                print(
                    f"[hermes] 재색인 스킵(손상 텍스트): {sid} — DB 원본 보존",
                    file=sys.stderr,
                )
                continue
            n = _reindex_session(con, sid, data["records"], force)
            if n >= 0:
                reindexed += n

        if backfill:
            # DB 에만 있고 텍스트에 없는 세션을 역-export 로 보정한다.
            text_sids = set(sessions.keys())
            db_sids = [
                r[0] for r in con.execute(
                    "SELECT DISTINCT session_id FROM session_history"
                ) if r[0]
            ]
            for sid in db_sids:
                if sid not in text_sids:
                    _export_db_session(con, hist_dir, sid)
    finally:
        con.close()

    print(f"[hermes] reindex 완료: {reindexed} messages / {len(sessions)} sessions ← {hist_dir}")
    return reindexed


def main():
    parser = argparse.ArgumentParser(description="헤르메스 JSONL → SQLite 재색인")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--project", required=True, help="프로젝트 루트 경로")
    parser.add_argument("--backfill", action="store_true",
                        help="DB 에만 있고 텍스트에 없는 세션을 역-export")
    parser.add_argument("--force", action="store_true",
                        help="행 수 감소 가드를 무시하고 교체")
    args = parser.parse_args()

    # 예외는 stderr 로만 알리고 항상 exit 0(훅 파이프라인·세션 시작을 막지 않음).
    try:
        reindex(args.db, args.project, args.backfill, args.force)
    except Exception as e:
        print(f"[hermes] reindex 실패: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
