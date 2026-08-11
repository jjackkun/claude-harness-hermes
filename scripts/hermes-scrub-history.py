#!/usr/bin/env python3
"""이미 적재·기록된 세션 기록에서 평문 비밀을 소급 제거하는 책임만 진다.

왜 필요한가: 마스킹 보강은 *이후* 입력에만 적용된다. 보강 이전에 DB 에 들어간 행과
파일로 나간 jsonl 은 그대로 남는다. 그 파일이 곧 커밋 대상이므로 소급 정리가 없으면
새 커밋마다 옛 평문이 다시 실려 나간다.

★파괴적이므로 dry-run 이 기본이다. 실제 치환은 `--apply` 를 명시해야 한다.
★값은 절대 출력하지 않는다 — 무엇이 몇 건 바뀌는지만 알린다.
★멱등하다 — 두 번 돌려도 두 번째는 변경 0건이다(redact 결과가 다시 매치되지 않음).

이 도구는 **로컬 파일과 DB 만 고친다.** 이미 push 된 git 히스토리는 되돌리지
않는다 — 그건 저장소 소유자의 판단(히스토리 재작성 또는 자격증명 교체) 몫이다.

사용법:
    python3 hermes-scrub-history.py --db PATH --project PATH          # 미리보기
    python3 hermes-scrub-history.py --db PATH --project PATH --apply  # 실제 치환
"""

import argparse
import glob
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1).

    (hermes 스크립트들은 독립 배포되므로 각 파일에 동일 함수를 복제한다)
    """
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def scrub_db(db_path: str, project_dir: str, apply: bool) -> int:
    """session_history 의 오염 행을 치환한다. 반환값은 바뀐(바뀔) 행 수."""
    if not os.path.isfile(db_path):
        print(f"[hermes] DB 없음 — 건너뜀: {db_path}", file=sys.stderr)
        return 0

    con = connect_db(db_path)
    try:
        rows = con.execute("SELECT rowid, content FROM session_history").fetchall()
        dirty = []
        for rid, content in rows:
            safe = redact(content, project_dir)
            if safe != content:
                dirty.append((rid, safe))
        if dirty and apply:
            con.executemany(
                "UPDATE session_history SET content = ? WHERE rowid = ?",
                [(safe, rid) for rid, safe in dirty],
            )
            con.commit()
    finally:
        con.close()
    return len(dirty)


def _scrub_jsonl(path: str, project_dir: str, apply: bool) -> int:
    """파일 하나를 치환한다. 반환값은 바뀐(바뀔) 줄 수.

    content 외의 키(seq·compacted·orig_lines 등)는 그대로 보존한다 — 압축 마커가
    사라지면 export 의 덮어쓰기 거부 가드가 무력해진다.
    """
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, UnicodeDecodeError):
        print(f"[hermes] 읽기 실패 — 건너뜀: {os.path.basename(path)}", file=sys.stderr)
        return 0

    changed = 0
    out = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            out.append(line)
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            out.append(line)      # 손상 줄은 손대지 않는다 — 파괴적 변경 금지.
            continue
        content = obj.get("content")
        safe = redact(content, project_dir)
        if safe != content:
            obj["content"] = safe
            changed += 1
            out.append(json.dumps(obj, ensure_ascii=False) + "\n")
        else:
            out.append(line)

    if changed and apply:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.writelines(out)
        os.replace(tmp, path)     # 원자적 교체 — 중단돼도 반쪽 파일이 남지 않는다.
    return changed


def scrub_files(project_dir: str, apply: bool) -> tuple:
    """.hermes/history/*.jsonl 전량 치환. 반환값은 (바뀐 줄 수, 바뀐 파일 수)."""
    hist_dir = os.path.join(project_dir, ".hermes", "history")
    total_lines = 0
    total_files = 0
    for path in sorted(glob.glob(os.path.join(hist_dir, "*.jsonl"))):
        changed = _scrub_jsonl(path, project_dir, apply)
        if changed:
            total_lines += changed
            total_files += 1
    return total_lines, total_files


def main():
    parser = argparse.ArgumentParser(
        description="세션 기록(DB·jsonl)의 평문 비밀 소급 제거")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--project", required=True, help="프로젝트 루트 경로")
    parser.add_argument("--apply", action="store_true",
                        help="실제로 치환한다 (없으면 미리보기만)")
    args = parser.parse_args()

    db_rows = scrub_db(args.db, args.project, args.apply)
    file_lines, file_count = scrub_files(args.project, args.apply)

    verb = "치환함" if args.apply else "치환 예정"
    print(f"[hermes] session_history {db_rows}행 {verb}")
    print(f"[hermes] .hermes/history {file_lines}줄 / {file_count}파일 {verb}")
    if not args.apply and (db_rows or file_lines):
        print("[hermes] 미리보기다. 실제로 고치려면 --apply 를 붙여라.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
