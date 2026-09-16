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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_history_fragments import (  # noqa: E402
    active_fragments, exported_line_count, write_fragment)

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


def _history_inputs(hist_dir: str):
    """(레거시 평평한 파일들, 조각 파일들). 압축이 대체한 조각은 빼고 돌려준다(목표 12)."""
    flat = sorted(glob.glob(os.path.join(hist_dir, "*.jsonl")))
    frag_files = []
    for d in sorted(glob.glob(os.path.join(hist_dir, "*"))):
        if os.path.isdir(d):
            frag_files.extend(active_fragments(hist_dir, os.path.basename(d)))
    return flat, frag_files


def _read_jsonl(path: str):
    """(레코드들, 손상 여부). session_id 없는 줄도 손상으로 본다(귀속 불가)."""
    records, bad = [], False
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    bad = True
                    continue
                if not obj.get("session_id"):
                    bad = True
                    continue
                records.append(obj)
    except OSError as e:
        print(f"[hermes] history 파일 읽기 실패: {path}: {e}", file=sys.stderr)
        return None, False
    return records, bad


def collect_sessions(hist_dir: str) -> dict:
    """.hermes/history/*.jsonl 을 세션 단위로 수집한다.

    파일명이 아니라 각 라인의 session_id 필드로 그룹핑한다(파일명 변조에 견고).
    파일에 파싱 실패 라인이 하나라도 있으면 그 파일이 기여한 모든 세션을
    tainted 로 표시해 이후 재색인에서 통째로 건너뛴다(안전 가드 1).

    반환: {session_id: {"records": [obj, ...], "tainted": bool}}
    """
    sessions = {}
    by_source = {}          # {sid: {"flat": [...], "frag": [...], "tainted": bool}}
    # 평평한 레거시 파일(`<날짜>-<세션>.jsonl`)과 턴 조각(`<세션>/<순번>.jsonl`)을 함께 읽는다.
    # 조각이 새 형식이고 레거시는 읽기 전용으로 남는다(계획 3 Step 1).
    flat, frag_files = _history_inputs(hist_dir)
    for path in flat + frag_files:
        file_records, had_parse_error = _read_jsonl(path)
        if file_records is None:
            continue
        source = "flat" if path in flat else "frag"
        for sid in {r["session_id"] for r in file_records}:
            bucket = by_source.setdefault(sid, {"flat": [], "frag": [], "tainted": False})
            bucket[source].extend(r for r in file_records if r["session_id"] == sid)
            if had_parse_error:
                bucket["tainted"] = True
        # 남은 좋은 라인이 전혀 없으면(전부 손상) 귀속할 세션이 없어 무동작 — 안전.

    # 한 세션이 레거시 파일과 조각 양쪽에 있으면 **기록이 더 많은 쪽**을 택한다.
    # 둘을 합치면 같은 대화가 두 번 들어가고, 적은 쪽을 택하면 사람이 복구해 둔 원문
    # (git blob → 레거시 파일)이 요약 조각에 가려 사라진다. 재색인의 기존 태도(행을
    # 잃지 않는다, 행수감소 가드)와 같은 규칙이다. 2026-09-16 실측으로 드러났다.
    for sid, bucket in by_source.items():
        chosen = bucket["frag"] if len(bucket["frag"]) >= len(bucket["flat"]) else bucket["flat"]
        sessions[sid] = {"records": chosen, "tainted": bucket["tainted"]}
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
    """DB 에만 있는 세션을 턴 조각으로 역-export 한다(hermes-export-history.py 와 같은 규칙, D5)."""
    rows = con.execute(
        "SELECT content, role, timestamp, project_id FROM session_history "
        "WHERE session_id = ?",
        (session_id,),
    ).fetchall()
    if not rows:
        return 0
    # 조각으로 내보낸다(추가 전용). 이미 내보낸 줄은 건너뛰므로 기존 조각을 지우지 않는다.
    already = exported_line_count(hist_dir, session_id)
    fresh = rows[already:]
    if not fresh:
        return 0
    write_fragment(hist_dir, session_id, [{
        "seq": already + i,
        "session_id": session_id,
        "project_id": project_id,
        "role": role,
        "timestamp": timestamp,
        "content": content,
    } for i, (content, role, timestamp, project_id) in enumerate(fresh)])
    return len(fresh)


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
