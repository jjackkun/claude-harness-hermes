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
그래서 (1) --all 명시 동의, (2) export_session 의 압축본 덮어쓰기 거부 가드,
(3) compacted 마커 보존 — 세 겹으로 막는다.
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


COMPACT_KEYS = ("compacted", "orig_lines")

DIVERGED_HINT = (
    "이 기계는 파일·DB 발산 상태다(다른 기계의 압축본을 pull 했고 로컬 DB 는 원문). "
    "압축을 수용하려면: python3 scripts/hermes-reindex.py "
    "--db <state.db> --project <프로젝트> --force"
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


def export_session(con: sqlite3.Connection, hist_dir: str, session_id: str) -> int:
    """한 세션을 JSONL 로 전량 재작성한다. 반환값은 기록한 라인 수.

    압축본(1행) 위에 DB 원문(N행)을 덮어쓰려는 시도는 세션 단위로 스킵한다 —
    그 덮어쓰기가 fleet 전체의 압축을 되돌리는 유일한 경로다(전체 실패는 아니다).

    ★"발산"과 "압축 세션 재개"는 **파일의 요약이 DB 안에 실재하는가** 하나로 가른다:
      - 요약이 DB 에 있다 → 이 기계가 압축한 세션이다. 행이 늘었다면 `--resume` 으로
        이어간 신규 대화이므로 정상 export 한다(스킵하면 새 대화가 영영 git 밖에 갇힌다).
        파일은 여러 행이 되므로 compacted 마커는 자연히 사라지는 게 맞다.
      - 요약이 DB 에 없다 → 타 기계의 압축본을 pull 한 발산이다. 스킵 + 경고.
      같은 술어가 마커 물려주기(carry)에도 쓰인다 — DB 1행이 그 요약 자신일 때만
      마커를 잇는다. 원문 1행에 마커를 붙이면 다음 기계에서 이 가드가 오작동한다.
    """
    # ORDER BY 없음 — FTS5 에는 순서 복원용 안정 키가 없으므로
    # 삽입 순서(=원본 대화 순서)인 SELECT 결과 순서에 seq 를 부여한다.
    rows = con.execute(
        "SELECT content, role, timestamp, project_id FROM session_history "
        "WHERE session_id = ?",
        (session_id,),
    ).fetchall()
    if not rows:
        return 0

    compacted = _compacted_record(hist_dir, session_id)
    # 파일의 요약이 DB 행 중에 실재하는가 — 재개(있음)와 발산(없음)을 가르는 술어.
    summary_in_db = compacted is not None and any(
        r[0] == compacted.get("content") for r in rows)
    if compacted is not None and len(rows) > 1 and not summary_in_db:
        print("[hermes] %s: 압축본(파일 1행) 덮어쓰기 거부 — DB %d행. %s"
              % (session_id, len(rows), DIVERGED_HINT), file=sys.stderr)
        return 0
    # 압축 직후(파일 1행 ⟺ DB 1행 = 그 요약)는 정상 export 한다. 다만 compacted/
    # orig_lines 는 session_history 5컬럼에 없어 재작성에 소실되므로 명시적으로
    # 물려준다 — 이 마커가 사라지면 다음 기계에서 덮어쓰기 거부 가드가 무력해진다.
    # DB 1행이 요약 자신일 때만 잇는다. 원문 1행에 붙이면 거짓 마커가 된다.
    carry = {k: compacted[k] for k in COMPACT_KEYS
             if compacted is not None and summary_in_db and len(rows) == 1
             and k in compacted}

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
                **carry,
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
    parser.add_argument("--session", help="세션 ID")
    parser.add_argument("--all", action="store_true",
                        help="전 세션 전량 export(DB→파일 전량 재작성) — 초기 백필용")
    args = parser.parse_args()

    if not args.session and not args.all:
        print("[hermes] 전량 export 는 DB→파일 전량 재작성이라 다른 기계에서 압축된 "
              "요약본을 원문으로 되돌릴 수 있다. 대상을 명시하라:\n"
              "  특정 세션만: --session <ID>\n"
              "  전량이 맞다면(초기 백필): --all", file=sys.stderr)
        sys.exit(2)

    # 훅 파이프라인을 막지 않도록 예외는 stderr 로만 알리고 항상 exit 0.
    try:
        export_history(args.db, args.project, args.session)
    except Exception as e:
        print(f"[hermes] history export 실패: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
