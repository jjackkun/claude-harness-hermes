#!/usr/bin/env python3
"""옛 주입 원장의 잡음(내부 모델 호출 세션의 행)을 정리한다 — 기본은 미리보기, --apply 일 때만 지운다.

내부 호출은 대화 기록 앞부분의 진입 표시(entrypoint)가 `sdk-cli` 인 세션으로만 가른다(사람 세션은 `cli`).
프롬프트 문구로 추측하지 않는다. 기록 파일이 없거나 진입 표시를 못 읽으면 지우지 않는다.
이미 판정이 끝난 행(correlated=1)은 도움·소용없음 누계와 어긋나므로 지우지 않고 알린다.
--apply 는 지우기 직전 DB 를 `state.db.bak-<날짜>` 로 복사하고, used_count 를 원장 행 수로 다시 센다.

사용: python3 scripts/hermes-yield-repair.py [--db .hermes/state.db] [--projects-dir ~/.claude/projects] [--apply]
"""

import argparse
import glob
import json
import os
import shutil
import sqlite3
import sys
from datetime import date

ENTRYPOINT_SCAN_LINES = 60  # 실측: 진입 표시는 기록 앞 10줄 안에 나온다 — 여유를 두고 60줄까지만 본다


def find_transcript(projects_dir: str, session_id: str) -> str:
    hits = glob.glob(os.path.join(projects_dir, "*", f"{session_id}.jsonl"))
    return hits[0] if hits else ""


def read_entrypoint(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i >= ENTRYPOINT_SCAN_LINES:
                    break
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(obj, dict) and obj.get("entrypoint"):
                    return str(obj["entrypoint"])
    except OSError:
        return ""
    return ""


def classify(con, projects_dir: str) -> dict:
    """세션별로 internal(지울 수 있음) / kept(사람 세션) / unknown(기록 없음·표시 없음) 으로 가른다."""
    out = {"internal": [], "kept": [], "unknown": []}
    for (sid,) in con.execute("SELECT DISTINCT session_id FROM skill_injection").fetchall():
        path = find_transcript(projects_dir, sid)
        entry = read_entrypoint(path) if path else ""
        bucket = "unknown" if not entry else ("internal" if entry == "sdk-cli" else "kept")
        out[bucket].append(sid)
    return out


def judged_rows(con, sids: list) -> int:
    if not sids:
        return 0
    marks = ",".join("?" * len(sids))
    return con.execute(
        f"SELECT COUNT(*) FROM skill_injection WHERE correlated=1 AND session_id IN ({marks})", sids
    ).fetchone()[0]


def recount_used(con) -> None:
    con.execute(
        "UPDATE skill_index SET used_count = "
        "(SELECT COUNT(*) FROM skill_injection WHERE skill_injection.skill_path = skill_index.skill_path)"
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default=".hermes/state.db")
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--apply", action="store_true", help="실제로 지운다(기본은 미리보기)")
    args = ap.parse_args()
    if not os.path.isfile(args.db):
        print(f"DB 없음: {args.db}", file=sys.stderr)
        return 2
    con = sqlite3.connect(args.db)
    groups = classify(con, args.projects_dir)
    internal = [s for s in groups["internal"]]
    marks = ",".join("?" * len(internal))
    rows = con.execute(f"SELECT COUNT(*) FROM skill_injection WHERE session_id IN ({marks})", internal).fetchone()[0] if internal else 0
    skipped = judged_rows(con, internal)
    print(f"내부 호출 세션 {len(internal)}개 · 원장 행 {rows}개 (그중 판정 끝남 {skipped}개는 지우지 않음)")
    print(f"사람 세션 {len(groups['kept'])}개 · 기록을 못 읽어 건드리지 않는 세션 {len(groups['unknown'])}개")
    if not args.apply:
        print("미리보기입니다. 지우려면 --apply 를 붙이십시오. (DB 는 바뀌지 않았습니다)")
        return 0
    backup = f"{args.db}.bak-{date.today().isoformat()}"
    shutil.copy2(args.db, backup)
    cur = con.execute(
        f"DELETE FROM skill_injection WHERE COALESCE(correlated, 0) != 1 AND session_id IN ({marks})", internal
    ) if internal else None
    recount_used(con)
    con.commit()
    print(f"지운 행 {cur.rowcount if cur else 0}개 · 백업 {backup} · used_count 를 원장 행 수로 다시 셌습니다")
    return 0


if __name__ == "__main__":
    sys.exit(main())
