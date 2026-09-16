#!/usr/bin/env python3
"""대화 원본(session_history)을 git 텍스트로 빼내는 스크립트.

Stop 훅에서 매 턴 호출된다. SQLite 에 갇힌 핑퐁을 .hermes/history/*.jsonl 로
전량 재작성해 다른 컴퓨터로 이식 가능하게 만든다.

사용법:
  python3 hermes-export-history.py --db PATH --project PATH --session ID
  python3 hermes-export-history.py --db PATH --project PATH --all   # 초기 백필용

★전량 모드(--all)가 명시 동의를 요구하는 이유: 전량 export 는 DB→파일 전량
재작성이다. 다른 기계가 압축(Part D)한 요약본을 pull 한 상태에서 무심코 돌리면
로컬 DB 의 원문이 요약본 파일을 덮어써 fleet 전체의 압축이 되돌아간다.
그래서 (1) --all 명시 동의, (2) --all 의 압축본 덮어쓰기 거부 가드,
(3) compacted 마커 보존 — 세 겹으로 막는다.

★거부 가드가 --all 전용인 이유: --session 은 Stop 훅이 **지금 살아있는 세션**에만
넘긴다. 압축된 세션을 --resume 했다는 것은 그 세션을 다시 쓰고 있다는 뜻이고,
곧 Part D 압축 게이트 ②(미사용)가 깨졌다는 뜻이다. 그러므로 압축 해제가 정상
동작이다(원문은 로컬 transcript 에 온전하다). 여기서 스킵하면 재개 후 나눈 신규
대화가 파일·git 어디에도 나가지 못하고 DB 에만 갇힌다 — 그 상태에서 재색인
--force 안내를 따르면 영구 소실된다. 되돌림 위험이 실재하는 곳은 "타 기계에서
전량 재작성"뿐이므로 가드는 거기에만 건다.
"""

import argparse
import glob
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_history_fragments import exported_line_count, write_fragment
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)

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


COMPACT_KEYS = ("compacted", "orig_lines")

DIVERGED_HINT = (
    "이 기계는 파일·DB 발산 상태다(다른 기계의 압축본을 pull 했고 로컬 DB 는 원문). "
    "압축을 수용하려면: python3 scripts/hermes-reindex.py "
    "--db <state.db> --project <프로젝트> --force "
    "⚠ 주의: --force 는 세션 단위가 아니라 전역이다. 파일이 DB 보다 뒤처진 다른 "
    "세션이 있으면 그 원문까지 파일 기준으로 덮어써 소실된다. 뒤처진 세션을 먼저 "
    "--session 으로 동기화·커밋한 뒤 실행하라."
)

DECOMPACT_NOTICE = (
    "압축 해제 — 압축된 세션이 재개돼 DB 가 원문으로 돌아왔다. 파일을 원문으로 "
    "재작성한다(원문은 압축 전 커밋에 보존돼 있다). 재개하지 않았는데 이 메시지가 "
    "보이면 --session 대상 세션 id 를 확인하라."
)


def _compacted_record(hist_dir: str, session_id: str):
    """이 세션의 기존 파일이 '정확히 1행 + compacted:true' 압축본이면 그 레코드.

    아니면 None. 압축본 여부는 Part D `--apply` 가 남긴 최상위 마커로 판정한다.
    (동일 기준이 assets/hooks/claude-sessionstart-history-reindex.sh 게이트 5 에도
     중복 구현돼 있다 — 훅은 하네스와 독립 실행이라 import 할 수 없다. 한쪽을
     바꾸면 다른 쪽도 바꿀 것.)
    """
    for path in sorted(glob.glob(os.path.join(hist_dir, "*-%s.jsonl" % session_id))):
        try:
            with open(path, encoding="utf-8") as f:
                lines = [l for l in f if l.strip()]
        except OSError:
            continue
        if len(lines) != 1:
            continue
        try:
            obj = json.loads(lines[0])
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and obj.get("compacted") is True:
            return obj
    return None


def export_session(con: sqlite3.Connection, hist_dir: str, session_id: str,
                   guard_overwrite: bool = False, project_dir: str = None) -> int:
    """아직 조각으로 내보내지 않은 줄만 **새 조각 하나**로 쓴다. 반환값은 그 줄 수.

    전에는 세션 하나를 파일 하나로 전량 재작성했다. 그래서 압축본을 원문으로 되돌리는
    사고 경로가 있었고 덮어쓰기 가드가 필요했다. 조각은 한 번 쓰면 바뀌지 않으므로
    그 경로 자체가 없어진다 — 가드도 함께 사라졌다(guard_overwrite 는 호출 호환용).
    계획: 2026-09-15-sync-transport-encryption 목표 2
    """
    # ORDER BY 없음 — FTS5 에 순서 복원용 안정 키가 없어 삽입 순서(=대화 순서)를 쓴다.
    rows = con.execute(
        "SELECT content, role, timestamp, project_id FROM session_history "
        "WHERE session_id = ?",
        (session_id,),
    ).fetchall()
    if not rows:
        return 0

    # ★다층 방어 — DB 적재 경계의 마스킹을 믿지 않는다. 조각은 원격으로 나가는 것이므로
    # 여기가 되돌릴 수 없는 마지막 경계다.
    rows = [(redact(content, project_dir), role, timestamp, project_id)
            for content, role, timestamp, project_id in rows]

    already = exported_line_count(hist_dir, session_id)
    fresh = rows[already:]
    if not fresh:
        return 0

    records = [{
        "seq": already + i,
        "session_id": session_id,
        "project_id": project_id,
        "role": role,
        "timestamp": timestamp,
        "content": content,
    } for i, (content, role, timestamp, project_id) in enumerate(fresh)]
    write_fragment(hist_dir, session_id, records)
    return len(records)


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
        # 덮어쓰기 거부 가드는 전량 재작성(--all)에만 건다 — export_session docstring 참조.
        guard = session_id is None
        exported = sum(export_session(con, hist_dir, sid, guard, project_dir)
                       for sid in targets)
    finally:
        con.close()

    print(f"[hermes] history exported: {exported} messages / {len(targets)} sessions → {hist_dir}")
    return exported


def main():
    parser = argparse.ArgumentParser(description="헤르메스 대화 원본 텍스트 export")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--project", required=True, help="프로젝트 루트 경로")
    parser.add_argument("--session", help="세션 ID")
    parser.add_argument("--all", action="store_true",
                        help="전 세션의 새 줄을 조각으로 — 초기 백필용")
    args = parser.parse_args()

    if not args.session and not args.all:
        print("[hermes] 대상을 명시하라:\n"
              "  특정 세션만: --session <ID>\n"
              "  전 세션(초기 백필): --all", file=sys.stderr)
        sys.exit(2)

    # 훅 파이프라인을 막지 않도록 예외는 stderr 로만 알리고 항상 exit 0.
    try:
        export_history(args.db, args.project, args.session)
    except Exception as e:
        print(f"[hermes] history export 실패: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
